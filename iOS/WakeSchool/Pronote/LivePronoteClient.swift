import Foundation
import Security

final class LivePronoteClient: PronoteClient, PronoteDataDiagnosticsReporting {

    private let credentials: PronoteCredentials
    private let options: PronoteLoginOptions
    private let transport: PronoteHTTPTransporting
    private let onCredentialsUpdated: ((PronoteCredentials) throws -> Void)?

    private var sessionClient: PronoteSessionClient?
    private var resource: [String: Any]?
    private var hasLoadedUserParameters = false
    private var periods: [[String: Any]] = []
    /// Lundi de référence de l'année scolaire PRONOTE, chargé après la première connexion.
    /// Accessible pour convertir des plages de dates en numéros de semaine PRONOTE.
    var schoolYearStart: Date?
    private var schoolDayEndTimes: [[String: Any]] = []
    private var functionOptionsErrorCode: String?
    private(set) var dataDiagnostics = PronoteSyncDiagnostics()
    private(set) var lastFetchedExams: [Exam] = []

    init(
        credentials: PronoteCredentials,
        options: PronoteLoginOptions = PronoteLoginOptions(),
        transport: PronoteHTTPTransporting = PronoteHTTPTransport(),
        onCredentialsUpdated: ((PronoteCredentials) throws -> Void)? = nil
    ) {
        self.credentials = credentials
        self.options = options
        self.transport = transport
        self.onCredentialsUpdated = onCredentialsUpdated
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
            usesMobileToken: false,
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
        guard let refreshedToken = try await client.refreshedMobileToken(),
              !refreshedToken.isEmpty else {
            throw PronoteQRLoginError.missingMobileToken
        }
        credentials.password = refreshedToken
        credentials.usesMobileToken = true

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

    /// Exchanges the mobile token exposed by PRONOTE after an ENT web login.
    static func loginWithENTMobileToken(
        serverURL: String,
        username: String,
        mobileToken: String,
        accountKind: PronoteAccountKind,
        mobileUUID: String,
        transport: PronoteHTTPTransporting = PronoteHTTPTransport()
    ) async throws -> PronoteQRLoginResult {
        let normalizedUsername = username.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalizedUsername.isEmpty,
              !mobileToken.isEmpty,
              !mobileUUID.isEmpty else {
            throw PronoteLiveError.invalidMobileTokenCredentials
        }

        var credentials = PronoteCredentials(
            serverURL: serverURL,
            username: normalizedUsername,
            password: mobileToken,
            accountKind: accountKind,
            usesMobileToken: false,
            mobileUUID: mobileUUID
        )
        let client = LivePronoteClient(
            credentials: credentials,
            options: PronoteLoginOptions(
                mobileUUID: mobileUUID,
                clientIdentifier: mobileUUID,
                mobileToken: mobileToken
            ),
            transport: transport
        )

        let profile: PronoteProfile
        do {
            profile = try await client.profile()
        } catch let diagnostic as PronoteLoginDiagnosticError {
            throw PronoteLoginDiagnosticError(
                stage: .mobileTokenRecovery,
                operation: diagnostic.operation ?? diagnostic.stage,
                message: diagnostic.message
            )
        } catch {
            throw PronoteLoginDiagnosticError(
                stage: .mobileTokenRecovery,
                operation: nil,
                message: error.localizedDescription
            )
        }
        guard let refreshedToken = try await client.refreshedMobileToken(),
              !refreshedToken.isEmpty else {
            throw PronoteLoginDiagnosticError(
                stage: .mobileTokenRecovery,
                operation: nil,
                message: "PRONOTE n'a pas fourni de jeton mobile de reconnexion après l'authentification."
            )
        }
        credentials.password = refreshedToken
        credentials.usesMobileToken = true

        return PronoteQRLoginResult(
            credentials: credentials,
            displayName: profile.displayName
        )
    }

    // MARK: - Timetable

    /// Récupère l'emploi du temps et les contrôles pour UNE SEULE semaine PRONOTE.
    /// Méthode privée utilisée en interne par `getTimetable(weekNumber:)` et
    /// `fetchTimetableAndExams()`.
    private func fetchTimetableForWeek(
        weekNumber: Int,
        resource: [String: Any]
    ) async throws -> (entries: [TimetableEntry], exams: [Exam]) {
        let client = try await connectedClient()

        let response = try await client.timetable(
            weekNumber: weekNumber,
            resource: resource
        )

        let rawCount = PronoteMapper.rawTimetableCount(from: response)
        let weekEntries = PronoteMapper.timetable(
            from: response,
            schoolDayEndTimes: schoolDayEndTimes
        )
        let weekExams = PronoteMapper.exams(from: response)

        dataDiagnostics.timetable.rawCount = rawCount
        dataDiagnostics.timetable.convertedCount = weekEntries.count

        return (weekEntries, weekExams)
    }

    private func fetchTimetableAndExams() async throws -> ([TimetableEntry], [Exam]) {
        let client = try await connectedClient()

        let resource = try await loadResource(
            client
        )

        let calendar = Calendar.current

        guard let start = schoolYearStart else {
            let error = PronoteLiveError.missingSchoolPeriodAnchor
            let stage = functionOptionsErrorCode == nil
                ? "FonctionParametres.General.PremierLundi"
                : "FonctionParametres.dataSec"
            dataDiagnostics.recordFailure(error, stage: stage)
            if let functionOptionsErrorCode {
                dataDiagnostics.errorCode = functionOptionsErrorCode
            }
            throw error
        }

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
        var rawCount = 0
        var exams: [Exam] = []

        for week in currentWeek...(currentWeek + 2) {
            let (weekEntries, weekExams) = try await fetchTimetableForWeek(
                weekNumber: week,
                resource: resource
            )
            rawCount += PronoteMapper.rawTimetableCount(from: [:]) // rawCount already tracked in fetchTimetableForWeek
            entries.append(contentsOf: weekEntries)
            exams.append(contentsOf: weekExams)
        }

        let result = deduplicate(entries)
        let deduplicatedExams = deduplicateExams(exams)
        dataDiagnostics.timetable.callStatus = .succeeded
        dataDiagnostics.timetable.rawCount = rawCount
        dataDiagnostics.timetable.convertedCount = result.count
        dataDiagnostics.schoolPeriodIdentified = !periods.isEmpty && schoolYearStart != nil
        return (result, deduplicatedExams)
    }

    /// Numéros de semaine PRONOTE qui couvrent la plage de dates donnée.
    /// Nécessite que `schoolYearStart` ait été chargé.
    /// Retourne un tableau vide si l'ancre de l'année scolaire est indisponible.
    func weekNumbersCovering(_ range: ClosedRange<Date>) -> [Int] {
        guard let start = schoolYearStart else { return [] }
        let calendar = Calendar.current

        let firstDay = calendar.startOfDay(for: range.lowerBound)
        let lastDay = calendar.startOfDay(for: range.upperBound)

        let firstWeek = schoolWeek(for: firstDay, anchor: start)
        let lastWeek = schoolWeek(for: lastDay, anchor: start)

        return Array(firstWeek...lastWeek)
    }

    /// Emploi du temps pour la plage de dates donnée, récupéré semaine par semaine
    /// depuis PRONOTE sans télécharger l'année entière.
    /// Établit la connexion si nécessaire (rendant `schoolYearStart` disponible).
    func getTimetable(in range: ClosedRange<Date>) async throws -> [TimetableEntry] {
        dataDiagnostics.timetable = PronoteDatasetDiagnostics(callStatus: .failed)
        do {
            let client = try await connectedClient()
            let resource = try await loadResource(client)

            let weeks = weekNumbersCovering(range)
            guard !weeks.isEmpty else {
                dataDiagnostics.timetable.callStatus = .succeeded
                dataDiagnostics.timetable.convertedCount = 0
                return []
            }

            var allEntries: [TimetableEntry] = []
            for week in weeks {
                let (weekEntries, _) = try await fetchTimetableForWeek(
                    weekNumber: week,
                    resource: resource
                )
                allEntries.append(contentsOf: weekEntries)
            }

            // Déduplication par ID (évite les doublons sur semaines chevauchantes)
            var seen = Set<UUID>()
            let result = allEntries.filter { seen.insert($0.id).inserted }
                .sorted { $0.start < $1.start }

            dataDiagnostics.timetable.callStatus = .succeeded
            dataDiagnostics.timetable.rawCount = allEntries.count
            dataDiagnostics.timetable.convertedCount = result.count
            dataDiagnostics.schoolPeriodIdentified = !periods.isEmpty && schoolYearStart != nil
            return result
        } catch {
            recordDatasetFailure(.timetable, error: error, fallbackStage: "PageEmploiDuTemps(range)")
            throw error
        }
    }

    // MARK: - Timetable

    func getTimetable() async throws -> [TimetableEntry] {
        dataDiagnostics.timetable = PronoteDatasetDiagnostics(callStatus: .failed)
        do {
            return try await fetchTimetableAndExams().0
        } catch {
            recordDatasetFailure(.timetable, error: error, fallbackStage: "PageEmploiDuTemps")
            throw error
        }
    }

    /// Emploi du temps pour une semaine PRONOTE donnée (numéro de semaine dans
    /// l'année scolaire). Permet le chargement progressif sans télécharger
    /// toute l'année d'un coup.
    ///
    /// - Requiert qu'une connexion ait été établie au préalable (pour disposer
    ///   de `schoolYearStart` et de la ressource élève).
    func getTimetable(weekNumber: Int) async throws -> [TimetableEntry] {
        dataDiagnostics.timetable = PronoteDatasetDiagnostics(callStatus: .failed)
        do {
            let client = try await connectedClient()
            let resource = try await loadResource(client)
            let (entries, exams) = try await fetchTimetableForWeek(weekNumber: weekNumber, resource: resource)
            dataDiagnostics.timetable.callStatus = .succeeded
            dataDiagnostics.timetable.rawCount = entries.count
            dataDiagnostics.timetable.convertedCount = entries.count
            dataDiagnostics.schoolPeriodIdentified = !periods.isEmpty && schoolYearStart != nil
            self.lastFetchedExams = exams
            return entries
        } catch {
            recordDatasetFailure(.timetable, error: error, fallbackStage: "PageEmploiDuTemps(week \(weekNumber))")
            throw error
        }
    }

    // MARK: - Emploi du temps + contrôles (DS)

    /// Emploi du temps ET contrôles en UNE SEULE récupération réseau :
    /// les DS sont dérivés des MÊMES réponses PageEmploiDuTemps que les cours
    /// et renvoyés avec elles en résultat direct — AUCUN état partagé mutable
    /// entre synchronisations concurrentes. Les erreurs sont propagées :
    /// aucun cache périmé, aucune erreur masquée.
    func getTimetableAndExams() async throws -> (entries: [TimetableEntry], exams: [Exam]) {
        dataDiagnostics.timetable = PronoteDatasetDiagnostics(callStatus: .failed)
        do {
            let (entries, exams) = try await fetchTimetableAndExams()
            return (entries, exams)
        } catch {
            recordDatasetFailure(.timetable, error: error, fallbackStage: "PageEmploiDuTemps")
            throw error
        }
    }

    private func deduplicateExams(_ exams: [Exam]) -> [Exam] {
        var map: [UUID: Exam] = [:]
        for exam in exams {
            map[exam.id] = exam
        }
        return map.values.sorted { $0.date < $1.date }
    }

    // MARK: - Homework

    func getHomework() async throws -> [Homework] {
        dataDiagnostics.homework = PronoteDatasetDiagnostics(callStatus: .failed)
        do {
            return try await fetchHomework()
        } catch {
            recordDatasetFailure(.homework, error: error, fallbackStage: "PageCahierDeTexte")
            throw error
        }
    }

    private func fetchHomework() async throws -> [Homework] {
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

        guard let schoolYearStart else {
            let error = PronoteLiveError.missingSchoolPeriodAnchor
            let stage = functionOptionsErrorCode == nil
                ? "FonctionParametres.General.PremierLundi"
                : "FonctionParametres.dataSec"
            dataDiagnostics.recordFailure(error, stage: stage)
            if let functionOptionsErrorCode {
                dataDiagnostics.errorCode = functionOptionsErrorCode
            }
            throw error
        }
        let firstWeek = schoolWeek(for: start, anchor: schoolYearStart)
        let lastWeek = schoolWeek(for: end, anchor: schoolYearStart)
        let weekRange: ClosedRange<Int> = firstWeek...lastWeek
        let response = try await client.homework(
            resource: resource,
            weekRange: weekRange
        )

        let result = PronoteMapper.homework(from: response, accountScope: credentials.accountScope)
        dataDiagnostics.homework.callStatus = .succeeded
        dataDiagnostics.homework.rawCount = PronoteMapper.rawHomeworkCount(from: response)
        dataDiagnostics.homework.convertedCount = result.count
        return result
    }

    // MARK: - Grades

    func getGrades() async throws -> [Grade] {
        dataDiagnostics.grades = PronoteDatasetDiagnostics(callStatus: .failed)
        do {
            return try await fetchGrades()
        } catch {
            recordDatasetFailure(.grades, error: error, fallbackStage: "DernieresNotes")
            throw error
        }
    }

    // MARK: - Absences et retards

    /// Absences et retards de l'élève, toutes périodes confondues.
    ///
    /// Synchronisation indépendante : les diagnostics de vie scolaire ne polluent
    /// pas ceux du cache scolaire. En cas d'erreur (contrat serveur, hors ligne…),
    /// l'erreur est propagée et le cache local existant n'est pas touché.
    func getAttendance() async throws -> [AttendanceEvent] {
        let client = try await connectedClient()
        let resource = try await loadResource(client)

        guard !periods.isEmpty else {
            throw PronoteLiveError.missingSchoolPeriods
        }

        var events: [AttendanceEvent] = []
        for period in periods {
            let response = try await client.presence(period: period, resource: resource)
            // Une listeAbsences absente/mal formée lève une erreur : le cache
            // local est conservé (cf. SchoolSyncService.syncAttendance).
            events.append(contentsOf: try PronoteMapper.attendance(from: response))
        }

        var seen = Set<UUID>()
        return events
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.start > $1.start }
    }

    private func fetchGrades() async throws -> [Grade] {
        let client =
            try await connectedClient()

        let resource = try await loadResource(
            client
        )

        guard !periods.isEmpty else {
            let error = PronoteLiveError.missingSchoolPeriods
            dataDiagnostics.schoolPeriodIdentified = false
            let stage = functionOptionsErrorCode == nil
                ? "FonctionParametres.General.ListePeriodes"
                : "FonctionParametres.dataSec"
            dataDiagnostics.recordFailure(error, stage: stage)
            if let functionOptionsErrorCode {
                dataDiagnostics.errorCode = functionOptionsErrorCode
            }
            throw error
        }

        var grades: [Grade] = []
        var rawCount = 0

        for period in periods {

            let response =
                try await client.grades(
                    period: period,
                    resource: resource
                )

            rawCount += PronoteMapper.rawGradesCount(from: response)
            let mapping = PronoteMapper.gradeMapping(from: response)
            for (reason, count) in mapping.rejectedCounts {
                dataDiagnostics.grades.rejectedCounts[reason, default: 0] += count
            }
            grades.append(contentsOf: mapping.grades)
        }

        let result = deduplicate(grades)
        let duplicatesAcrossPeriods = grades.count - result.count
        if duplicatesAcrossPeriods > 0 {
            dataDiagnostics.grades.rejectedCounts[
                PronoteGradeRejection.duplicate.rawValue,
                default: 0
            ] += duplicatesAcrossPeriods
        }
        dataDiagnostics.grades.callStatus = .succeeded
        dataDiagnostics.grades.rawCount = rawCount
        dataDiagnostics.grades.convertedCount = result.count
        dataDiagnostics.schoolPeriodIdentified = true
        return result
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

    func downloadHomeworkAttachment(_ attachment: HomeworkAttachment) async throws -> Data {
        let client = try await connectedClient()
        return try await client.downloadHomeworkAttachment(attachment)
    }

    // MARK: - Connection

    private func connectedClient()
        async throws -> PronoteSessionClient {

        if let sessionClient {
            return sessionClient
        }

        let sessionParameters: PronoteSessionParameters
        do {
            sessionParameters = try await diagnoseAutomaticReconnection {
                try await transport.bootstrap(
                    serverURL: credentials.serverURL,
                    accountKind: credentials.accountKind
                )
            }
        } catch {
            dataDiagnostics.recordFailure(error, stage: "Bootstrap PRONOTE")
            throw error
        }

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

        let initial: PronoteInitialSession
        do {
            initial = try await diagnoseAutomaticReconnection {
                try await functionClient.start(
                    session: sessionParameters,
                    clientIdentifier: options.clientIdentifier,
                    temporaryIV: temporaryIV
                )
            }
        } catch {
            dataDiagnostics.recordFailure(error, stage: "FonctionParametres")
            throw error
        }

        let authenticator =
            PronoteAuthenticator(
                transport: transport
            )

        let authentication =
            try await diagnoseAuthentication {
                try await authenticator.authenticate(
                    credentials: credentials,
                    session: sessionParameters,
                    initial: initial,
                    options: options
                )
            }
        dataDiagnostics.authenticationSucceeded = true

        if credentials.usesMobileToken,
           let refreshedToken = authentication.mobileToken,
           !refreshedToken.isEmpty,
           refreshedToken != credentials.password {
            var updatedCredentials = credentials
            updatedCredentials.password = refreshedToken
            try onCredentialsUpdated?(updatedCredentials)
        }

        let client =
            PronoteSessionClient(
                transport: transport,
                session: authentication
            )

        schoolYearStart = initial.schoolYearStart
        periods = initial.schoolPeriods
        schoolDayEndTimes = initial.schoolDayEndTimes
        functionOptionsErrorCode = initial.functionOptionsErrorCode
        dataDiagnostics.authenticationSucceeded = true
        dataDiagnostics.schoolPeriodIdentified = !periods.isEmpty && schoolYearStart != nil
        sessionClient = client

        return client
    }

    private func diagnoseAutomaticReconnection<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard options.automaticReconnection else { throw error }
            if error is PronoteLoginDiagnosticError {
                throw error
            }
            throw PronoteLoginDiagnosticError(
                stage: .automaticReconnection,
                operation: nil,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - User Parameters

    private func loadUserParameters(
        _ client: PronoteSessionClient
    ) async throws -> Any {

        let response: Any
        do {
            response = try await client.userParameters()
        } catch {
            dataDiagnostics.userParametersRetrieved = false
            dataDiagnostics.recordFailure(error, stage: "ParametresUtilisateur")
            throw error
        }

        resource = PronoteMapper.studentResource(
            from: response,
            accountKind: credentials.accountKind
        ) ?? resource
        hasLoadedUserParameters = true

        if periods.isEmpty {
            periods = PronoteMapper.periods(from: response)
        }

        dataDiagnostics.userParametersRetrieved = true
        dataDiagnostics.studentResourceIdentified = resource?["N"] != nil
        dataDiagnostics.schoolPeriodIdentified = !periods.isEmpty && schoolYearStart != nil

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

        guard let resource, resource["N"] != nil else {
            dataDiagnostics.studentResourceIdentified = false
            let error = PronoteLiveError.missingResource
            dataDiagnostics.recordFailure(error, stage: "ParametresUtilisateur.ressource")
            throw error
        }

        return resource
    }

    private enum Dataset {
        case timetable
        case homework
        case grades
    }

    private func recordDatasetFailure(
        _ dataset: Dataset,
        error: Error,
        fallbackStage: String
    ) {
        if dataDiagnostics.errorStage == nil {
            dataDiagnostics.recordFailure(error, stage: fallbackStage)
        }
        let stage = dataDiagnostics.errorStage ?? fallbackStage
        let code = dataDiagnostics.errorCode ?? String(describing: type(of: error))
        switch dataset {
        case .timetable:
            dataDiagnostics.timetable.callStatus = .failed
            dataDiagnostics.timetable.errorStage = stage
            dataDiagnostics.timetable.errorCode = code
        case .homework:
            dataDiagnostics.homework.callStatus = .failed
            dataDiagnostics.homework.errorStage = stage
            dataDiagnostics.homework.errorCode = code
        case .grades:
            dataDiagnostics.grades.callStatus = .failed
            dataDiagnostics.grades.errorStage = stage
            dataDiagnostics.grades.errorCode = code
        }
    }

    private func diagnoseAuthentication<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            let stage: String
            if let diagnostic = error as? PronoteLoginDiagnosticError {
                stage = diagnostic.operation?.label ?? diagnostic.stage.label
            } else {
                stage = "Authentification PRONOTE"
            }
            dataDiagnostics.authenticationSucceeded = false
            dataDiagnostics.recordFailure(error, stage: stage)
            throw error
        }
    }

    private func schoolWeek(for date: Date, anchor: Date) -> Int {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: anchor)
        let targetDay = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: firstDay, to: targetDay).day ?? 0
        return max(1, 1 + days / 7)
    }

    func resetDataDiagnostics() {
        var fresh = PronoteSyncDiagnostics()
        fresh.authenticationSucceeded = sessionClient != nil
        fresh.userParametersRetrieved = hasLoadedUserParameters
        fresh.studentResourceIdentified = resource?["N"] != nil
        fresh.schoolPeriodIdentified = !periods.isEmpty && schoolYearStart != nil
        dataDiagnostics = fresh
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
    case missingSchoolPeriodAnchor
    case missingSchoolPeriods
    case randomGenerationFailed
    case invalidMobileTokenCredentials

    var errorDescription: String? {

        switch self {

        case .missingResource:
            return "PRONOTE n'a pas fourni la ressource élève nécessaire pour récupérer les données."

        case .missingSchoolPeriodAnchor:
            return "Les paramètres PRONOTE ne contiennent pas le lundi de référence de l'année scolaire."

        case .missingSchoolPeriods:
            return "Les paramètres PRONOTE ne contiennent aucune période scolaire."

        case .randomGenerationFailed:
            return "Impossible de générer l'IV temporaire PRONOTE."

        case .invalidMobileTokenCredentials:
            return "La session ENT n'a pas fourni un identifiant et un jeton PRONOTE valides."
        }
    }
}