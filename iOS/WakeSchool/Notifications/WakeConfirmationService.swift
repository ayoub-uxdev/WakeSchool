import Foundation

/// Paramètres de la confirmation quotidienne du réveil.
struct WakeConfirmationSettings: Codable, Equatable {
    /// Confirmation activée.
    var isEnabled: Bool
    /// Heure d'envoi (minutes depuis minuit). 21 h par défaut.
    var confirmationTimeMinutes: Int

    static let `default` = WakeConfirmationSettings(isEnabled: true,
                                                    confirmationTimeMinutes: 21 * 60)
}

/// Logique de la confirmation quotidienne du réveil.
///
/// Pure : aucune dépendance à UserNotifications ni à PRONOTE — le message est
/// construit à partir des informations DÉJÀ connues de WakeSchool au moment de
/// la planification. iOS ne garantit pas une exécution en arrière-plan exacte :
/// la notification est donc planifiée À L'AVANCE avec le contenu calculé
/// (emploi du temps connu), et re-planifiée à chaque synchronisation utile.
enum WakeConfirmationService {

    static let confirmationHourDefault = 21

    /// Prochaine date d'envoi de la confirmation : aujourd'hui à `minutes` si
    /// futur, sinon demain à la même heure. Fuseau local.
    static func nextSendDate(minutesFromMidnight: Int,
                             now: Date,
                             calendar: Calendar) -> Date? {
        guard minutesFromMidnight >= 0, minutesFromMidnight <= 1_439 else { return nil }
        let today = calendar.startOfDay(for: now)
        let todayAt = today.addingTimeInterval(TimeInterval(minutesFromMidnight) * 60)
        if todayAt > now { return todayAt }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return tomorrow.addingTimeInterval(TimeInterval(minutesFromMidnight) * 60)
    }

    /// True si la confirmation doit être envoyée pour ce plan :
    /// - confirmation activée ;
    /// - un cours est prévu (plan non nil) : pas de notification inutile ;
    /// - l'emploi du temps a été synchronisé récemment (sinon le message
    ///   risque d'être faux — on n'envoie pas d'info périmée).
    static func shouldSend(plan: AutoWakePlan?,
                           settings: WakeConfirmationSettings,
                           lastSync: Date?,
                           now: Date,
                           maxDataAge: TimeInterval = 24 * 3600) -> Bool {
        guard settings.isEnabled else { return false }
        guard plan != nil else { return false }
        guard let lastSync, now.timeIntervalSince(lastSync) <= maxDataAge else { return false }
        return true
    }

    /// Contenu de la notification de confirmation.
    /// Exemple : « Demain, ton premier cours est à 8 h 00. Réveil proposé : 6 h 45. »
    static func message(plan: AutoWakePlan,
                        now: Date,
                        calendar: Calendar = .current) -> (title: String, body: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH'h'mm"

        let dayWord: String
        let planDay = calendar.startOfDay(for: plan.targetDay)
        let today = calendar.startOfDay(for: now)
        if planDay == today {
            dayWord = "Aujourd'hui"
        } else if planDay == (calendar.date(byAdding: .day, value: 1, to: today) ?? today) {
            dayWord = "Demain"
        } else {
            let weekday = DateLabels.weekdayShort(plan.targetDay)
            dayWord = weekday
        }

        let body = "\(dayWord), ton premier cours est à \(formatter.string(from: plan.recommendation.firstClassStart)). "
            + "Réveil proposé : \(formatter.string(from: plan.recommendation.wakeTime))."
        return (title: "Réveil intelligent", body: body)
    }

    /// Construit la notification à planifier pour un plan donné (identifiant
    /// STABLE par jour visé : re-planifier remplace au lieu de dupliquer).
    static func notification(plan: AutoWakePlan,
                             now: Date,
                             calendar: Calendar = .current) -> WakeNotification? {
        let content = message(plan: plan, now: now, calendar: calendar)
        return .wakeConfirmation(targetDay: plan.targetDay,
                                 calendar: calendar,
                                 title: content.title,
                                 body: content.body)
    }
}
