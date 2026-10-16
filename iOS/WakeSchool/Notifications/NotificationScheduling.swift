import Foundation
import UserNotifications

/// Contenu d'une notification locale WakeSchool, indépendant de UIKit.
/// Les identifiants sont STABLES par nature de contenu : replanifier la même
/// notification remplace l'ancienne au lieu de créer un doublon.
struct WakeNotification: Equatable {
    enum Kind: String {
        /// Confirmation quotidienne du réveil (identifiant stable par jour visé).
        case wakeConfirmation
        /// Notification de test (identifiant fixe : une seule à la fois).
        case test
        /// Notification issue d'une règle personnalisée.
        case rule

        var prefix: String {
            switch self {
            case .wakeConfirmation: return "wake.confirm"
            case .test: return "wake.test"
            case .rule: return "rule"
            }
        }
    }

    let id: String
    let title: String
    let body: String
    /// Identifiant du thread pour regrouper dans le Centre de notifications iOS.
    let threadID: String
    /// Secondes après `Date()` (pour une planification relative immédiate).
    let triggerDelay: TimeInterval

    /// Identifiants STABLES : une confirmation par jour visé (YYYY-MM-DD).
    static func wakeConfirmation(targetDay: Date, calendar: Calendar, title: String, body: String) -> WakeNotification {
        let dayKey = Self.dayKey(targetDay, calendar: calendar)
        return WakeNotification(
            id: "\(Kind.wakeConfirmation.prefix).\(dayKey)",
            title: title,
            body: body,
            threadID: "wake",
            triggerDelay: 0 // défini par le planificateur (21 h par défaut)
        )
    }

    static func test(title: String, body: String) -> WakeNotification {
        WakeNotification(id: Kind.test.prefix, title: title, body: body, threadID: "wake", triggerDelay: 1)
    }

    static func rule(_ kind: String, subjectKey: String, title: String, body: String) -> WakeNotification {
        WakeNotification(id: "\(Kind.rule.prefix).\(kind).\(subjectKey)", title: title, body: body, threadID: "rules", triggerDelay: 0)
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Abstraction de planification testable (aucune dépendance UIKit).
protocol NotificationScheduling: AnyObject {
    /// État de l'autorisation, SANS la demander.
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Demande l'autorisation (contextuelle : appelée uniquement après explication).
    func requestAuthorization() async -> Bool
    /// Planifie une notification locale à `fireDate` (ou après `triggerDelay` si fourni).
    func schedule(_ notification: WakeNotification, at fireDate: Date?) async throws
    /// Annule les notifications dont l'identifiant est fourni.
    func cancel(ids: [String])
    /// Identifiants des notifications actuellement planifiées.
    func pendingIDs() async -> [String]
    /// Supprime toutes les notifications livrées (centre de notifications iOS).
    func clearDelivered() async
}

/// Implémentation réelle via UNUserNotificationCenter.
final class SystemNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter
    /// Sans ce délégué, iOS SUPPRIME silencieusement toute notification livrée
    /// pendant que l'app est au premier plan (cas du bouton de test) : la
    /// notification partait dans le centre sans jamais être visible.
    private let foregroundPresenter: ForegroundNotificationPresenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        self.foregroundPresenter = ForegroundNotificationPresenter()
        center.delegate = foregroundPresenter
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(_ notification: WakeNotification, at fireDate: Date?) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.threadID

        // Calage sur le fuseau local : UNCalendarNotificationTrigger recalcule
        // la date en heure locale, donc un changement de fuseau conserve l'heure.
        let trigger: UNNotificationTrigger
        if let fireDate {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            let delay = max(0.1, notification.triggerDelay)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        }

        let request = UNNotificationRequest(identifier: notification.id,
                                            content: content,
                                            trigger: trigger)
        try await center.add(request)
    }

    func cancel(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func pendingIDs() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    func clearDelivered() async {
        center.removeAllDeliveredNotifications()
    }
}

/// Délégué du centre de notifications : présente les alertes même quand
/// l'application est au premier plan (sinon iOS les supprime silencieusement,
/// ce qui rendait le bouton de notification de test inopérant).
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
