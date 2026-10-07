import Foundation
import Security

final class LivePronoteClient: PronoteClient {
    private let credentials: PronoteCredentials
    private let options: PronoteLoginOptions
    private let transport: PronoteHTTPTransporting

    private var sessionClient: PronoteSessionClient?
    private var resource: [String: Any]?
    private var periods: [[String: Any]] = []
    private var schoolYearStart: Date?

    init(credentials: PronoteCredentials,
         options: PronoteLoginOptions = .init(),
         transport: PronoteHTTPTransporting = PronoteHTTPTransport()) {
        self.credentials = credentials
        self.options = options
        self.transport = transport
    }

    func getTimetable() async throws -> [TimetableEntry] {
        let client = try await connectedClient()
        let resource = try await loadResource(client)
        let start = schoolYearStart ?? Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 9, day: 1))!
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentWeek = max(1, 1 + max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0) / 7)

        var entries: [TimetableEntry] = []
        for week in currentWeek...min(currentWeek + 2, currentWeek + 2) {
            let response = try await client.timetable(weekNumber: week, resource: resource)
            entries.append(contentsOf: PronoteMapper.timetable(from: response))
        }
        return deduplicate(entries)
    }

    func getHomework() async throws -> [Homework] {
        let client = try await connectedClient()
        let resource = try await loadResource(client)
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 45, to: start) ?? start
        let response = try await client.homework(from: start, to: end, resource: resource)
        return PronoteMapper.homework(from: response)
    }

    func getGrades() async throws -> [Grade] {
        let client = try await connectedClient()
        _ = try await loadResource(client)
        if periods.isEmpty { return [] }
        var grades: [Grade] = []
        for period in periods {
            let response = try await client.grades(period: period)
            grades.append(contentsOf: PronoteMapper.grades(from: response))
        }
        return deduplicate(grades)
    }

    func profile() async throws -> PronoteProfile {
        let client = try await connectedClient()
        let parameters = try await loadUserParameters(client)
        return PronoteMapper.profile(from: parameters)
    }

    func refreshedMobileToken() async throws -> String? {
        let client = try await connectedClient()
        return client.mobileToken
    }

    private func connectedClient() async throws -> PronoteSessionClient {
        if let sessionClient { return sessionClient }

        let sessionParameters = try await transport.bootstrap(serverURL: credentials.serverURL)
        let functionClient = PronoteFunctionParametersClient(transport: transport)
        var temporaryIV = Data(count: 16)
        let randomStatus = temporaryIV.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw PronoteLiveError.randomGenerationFailed
        }

        let initial = try await functionClient.start(
            session: sessionParameters,
            serverURL: credentials.serverURL,
            clientIdentifier: options.clientIdentifier,
            temporaryIV: temporaryIV
        )
        let authenticator = PronoteAuthenticator(transport: transport)
        let authentication = try await authenticator.authenticate(
            credentials: credentials,
            session: sessionParameters,
            initial: initial,
            options: options
        )
        let client = PronoteSessionClient(transport: transport, session: authentication)
        sessionClient = client
        return client
    }

    private func loadUserParameters(_ client: PronoteSessionClient) async throws -> Any {
        let response = try await client.userParameters()
        resource = PronoteMapper.resource(from: response) ?? resource
        periods = PronoteMapper.periods(from: response)
        if schoolYearStart == nil { schoolYearStart = PronoteMapper.schoolYearStart(from: response) }
        return response
    }

    private func loadResource(_ client: PronoteSessionClient) async throws -> [String: Any] {
        if let resource { return resource }
        _ = try await loadUserParameters(client)
        guard let resource else {
            throw PronoteLiveError.missingResource
        }
        return resource
    }

    private func deduplicate(_ entries: [TimetableEntry]) -> [TimetableEntry] {
        var map: [UUID: TimetableEntry] = [:]
        entries.forEach { map[$0.id] = $0 }
        return map.values.sorted { $0.start < $1.start }
    }

    private func deduplicate(_ grades: [Grade]) -> [Grade] {
        var map: [UUID: Grade] = [:]
        grades.forEach { map[$0.id] = $0 }
        return map.values.sorted { $0.date > $1.date }
    }
}

enum PronoteLiveError: Error, LocalizedError, Equatable {
    case missingResource
    case randomGenerationFailed
    var errorDescription: String? {
        switch self {
        case .missingResource: return "PRONOTE n'a pas fourni la ressource élève nécessaire pour récupérer les données."
        case .randomGenerationFailed: return "Impossible de générer l'IV temporaire PRONOTE."
        }
    }
}
