import Foundation

enum PronoteDiagnosticCallStatus: String {
    case notRun = "non exécuté"
    case succeeded = "succès"
    case failed = "échec"
}

struct PronoteDatasetDiagnostics {
    var callStatus: PronoteDiagnosticCallStatus = .notRun
    var rawCount = 0
    var convertedCount = 0
    var savedCount = 0
    var displayedCount = 0
    var rejectedCounts: [String: Int] = [:]
    var errorStage: String?
    var errorCode: String?
}

struct PronoteSyncDiagnostics {
    var authenticationSucceeded = false
    var userParametersRetrieved = false
    var studentResourceIdentified = false
    var schoolPeriodIdentified = false
    var timetable = PronoteDatasetDiagnostics()
    var homework = PronoteDatasetDiagnostics()
    var grades = PronoteDatasetDiagnostics()
    var errorStage: String?
    var errorCode: String?

    mutating func recordFailure(_ error: Error, stage: String) {
        errorStage = stage
        errorCode = Self.code(for: error)
    }

    mutating func recordPersistedSnapshot(_ snapshot: SchoolSnapshot) {
        timetable.savedCount = snapshot.timetable.count
        timetable.displayedCount = snapshot.timetable.count
        homework.savedCount = snapshot.homework.count
        homework.displayedCount = snapshot.homework.count
        grades.savedCount = snapshot.grades.count
        grades.displayedCount = snapshot.grades.count
    }

    private static func code(for error: Error) -> String {
        switch error {
        case let error as PronoteSessionError:
            switch error {
            case .invalidResponse:
                return "INVALID_RESPONSE"
            case .missingStudentResource:
                return "STUDENT_RESOURCE_MISSING"
            case .invalidPeriod:
                return "INVALID_SCHOOL_PERIOD"
            case .unexpectedResponseNumber(_):
                return "UNEXPECTED_ORDER_NUMBER"
            case .pronoteError(let code, _):
                return "PRONOTE_\(code)"
            }
        case let error as PronoteTransportError:
            switch error {
            case .httpStatus(let code):
                return "HTTP_\(code)"
            case .pronoteError(let code, _):
                return "PRONOTE_\(code)"
            case .invalidServerURL:
                return "INVALID_SERVER_URL"
            case .invalidHTTPResponse:
                return "INVALID_HTTP_RESPONSE"
            case .emptyResponse:
                return "EMPTY_RESPONSE"
            case .sessionParametersNotFound:
                return "SESSION_PARAMETERS_NOT_FOUND"
            case .missingPageVersion:
                return "MISSING_PAGE_VERSION"
            case .invalidSessionParameter(_):
                return "INVALID_SESSION_PARAMETER"
            case .attachmentUnavailable:
                return "ATTACHMENT_UNAVAILABLE"
            case .attachmentDownloadUnsupported:
                return "ATTACHMENT_DOWNLOAD_UNSUPPORTED"
            }
        case let error as PronoteLiveError:
            switch error {
            case .missingResource:
                return "STUDENT_RESOURCE_MISSING"
            case .missingSchoolPeriodAnchor:
                return "SCHOOL_PERIOD_ANCHOR_MISSING"
            case .missingSchoolPeriods:
                return "SCHOOL_PERIODS_MISSING"
            case .randomGenerationFailed:
                return "RANDOM_GENERATION_FAILED"
            case .invalidMobileTokenCredentials:
                return "INVALID_CREDENTIAL_STATE"
            }
        case let error as PronoteLoginDiagnosticError:
            if let code = numericCode(in: error.message, after: "code ") {
                return "PRONOTE_\(code)"
            }
            if let code = numericCode(in: error.message, after: "HTTP ") {
                return "HTTP_\(code)"
            }
            return "LOGIN_DIAGNOSTIC"
        default:
            return String(describing: type(of: error))
        }
    }

    private static func numericCode(in message: String, after marker: String) -> Int? {
        guard let markerRange = message.range(of: marker) else {
            return nil
        }
        let digits = message[markerRange.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}

protocol PronoteDataDiagnosticsReporting {
    var dataDiagnostics: PronoteSyncDiagnostics { get }
    func resetDataDiagnostics()
}

protocol SchoolSyncDiagnosticsReporting: PronoteDataDiagnosticsReporting {
}

struct PronoteSchoolDataProvider: SchoolDataProvider, SchoolSyncDiagnosticsReporting, HomeworkAttachmentDownloading {
    let client: PronoteClient

    var dataDiagnostics: PronoteSyncDiagnostics {
        (client as? PronoteDataDiagnosticsReporting)?.dataDiagnostics
            ?? PronoteSyncDiagnostics()
    }

    func resetDataDiagnostics() {
        (client as? PronoteDataDiagnosticsReporting)?.resetDataDiagnostics()
    }

    func timetable() async throws -> [TimetableEntry] {
        try await client.getTimetable()
    }

    /// Synchronisation en UNE SEULE récupération emploi du temps :
    /// `client.getTimetableAndExams()` dérive les DS des MÊMES réponses réseau
    /// que les cours (pas de 2ᵉ boucle PageEmploiDuTemps). Les notes sont aussi
    /// récupérées UNE SEULE fois : les moyennes sont calculées localement à partir
    /// de ce même tableau (il n'existe pas de moyennes officielles PRONOTE dans
    /// cette intégration). Les erreurs restent propagées telles quelles.
    func snapshot() async throws -> SchoolSnapshot {
        let timetableAndExams = try await client.getTimetableAndExams()
        let grades = try await client.getGrades()
        return SchoolSnapshot(
            timetable: timetableAndExams.entries,
            homework: try await homework(),
            grades: grades,
            averages: AverageCalculator.subjectAverages(from: grades),
            exams: timetableAndExams.exams,
            events: try await events()
        )
    }

    func homework() async throws -> [Homework] {
        try await client.getHomework()
    }

    func grades() async throws -> [Grade] {
        try await client.getGrades()
    }

    func exams() async throws -> [Exam] {
        // DS dérivés de l'emploi du temps. Appelé SEUL, ce chemin déclenche la
        // récupération complète emploi du temps + DS (la source des DS est la
        // réponse PageEmploiDuTemps). La synchronisation normale utilise
        // `snapshot()`, qui récupère le tout en une seule passe.
        try await client.getTimetableAndExams().exams
    }

    func events() async throws -> [SchoolEvent] {
        []
    }

    func attendance() async throws -> [AttendanceEvent] {
        try await client.getAttendance()
    }

    func downloadHomeworkAttachment(_ attachment: HomeworkAttachment) async throws -> Data {
        guard let client = client as? LivePronoteClient else {
            throw PronoteTransportError.attachmentDownloadUnsupported
        }
        return try await client.downloadHomeworkAttachment(attachment)
    }
}