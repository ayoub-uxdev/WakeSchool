import AlarmKit
import SwiftUI

/// Métadonnées associées aux alarmes WakeSchool (vides pour l'instant).
struct WakeAlarmMetadata: AlarmMetadata {}

/// État de l'autorisation AlarmKit, exposé pour l'affichage dans les Réglages.
/// Volontairement découplé du type AlarmKit pour rester affichable et testable.
enum WakeAlarmAuthorizationStatus: Equatable {
    case authorized
    case denied
    case notDetermined
    case unknown

    var label: String {
        switch self {
        case .authorized: return "Autorisé"
        case .denied: return "Refusé"
        case .notDetermined: return "Non demandé"
        case .unknown: return "Inconnu"
        }
    }

    var systemImage: String {
        switch self {
        case .authorized: return "checkmark.seal.fill"
        case .denied: return "xmark.octagon.fill"
        case .notDetermined: return "questionmark.circle"
        case .unknown: return "minus.circle"
        }
    }

    var tint: Color {
        switch self {
        case .authorized: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        case .unknown: return .gray
        }
    }
}

/// Seul point d'entrée AlarmKit de l'application.
/// Une alarme n'est jamais considérée comme créée si `schedule` lève une erreur.
@MainActor
final class AlarmManager {
    static let shared = AlarmManager()
    private init() {}

    // Qualifié par le module : notre type porte le même nom que celui d'AlarmKit.
    private var system: AlarmKit.AlarmManager { AlarmKit.AlarmManager.shared }

    /// Retourne true si l'autorisation est accordée (la demande est faite si nécessaire).
    func requestAuthorization() async throws -> Bool {
        switch system.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try await system.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }

    /// État actuel de l'autorisation, en LECTURE SEULE.
    /// Ne déclenche jamais la demande d'autorisation (contrairement à `requestAuthorization`).
    /// Utilisé uniquement pour informer l'utilisateur dans les Réglages.
    func authorizationStatus() -> WakeAlarmAuthorizationStatus {
        switch system.authorizationState {
        case .authorized: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    /// Programme une alarme système à `date`. Lève une `AlarmError` en cas d'échec.
    @discardableResult
    func schedule(at date: Date) async throws -> UUID {
        guard date > Date() else { throw AlarmError.dateInPast }
        guard try await requestAuthorization() else { throw AlarmError.notAuthorized }

        let id = UUID()
        let stopButton = AlarmButton(text: "Arrêter",
                                     textColor: .white,
                                     systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: "Réveil WakeSchool",
                                            stopButton: stopButton)
        let attributes = AlarmAttributes<WakeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeAlarmMetadata(),
            tintColor: .indigo
        )
        let configuration = AlarmKit.AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes
        )
        do {
            _ = try await system.schedule(id: id, configuration: configuration)
        } catch {
            throw AlarmError.schedulingFailed(error)
        }
        return id
    }

    func cancel(id: UUID) throws {
        do {
            try system.cancel(id: id)
        } catch {
            throw AlarmError.cancelFailed(error)
        }
    }

    /// Indique si l'alarme `id` est toujours connue du système (programmée ou en cours de sonnerie).
    func isScheduled(id: UUID) throws -> Bool {
        try system.alarms.contains { $0.id == id }
    }
}

extension AlarmManager: AlarmScheduling {}
