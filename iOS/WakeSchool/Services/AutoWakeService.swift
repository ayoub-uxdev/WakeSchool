import Foundation

/// Plan de réveil automatique calculé à partir de l'emploi du temps RÉEL
/// normalisé par WakeSchool (aucune invention PRONOTE).
struct AutoWakePlan: Equatable {
    /// Jour visé (premier jour avec un cours actif).
    let targetDay: Date
    /// Premier cours actif (non annulé) de ce jour.
    let firstCourse: TimetableEntry
    /// Recommandation calculée par `WakeTimeCalculator` (réutilisée, pas de logique parallèle).
    let recommendation: WakeTimeRecommendation
    /// True si l'heure de réveil provient du choix personnalisé de l'utilisateur.
    let isCustom: Bool
}

/// Moteur AutoWake : détermine le prochain réveil à proposer.
///
/// Logique pure : aucune dépendance à AlarmKit, à UNUserNotificationCenter
/// ni à l'état de l'application — testable sans iPhone.
///
/// Règles :
/// - le « prochain jour de cours » est le premier jour (aujourd'hui inclus)
///   dont le premier cours NON ANNULÉ est encore à venir (`DashboardService.nextWake`,
///   réutilisé) ; week-ends et journées sans cours sont donc naturellement ignorés ;
/// - un cours modifié ou remplacé reste un cours actif : seul `isCancelled`
///   est déterminant (aucun rapprochement inventé entre deux cours) ;
/// - l'heure personnalisée, si activée, remplace l'heure recommandée sans
///   changer le jour ni le premier cours de référence.
enum AutoWakeService {

    /// Heure de réveil personnalisée, exprimée en minutes depuis minuit (0…1439).
    static func customWakeDate(minutesFromMidnight: Int,
                               on day: Date,
                               calendar: Calendar) -> Date? {
        guard minutesFromMidnight >= 0, minutesFromMidnight <= 1_439 else { return nil }
        let midnight = calendar.startOfDay(for: day)
        return midnight.addingTimeInterval(TimeInterval(minutesFromMidnight) * 60)
    }

    /// Plan de réveil pour le prochain jour de cours, ou nil si aucun cours
    /// à venir dans la fenêtre explorée (`DashboardService.wakeSearchDays`).
    static func plan(entries: [TimetableEntry],
                     now: Date,
                     settings: WakeSettings,
                     customWakeMinutesFromMidnight: Int? = nil,
                     calendar: Calendar = .current) -> AutoWakePlan? {
        let today = calendar.startOfDay(for: now)
        for offset in 0..<DashboardService.wakeSearchDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let start = WakeTimeCalculator.firstCourseStart(in: entries, on: day, calendar: calendar),
                  start > now,
                  let course = entries.first(where: {
                      !$0.isCancelled && $0.start == start &&
                      calendar.isDate($0.start, inSameDayAs: day)
                  }),
                  let recommendation = try? WakeTimeCalculator.recommend(
                        for: day,
                        entries: entries,
                        travelTime: settings.travelTime,
                        preparationTime: settings.preparationTime,
                        safetyMargin: settings.safetyMargin,
                        calendar: calendar) else {
                continue
            }

            // Heure personnalisée : même jour, même cours de référence, heure remplacée.
            if let customMinutes = customWakeMinutesFromMidnight,
               let customDate = customWakeDate(minutesFromMidnight: customMinutes,
                                               on: recommendation.wakeTime,
                                               calendar: calendar) {
                let custom = WakeTimeRecommendation(wakeTime: customDate,
                                                    departureTime: recommendation.departureTime,
                                                    firstClassStart: recommendation.firstClassStart)
                return AutoWakePlan(targetDay: day,
                                    firstCourse: course,
                                    recommendation: custom,
                                    isCustom: true)
            }

            return AutoWakePlan(targetDay: day,
                                firstCourse: course,
                                recommendation: recommendation,
                                isCustom: false)
        }
        return nil
    }

    /// Anti-doublon : une alarme déjà programmée à la même minute (±60 s) ne
    /// doit jamais être reprogrammée, même si l'emploi du temps n'a pas changé.
    static func shouldReschedule(existingFireDate: Date?, desiredFireDate: Date?) -> Bool {
        switch (existingFireDate, desiredFireDate) {
        case (nil, nil):
            return false
        case (nil, _), (_, nil):
            return true
        case (let existing?, let desired?):
            return abs(existing.timeIntervalSince(desired)) > 60
        }
    }
}
