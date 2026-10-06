import Foundation

enum PronoteError: LocalizedError, Equatable {
    /// L'intégration réelle n'existe pas encore.
    case notImplemented
    /// Aucun identifiant enregistré.
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notImplemented: return "L'intégration Pronote n'est pas encore disponible."
        case .notConfigured: return "Aucun compte Pronote n'est configuré."
        }
    }
}

/// Implémentation de remplacement : échoue explicitement tant que le vrai client n'existe pas.
struct UnavailablePronoteClient: PronoteClient {
    func getTimetable() async throws -> [TimetableEntry] { throw PronoteError.notImplemented }
    func getHomework() async throws -> [Homework] { throw PronoteError.notImplemented }
    func getGrades() async throws -> [Grade] { throw PronoteError.notImplemented }
}
