import Foundation

enum AlarmError: LocalizedError {
    case notAuthorized
    case dateInPast
    case schedulingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "L'autorisation AlarmKit n'a pas été accordée."
        case .dateInPast:
            return "L'heure du réveil est déjà passée."
        case .schedulingFailed(let error):
            return "Impossible de programmer l'alarme : \(error.localizedDescription)"
        }
    }
}
