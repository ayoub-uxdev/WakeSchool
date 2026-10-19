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

/// Résultat du calcul du prochain réveil AutoWake.
///
/// Permet de distinguer sans ambiguïté :
/// - un réveil confirmé (un cours a été trouvé) ;
/// - des vacances confirmées (aucune cours sur toute la fenêtre, données suffisantes) ;
/// - des données insuffisantes (période inconnue / non encore synchronisée) —
///   dans ce cas, on ne doit JAMAIS conclure à des vacances ni annuler un
///   réveil valide.
enum AutoWakeResult: Equatable {
    /// Un prochain réveil a été confirmé.
    case planned(AutoWakePlan)
    /// Aucune cours à venir sur la fenêtre explorée ; toutes les périodes
    /// couvertes sont connues et complètes → vraies vacances.
    case holidaysConfirmed
    /// Au moins un jour pertinent de la fenêtre n'est couvert par aucune
    /// période scolaire complète → impossible de conclure.
    case insufficientData
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
///   changer le jour ni le premier cours de référence ;
/// - une période scolaire inconnue ne signifie JAMAIS absence de cours : si
///   un jour entre aujourd'hui et le premier cours trouvé n'est couvert par
///   aucune période complète, le résultat est `.insufficientData`.
enum AutoWakeService {

    /// Heure de réveil personnalisée, exprimée en minutes depuis minuit (0…1439).
    static func customWakeDate(minutesFromMidnight: Int,
                               on day: Date,
                               calendar: Calendar) -> Date? {
        guard minutesFromMidnight >= 0, minutesFromMidnight <= 1_439 else { return nil }
        let midnight = calendar.startOfDay(for: day)
        return midnight.addingTimeInterval(TimeInterval(minutesFromMidnight) * 60)
    }

    /// Vérifie que chaque jour de `0` jusqu'à `limitOffset` (inclus), à partir
    /// de `now`, est couvert par au moins une période scolaire marquée
    /// `isTimetableComplete == true`.
    ///
    /// Utilisé pour distinguer « période connue et vide » (vacances réelles)
    /// de « période inconnue / non encore synchronisée » (données insuffisantes).
    static func daysCovered(periods: [SchoolPeriod],
                            from now: Date,
                            upTo limitOffset: Int,
                            calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        for offset in 0...limitOffset {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return false
            }
            let covered = periods.contains { period in
                period.isTimetableComplete &&
                (period.startDate...period.endDate).contains(day)
            }
            if !covered { return false }
        }
        return true
    }

    /// Plan de réveil pour le prochain jour de cours, SANS vérification de la
    /// disponibilité des périodes scolaires.
    ///
    /// Cette surcharge est conservée pour la rétrocompatibilité avec les appelants
    /// qui ne disposent pas encore de périodes (ex. tests existants, mode démo
    /// sans périodes). Elle se comporte exactement comme l'ancienne implémentation :
    /// aucun blocage lié aux périodes inconnues n'est appliqué.
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

    /// Plan de réveil pour le prochain jour de cours, tenant compte de la
    /// disponibilité des périodes scolaires.
    ///
    /// - Si `periods` est `nil` ou vide : les périodes sont indisponibles
    ///   (mode démo, première synchronisation, ou erreur de lecture du dépôt).
    ///   Aucune vérification de disponibilité n'est appliquée : le comportement
    ///   historique est préservé (un réveil est confirmé si un cours existe,
    ///   jamais d'annulation par précaution).
    /// - Si `periods` est non vide : seules les journées jusqu'au premier cours
    ///   trouvé doivent être couvertes (pas tous les 8 jours si le réveil
    ///   concerne J+2).
    /// - Si aucun cours n'est trouvé sur la fenêtre : les 8 journées doivent
    ///   être couvertes pour conclure à des vacances confirmées.
    static func plan(entries: [TimetableEntry],
                     periods: [SchoolPeriod]?,
                     now: Date,
                     settings: WakeSettings,
                     isDemoMode: Bool = false,
                     customWakeMinutesFromMidnight: Int? = nil,
                     calendar: Calendar = .current) -> AutoWakeResult {
        let today = calendar.startOfDay(for: now)

        // En mode démonstration, on préserve le calcul historique à partir des
        // cours démo : jamais de vérification de disponibilité des périodes.
        // En production, périodes indisponibles (nil ou vide) ne doivent jamais
        // conclure à des vacances par précaution.
        let periodsAvailable = periods?.isEmpty == false
        let shouldCheckAvailability = periodsAvailable && !isDemoMode

        // Recherche du premier jour avec un cours actif encore à venir.
        var firstCourseOffset: Int?
        for offset in 0..<DashboardService.wakeSearchDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let start = WakeTimeCalculator.firstCourseStart(in: entries, on: day, calendar: calendar),
                  start > now,
                  let _ = entries.first(where: {
                      !$0.isCancelled && $0.start == start &&
                      calendar.isDate($0.start, inSameDayAs: day)
                  }) else {
                continue
            }
            firstCourseOffset = offset
            break
        }

        if let offset = firstCourseOffset {
            // Un cours futur a été trouvé.
            // Si les périodes sont disponibles, vérifier seulement les jours
            // jusqu'à ce cours (pas tous les 8 jours de la fenêtre).
            if shouldCheckAvailability {
                guard daysCovered(periods: periods!, from: now, upTo: offset,
                                  calendar: calendar) else {
                    return .insufficientData
                }
            }
            // Recalcul du plan complet (même logique qu'avant).
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let start = WakeTimeCalculator.firstCourseStart(in: entries, on: day, calendar: calendar)!
            let course = entries.first(where: {
                !$0.isCancelled && $0.start == start &&
                calendar.isDate($0.start, inSameDayAs: day)
            })!
            if let recommendation = try? WakeTimeCalculator.recommend(
                for: day,
                entries: entries,
                travelTime: settings.travelTime,
                preparationTime: settings.preparationTime,
                safetyMargin: settings.safetyMargin,
                calendar: calendar) {

                // Heure personnalisée : même jour, même cours de référence, heure remplacée.
                if let customMinutes = customWakeMinutesFromMidnight,
                   let customDate = customWakeDate(minutesFromMidnight: customMinutes,
                                                   on: recommendation.wakeTime,
                                                   calendar: calendar) {
                    let custom = WakeTimeRecommendation(wakeTime: customDate,
                                                        departureTime: recommendation.departureTime,
                                                        firstClassStart: recommendation.firstClassStart)
                    return .planned(AutoWakePlan(targetDay: day,
                                                 firstCourse: course,
                                                 recommendation: custom,
                                                 isCustom: true))
                }
                return .planned(AutoWakePlan(targetDay: day,
                                             firstCourse: course,
                                             recommendation: recommendation,
                                             isCustom: false))
            }
            // Le calcul de recommandation a échoué (ne devrait pas arriver si
            // firstCourseStart a réussi) : on traite comme données insuffisantes.
            return .insufficientData
        }

        // Aucun cours trouvé sur la fenêtre : conclure à des vacances seulement
        // si des périodes sont disponibles ET toutes les 8 journées sont couvertes.
        if shouldCheckAvailability {
            guard daysCovered(periods: periods!, from: now, upTo: DashboardService.wakeSearchDays - 1,
                              calendar: calendar) else {
                return .insufficientData
            }
            return .holidaysConfirmed
        }
        // Périodes indisponibles : on ne peut ni confirmer un réveil ni conclure
        // à des vacances → données insuffisantes (alarme conservée par l'appelant).
        return .insufficientData
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

/// Extension pour extraire le plan optionnel associé au résultat.
extension AutoWakeResult {
    /// Le plan associé, nil si `.holidaysConfirmed` ou `.insufficientData`.
    var plan: AutoWakePlan? {
        if case .planned(let p) = self { return p }
        return nil
    }
}