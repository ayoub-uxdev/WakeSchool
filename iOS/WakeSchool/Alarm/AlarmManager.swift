import AlarmKit
import SwiftUI

/// Métadonnées associées aux alarmes WakeSchool (vides pour l'instant).
struct WakeAlarmMetadata: AlarmMetadata {}

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
