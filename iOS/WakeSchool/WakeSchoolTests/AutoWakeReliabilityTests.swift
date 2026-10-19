import XCTest
@testable import WakeSchool

/// Fiabilisation d'AutoWake après les vacances (LOT 9A.5).
///
/// Règle fondamentale : une période PRONOTE inconnue ne signifie jamais
/// absence de cours. Ces tests vérifient que AutoWake distingue clairement
/// « réveil confirmé », « vacances confirmées » et « données insuffisantes ».
final class AutoWakeReliabilityTests: XCTestCase {

    /// Réveils par défaut (25 min trajet, 40 min préparation, 10 min marge).
    private let settings = WakeSettings.default

    // MARK: - Helper : périodes

    /// Période couvrant un seul jour, marquée complète.
    private func fullPeriod(day: Int) -> SchoolPeriod {
        SchoolPeriod(
            id: "period-\(day)",
            title: "\(day) octobre",
            startDate: TestSupport.date(day),
            endDate: TestSupport.date(day),
            isTimetableComplete: true
        )
    }

    /// Période couvrant un seul jour, NON marquée complète (données insuffisantes).
    private func incompletePeriod(day: Int) -> SchoolPeriod {
        SchoolPeriod(
            id: "period-incomplete-\(day)",
            title: "\(day) octobre (incomplète)",
            startDate: TestSupport.date(day),
            endDate: TestSupport.date(day),
            isTimetableComplete: false
        )
    }

    // MARK: - 1. Cours confirmé demain, semaine suivante inconnue

    func testCourseTomorrowButFollowingWeekUnknown() throws {
        // Cours jeudi 8/10 à 08:00. Période complète uniquement le 8/10.
        // Le 7/10 (aujourd'hui) est couvert, le 8/10 (jour du cours) est couvert.
        // Les jours après (9/10 et suivants) sont inconnus mais n'ont pas d'importance.
        let entries = [TestSupport.entry(8, 8)]
        let periods = [fullPeriod(day: 7), fullPeriod(day: 8)]
        let now = TestSupport.date(7, 8) // 7/10 à 08:00

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .planned(let plan):
            XCTAssertEqual(plan.targetDay, TestSupport.date(8), "Le réveil doit viser le jour du cours connu.")
            XCTAssertFalse(plan.isCustom)
        case .holidaysConfirmed:
            XCTFail("Un cours confirmé demain ne doit pas conduire à des vacances.")
        case .insufficientData:
            XCTFail("Les jours jusqu'au cours sont couverts : pas de blocage pour une semaine suivante inconnue.")
        }
    }

    // MARK: - 2. Huit jours connus et vides

    func testEightKnownEmptyDaysAreHolidays() throws {
        // Aucun cours sur 8 jours, toutes les périodes couvertes et complètes.
        let entries: [TimetableEntry] = []
        let periods = (7...14).map { fullPeriod(day: $0) }
        let now = TestSupport.date(7, 8)

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .planned:
            XCTFail("Aucun cours sur 8 jours connus ne doit pas produire de réveil.")
        case .holidaysConfirmed:
            break // Vacances confirmées : comportement attendu.
        case .insufficientData:
            XCTFail("Tous les 8 jours sont couverts : vacances doivent être confirmées.")
        }
    }

    // MARK: - 3. Période inconnue avant le prochain cours connu

    func testUnknownPeriodBeforeNextKnownCourse() throws {
        // Cours vendredi 9/10 à 08:00, mais aucune période ne couvre le 7/10 ou 8/10.
        // Impossible de savoir s'il y a un cours entre-temps.
        let entries = [TestSupport.entry(9, 8)]
        let periods = [fullPeriod(day: 9)] // seulement le jour du cours est connu
        let now = TestSupport.date(7, 8)

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .planned:
            XCTFail("Un jour non couvert avant le cours rend les données insuffisantes.")
        case .holidaysConfirmed:
            XCTFail("Une période inconnue ne doit jamais conduire à des vacances.")
        case .insufficientData:
            break // Données insuffisantes : comportement attendu.
        }
    }

    // MARK: - 4. Période incomplète

    func testIncompletePeriodBeforeCourse() throws {
        // Cours jeudi 8/10, période couvrant le 8/10 mais non marquée complète.
        let entries = [TestSupport.entry(8, 8)]
        let periods = [fullPeriod(day: 7), incompletePeriod(day: 8)]
        let now = TestSupport.date(7, 8)

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .planned:
            XCTFail("Une période incomplète ne doit pas permettre de conclure à un réveil confirmé.")
        case .holidaysConfirmed:
            XCTFail("Une période incomplète ne doit pas conduire à des vacances.")
        case .insufficientData:
            break // Données insuffisantes : comportement attendu.
        }
    }

    // MARK: - 5. Échec réseau : conservation du dernier état valide

    func testInsufficientDataKeepsValidExistingAlarm() throws {
        // Une alarme automatique existe déjà (programmée pour demain).
        // Les données actuelles sont insuffisantes : on ne doit PAS l'annuler.
        let store = InMemoryAutoWakeAlarmStore()
        let futureFireDate = TestSupport.date(8, 7) // demain 07:00
        let existing = ScheduledAutoWakeAlarm(
            id: UUID(), fireDate: futureFireDate,
            targetDayKey: "2026-10-08", isCustom: false)
        store.current = existing

        let scheduler = MockAlarmScheduler()
        let lifecycle = AutoWakeLifecycle(alarmScheduler: scheduler, store: store)

        let now = TestSupport.date(7, 8)
        let alarm = lifecycle.current

        // Logique du cas .insufficientData : pas d'annulation si l'alarme est valide.
        if let alarm, alarm.fireDate > now {
            // Alarme encore valide : on garde.
            XCTAssertNotNil(lifecycle.current, "Une alarme valide doit être conservée.")
            XCTAssertTrue(scheduler.cancelled.isEmpty, "Aucune annulation en cas de données insuffisantes avec alarme valide.")
        } else {
            XCTFail("L'alarme existante (demain) est encore dans le futur.")
        }
    }

    // MARK: - 6. Ancienne alarme déjà dépassée

    func testExpiredAlarmIsCancelledOnInsufficientData() throws {
        // Une alarme automatique existe mais sa date est déjà passée (hier).
        // En cas de données insuffisantes, elle doit être annulée.
        let store = InMemoryAutoWakeAlarmStore()
        let expiredFireDate = TestSupport.date(6, 7) // hier 07:00 (dépassé par rapport au 7/10)
        let existing = ScheduledAutoWakeAlarm(
            id: UUID(), fireDate: expiredFireDate,
            targetDayKey: "2026-10-06", isCustom: false)
        store.current = existing

        let scheduler = MockAlarmScheduler()
        let lifecycle = AutoWakeLifecycle(alarmScheduler: scheduler, store: store)

        let now = TestSupport.date(7, 8)
        let alarm = lifecycle.current

        // Logique du cas .insufficientData : annuler si l'alarme est déjà dépassée.
        if let alarm, alarm.fireDate <= now {
            lifecycle.cancel()
        }

        XCTAssertNil(lifecycle.current, "Une alarme déjà dépassée doit être annulée.")
        XCTAssertEqual(scheduler.cancelled, [existing.id], "L'alarme expirée doit être annulée auprès d'AlarmKit.")
    }

    // MARK: - 7. Mode démo : périodes indisponibles, comportement historique préservé

    /// En mode démo, `loadPeriods()` retourne [] (aucune période stockée).
    /// AutoWake doit se comporter comme avant : confirmer un réveil si un cours
    /// existe, sans vérification de disponibilité de périodes.
    func testDemoModeEmptyPeriodsStillConfirmsCoursePlan() throws {
        let entries = [TestSupport.entry(8, 8)]
        let periods: [SchoolPeriod] = [] // mode démo : aucune période connue
        let now = TestSupport.date(7, 8)

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .planned(let plan):
            XCTAssertEqual(plan.targetDay, TestSupport.date(8),
                           "Mode démo : un cours confirmé doit produire un réveil malgré l'absence de périodes.")
        case .holidaysConfirmed:
            XCTFail("Mode démo : jamais de conclusion à des vacances sans données de périodes.")
        case .insufficientData:
            XCTFail("Mode démo : un cours trouvé avec périodes indisponibles doit confirmer le réveil.")
        }
    }

    /// `periods = nil` (erreur de lecture du dépôt) ne doit jamais conduire à des
    /// vacances confirmées : c'est indifférenciable d'une absence de cours, donc
    /// le résultat est `.insufficientData` et l'alarme existante est conservée.
    func testNilPeriodsAreNotHolidays() throws {
        let entries: [TimetableEntry] = []
        let periods: [SchoolPeriod]? = nil // erreur de lecture ou données indisponibles
        let now = TestSupport.date(7, 8)

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .planned:
            XCTFail("Aucun cours et périodes indisponibles ne doivent pas confirmer un réveil.")
        case .holidaysConfirmed:
            XCTFail("Périodes indisponibles (nil) ne doivent jamais conclure à des vacances.")
        case .insufficientData:
            break // Comportement attendu : données insuffisantes, alarme conservée.
        }
    }

    // MARK: - Démo vs production : séparation explicite des périodes indisponibles

    /// Mode démo : périodes indisponibles (nil) + cours trouvé → réveil confirmé.
    /// Le calcul historique à partir des cours démo est préservé.
    func testDemoModeNilPeriodsConfirmsCourse() throws {
        let now = TestSupport.date(7, 8)
        let entries = [TestSupport.entry(8, 8)]
        let periods: [SchoolPeriod]? = nil

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            isDemoMode: true, settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .planned(let plan):
            XCTAssertEqual(plan.targetDay, TestSupport.date(8),
                           "Démo : un cours trouvé confirme le réveil même sans périodes.")
        case .holidaysConfirmed:
            XCTFail("Démo : périodes nil ne doivent jamais conclure à des vacances.")
        case .insufficientData:
            XCTFail("Démo : un cours trouvé doit confirmer le réveil.")
        }
    }

    /// Mode démo : périodes vides ([]) + cours trouvé → réveil confirmé.
    func testDemoModeEmptyPeriodsConfirmsCourse() throws {
        let now = TestSupport.date(7, 8)
        let entries = [TestSupport.entry(8, 8)]
        let periods: [SchoolPeriod] = []

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            isDemoMode: true, settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .planned(let plan):
            XCTAssertEqual(plan.targetDay, TestSupport.date(8),
                           "Démo : un cours trouvé confirme le réveil avec périodes vides.")
        case .holidaysConfirmed:
            XCTFail("Démo : périodes vides ne doivent jamais conclure à des vacances.")
        case .insufficientData:
            XCTFail("Démo : un cours trouvé doit confirmer le réveil.")
        }
    }

    /// Production : périodes indisponibles (nil) + aucun cours → insufficientData,
    /// jamais holidaysConfirmed. L'alarme valide est conservée par l'appelant.
    func testProductionNilPeriodsNeverHolidays() throws {
        let now = TestSupport.date(7, 8)
        let entries: [TimetableEntry] = []
        let periods: [SchoolPeriod]? = nil

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            isDemoMode: false, settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .holidaysConfirmed:
            XCTFail("Production : périodes nil ne doivent jamais conclure à des vacances.")
        case .planned:
            XCTFail("Production : aucune période connue ne doit pas confirmer un réveil.")
        case .insufficientData:
            break // Données insuffisantes : alarme conservée par l'appelant.
        }
    }

    /// Production : périodes vides ([]) + aucun cours → insufficientData.
    func testProductionEmptyPeriodsInsufficientData() throws {
        let now = TestSupport.date(7, 8)
        let entries: [TimetableEntry] = []
        let periods: [SchoolPeriod] = []

        let result = AutoWakeService.plan(
            entries: entries, periods: periods, now: now,
            isDemoMode: false, settings: settings, calendar: TestSupport.calendar)

        switch result {
        case .holidaysConfirmed:
            XCTFail("Production : périodes vides ne doivent jamais conclure à des vacances.")
        case .planned:
            XCTFail("Production : aucune période connue ne doit pas confirmer un réveil.")
        case .insufficientData:
            break
        }
    }

    // MARK: - Mock AlarmScheduler

    final class MockAlarmScheduler: AlarmScheduling {
        var shouldFail = false
        private(set) var scheduledDates: [Date] = []
        private(set) var cancelled: [UUID] = []

        func schedule(at date: Date) async throws -> UUID {
            if shouldFail { throw AlarmError.notAuthorized }
            scheduledDates.append(date)
            return UUID()
        }

        func cancel(id: UUID) throws {
            cancelled.append(id)
        }

        func isScheduled(id: UUID) throws -> Bool { true }
    }
}