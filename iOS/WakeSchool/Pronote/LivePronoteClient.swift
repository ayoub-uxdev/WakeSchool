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

    init(
        credentials: PronoteCredentials,
        options: PronoteLoginOptions = PronoteLoginOptions(),
        transport: PronoteHTTPTransporting = PronoteHTTPTransport()
    ) {
        self.credentials = credentials
        self.options = options
        self.transport = transport
    }

    // MARK: - QR Login

    /// Décode le QR PRONOTE, récupère les identifiants mobiles
    /// et vérifie immédiatement que la connexion PRONOTE fonctionne.
    static func loginWithQRCode(
        qrText: String,
        pin: String
    ) async throws -> PronoteQRLoginResult {

        let qr = try PronoteQRLogin.decodeQRCode(
            qrText,
            pin: pin
        )

        let decoded = try PronoteQRLogin.decryptCredentials(
            from: qr,
            pin: pin
        )

        let mobileUUID = try PronoteMobileIdentity.sharedUUID()

        var credentials = PronoteCredentials(
            serverURL: decoded.serverURL,
            username: decoded.username,
            password: decoded.password,
            accountKind: decoded.accountKind,
            usesMobileToken: true,
            mobileUUID: mobileUUID
        )

        let options = PronoteLoginOptions(
            useENT: false,
            mobileUUID: mobileUUID,
            clientIdentifier: mobileUUID,
            mobileToken: nil,
            requestFirstMobileAuthentication: true,
            qrLogin: true
        )

        let client = LivePronoteClient(
            credentials: credentials,
            options: options
        )

        let profile = try await client.profile()
        if let refreshedToken = try await client.refreshedMobileToken(),
           !refreshedToken.isEmpty {
            credentials.password = refreshedToken
        }

        return PronoteQRLoginResult(
            credentials: credentials,
            displayName: profile.displayName
        )
    }

    /// Logs in with a school's direct PRONOTE credentials (not an ENT SSO login).
    static func loginWithCredentials(
        serverURL: String,
        username: String,
        password: String,
        accountKind: PronoteAccountKind
    ) async throws -> PronoteQRLoginResult {
        let normalizedUsername = username.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalizedUsername.isEmpty,
              !password.isEmpty else {
            throw PronoteQRLoginError.invalidCredentials
        }

        let mobileUUID = try PronoteMobileIdentity.sharedUUID()
        var credentials = PronoteCredentials(
            serverURL: serverURL,
            username: normalizedUsername,
            password: password,
            accountKind: accountKind,
            mobileUUID: mobileUUID
        )
        let client = LivePronoteClient(
            credentials: credentials,
            options: PronoteLoginOptions(
                mobileUUID: mobileUUID,
                clientIdentifier: mobileUUID,
                requestFirstMobileAuthentication: true
            )
        )

        let profile = try await client.profile()
        if let refreshedToken = try await client.refreshedMobileToken(),
           !refreshedToken.isEmpty {
            credentials.password = refreshedToken
            credentials.usesMobileToken = true
        }

        return PronoteQRLoginResult(
            credentials: credentials,
            displayName: profile.displayName
        )
    }

    // MARK: - Timetable

    func getTimetable() async throws -> [TimetableEntry] {

        let client = try await connectedClient()

        let resource = try await loadResource(
            client
        )

        let calendar = Calendar.current

        let currentYear =
            calendar.component(
                .year,
                from: Date()
            )

        let start =
            schoolYearStart
            ?? calendar.date(
                from: DateComponents(
                    year: currentYear,
                    month: 9,
                    day: 1
                )
            )!

        let today =
            calendar.startOfDay(
                for: Date()
            )

        let daysSinceStart =
            calendar.dateComponents(
                [.day],
                from: start,
                to: today
            ).day ?? 0

        let currentWeek =
            max(
                1,
                1 + max(0, daysSinceStart) / 7
            )

        var entries: [TimetableEntry] = []

        for week in currentWeek...(currentWeek + 2) {

            let response =
                try await client.timetable(
                    weekNumber: week,
                    resource: resource
                )

            entries.append(
                contentsOf:
                    PronoteMapper.timetable(
                        from: response
                    )
            )
        }

        return deduplicate(entries)
    }

    // MARK: - Homework

    func getHomework() async throws -> [Homework] {

        let client =
            try await connectedClient()

        let resource =
            try await loadResource(
                client
            )

        let calendar = Calendar.current

        let start =
            calendar.startOfDay(
                for: Date()
            )

        let end =
            calendar.date(
                byAdding: .day,
                value: 45,
                to: start
            ) ?? start

        let response =
            try await client.homework(
                from: start,
                to: end,
                resource: resource
            )

        return PronoteMapper.homework(
            from: response
        )
    }

    // MARK: - Grades

    func getGrades() async throws -> [Grade] {

        let client =
            try await connectedClient()

        _ = try await loadResource(
            client
        )

        guard !periods.isEmpty else {
            return []
        }

        var grades: [Grade] = []

        for period in periods {

            let response =
                try await client.grades(
                    period: period
                )

            grades.append(
                contentsOf:
                    PronoteMapper.grades(
                        from: response
                    )
            )
        }

        return deduplicate(grades)
    }

    // MARK: - Profile

    func profile() async throws -> PronoteProfile {

        let client =
            try await connectedClient()

        let parameters =
            try await loadUserParameters(
                client
            )

        return PronoteMapper.profile(
            from: parameters
        )
    }

    // MARK: - Mobile Token

    func refreshedMobileToken() async throws -> String? {

        let client =
            try await connectedClient()

        return client.mobileToken
    }

    // MARK: - Connection

    private func connectedClient()
        async throws -> PronoteSessionClient {

        if let sessionClient {
            return sessionClient
        }

        let sessionParameters =
            try await transport.bootstrap(
                serverURL: credentials.serverURL,
                accountKind: credentials.accountKind
            )

        let functionClient =
            PronoteFunctionParametersClient(
                transport: transport
            )

        var temporaryIV =
            Data(
                count: 16
            )

        let randomStatus =
            temporaryIV.withUnsafeMutableBytes { buffer in

                SecRandomCopyBytes(
                    kSecRandomDefault,
                    buffer.count,
                    buffer.baseAddress!
                )
            }

        guard randomStatus == errSecSuccess else {
            throw PronoteLiveError.randomGenerationFailed
        }

        let initial =
            try await functionClient.start(
                session: sessionParameters,
                clientIdentifier: options.clientIdentifier,
                temporaryIV: temporaryIV
            )

        let authenticator =
            PronoteAuthenticator(
                transport: transport
            )

        let authentication =
            try await authenticator.authenticate(
                credentials: credentials,
                session: sessionParameters,
                initial: initial,
                options: options
            )

        let client =
            PronoteSessionClient(
                transport: transport,
                session: authentication
            )

        sessionClient = client

        return client
    }

    // MARK: - User Parameters

    private func loadUserParameters(
        _ client: PronoteSessionClient
    ) async throws -> Any {

        let response =
            try await client.userParameters()

        resource =
            PronoteMapper.resource(
                from: response
            ) ?? resource

        periods =
            PronoteMapper.periods(
                from: response
            )

        if schoolYearStart == nil {

            schoolYearStart =
                PronoteMapper.schoolYearStart(
                    from: response
                )
        }

        return response
    }

    // MARK: - Resource

    private func loadResource(
        _ client: PronoteSessionClient
    ) async throws -> [String: Any] {

        if let resource {
            return resource
        }

        _ = try await loadUserParameters(
            client
        )

        guard let resource else {
            throw PronoteLiveError.missingResource
        }

        return resource
    }

    // MARK: - Deduplication

    private func deduplicate(
        _ entries: [TimetableEntry]
    ) -> [TimetableEntry] {

        var map: [UUID: TimetableEntry] = [:]

        for entry in entries {
            map[entry.id] = entry
        }

        return map.values.sorted {
            $0.start < $1.start
        }
    }

    private func deduplicate(
        _ grades: [Grade]
    ) -> [Grade] {

        var map: [UUID: Grade] = [:]

        for grade in grades {
            map[grade.id] = grade
        }

        return map.values.sorted {
            $0.date > $1.date
        }
    }
}

// MARK: - Errors

enum PronoteLiveError: Error, LocalizedError, Equatable {

    case missingResource
    case randomGenerationFailed

    var errorDescription: String? {

        switch self {

        case .missingResource:
            return "PRONOTE n'a pas fourni la ressource élève nécessaire pour récupérer les données."

        case .randomGenerationFailed:
            return "Impossible de générer l'IV temporaire PRONOTE."
        }
    }
}