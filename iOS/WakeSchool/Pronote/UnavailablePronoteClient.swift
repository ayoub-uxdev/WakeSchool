import Foundation

enum PronoteError: LocalizedError, Equatable {
    case notImplemented
    case notConfigured
    var errorDescription: String? {
        switch self {
        case .notImplemented: return "L'intégration Pronote n'est pas encore disponible."
        case .notConfigured: return "Aucun compte Pronote n'est configuré."
        }
    }
}

struct UnavailablePronoteClient: PronoteClient {
    func getTimetable() async throws -> [TimetableEntry] { throw PronoteError.notImplemented }
    func getHomework() async throws -> [Homework] { throw PronoteError.notImplemented }
    func getGrades() async throws -> [Grade] { throw PronoteError.notImplemented }
}
