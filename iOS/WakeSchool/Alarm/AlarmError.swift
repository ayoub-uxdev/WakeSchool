import Foundation

enum AlarmError: LocalizedError {
    case notAuthorized
    case dateInPast
    case schedulingFailed(Error)
    case cancelFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "WakeSchool n'a pas l'autorisation de programmer des alarmes. Tu peux l'activer dans les Réglages."
        case .dateInPast:
            return "L'heure du réveil est déjà passée : impossible de programmer cette alarme."
        case .schedulingFailed(let error):
            return "Impossible de programmer l'alarme : \(error.localizedDescription)"
        case .cancelFailed(let error):
            return "Impossible d'annuler l'alarme : \(error.localizedDescription)"
        }
    }
}
