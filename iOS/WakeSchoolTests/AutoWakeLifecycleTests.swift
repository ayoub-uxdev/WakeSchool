import XCTest
@testable import WakeSchool

/// Cycle de vie AutoWake : store isolé des alarmes manuelles, annulations,
/// reprogrammations, jamais d'inscription partielle en cas d'échec AlarmKit.
final class AutoWakeLifecycleTests: XCTestCase {

    /// Faux scheduler AlarmKit qui peut échouer volontairement.
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

    private func makePlan(wakeDate: Date, custom: Bool = false) -> AutoWakePlan {
        let course = TimetableEntry(id: UUID(),
                                    subject: Subject(id: UUID(), name: "Maths"),
                                    teacher: nil, room: nil,
                                    start: wakeDate.addingTimeInterval(2 * 3600),
                                    end: wakeDate.addingTimeInterval(3 * 3600))
        let recommendation = WakeTimeRecommendation(wakeTime: wakeDate,
                                                    departureTime: wakeDate.addingTimeInterval(3600),
                                                    firstClassStart: course.start)
        return AutoWakePlan(targetDay: Calendar.current.startOfDay(for: wakeDate),
                            firstCourse: course,
                            recommendation: recommendation,
                            isCustom: custom)
    }

    private func makeLifecycle(shouldFail: Bool = false) -> (AutoWakeLifecycle, MockAlarmScheduler, InMemoryAutoWakeAlarmStore) {
        let scheduler = MockAlarmScheduler()
        scheduler.shouldFail = shouldFail
        let store = InMemoryAutoWakeAlarmStore()
        return (AutoWakeLifecycle(alarmScheduler: scheduler, store: store), scheduler, store)
    }

    @MainActor
    func testScheduleStoresAlarmOnlyOnSuccess() async throws {
        let (lifecycle, scheduler, store) = makeLifecycle()
        let plan = makePlan(wakeDate: Date().addingTimeInterval(3600))

        let scheduled = await lifecycle.schedule(plan: plan)

        XCTAssertNotNil(scheduled, "Une alarme programmée avec succès doit être mémorisée.")
        XCTAssertEqual(store.current?.id, scheduled?.id)
        XCTAssertEqual(scheduler.scheduledDates.count, 1)
        XCTAssertEqual(scheduler.scheduledDates.first, plan.recommendation.wakeTime)
    }

    @MainActor
    func testScheduleFailureDoesNotRegisterAnything() async throws {
        let (lifecycle, scheduler, store) = makeLifecycle(shouldFail: true)
        let plan = makePlan(wakeDate: Date().addingTimeInterval(3600))

        let scheduled = await lifecycle.schedule(plan: plan)

        XCTAssertNil(scheduled, "Aucune alarme ne doit être mémorisée si AlarmKit échoue.")
        XCTAssertNil(store.current, "Le store ne doit PAS être mis à jour en cas d'échec.")
        XCTAssertTrue(scheduler.scheduledDates.isEmpty)
    }

    @MainActor
    func testRescheduleCancelsOnlyPreviousAutoWakeAlarm() async throws {
        let (lifecycle, scheduler, store) = makeLifecycle()
        let firstPlan = makePlan(wakeDate: Date().addingTimeInterval(3600))
        let first = try XCTUnwrap(await lifecycle.schedule(plan: firstPlan))

        // Deuxième plan à une autre heure → reprogrammation.
        let secondPlan = makePlan(wakeDate: Date().addingTimeInterval(7200))
        _ = await lifecycle.schedule(plan: secondPlan)

        XCTAssertEqual(scheduler.cancelled, [first.id], "Seule l'ancienne alarme AUTOMATIQUE est annulée.")
        XCTAssertEqual(store.current?.fireDate, secondPlan.recommendation.wakeTime)
    }

    @MainActor
    func testDisableCancelsAutoWakeAlarmOnly() async throws {
        let (lifecycle, scheduler, _) = makeLifecycle()
        _ = await lifecycle.schedule(plan: makePlan(wakeDate: Date().addingTimeInterval(3600)))
        let current = try XCTUnwrap(lifecycle.current)

        lifecycle.disable()

        XCTAssertEqual(scheduler.cancelled, [current.id], "La désactivation annule l'alarme automatique.")
        XCTAssertNil(lifecycle.current)
    }

    @MainActor
    func testReconcileCancelsWhenPlanDisappears() async throws {
        let (lifecycle, scheduler, _) = makeLifecycle()
        _ = await lifecycle.schedule(plan: makePlan(wakeDate: Date().addingTimeInterval(3600)))
        let current = try XCTUnwrap(lifecycle.current)

        // Le premier cours disparaît : plan nil → alarme obsolète annulée.
        let didCancel = lifecycle.reconcile(plan: nil)

        XCTAssertTrue(didCancel)
        XCTAssertEqual(scheduler.cancelled, [current.id])
        XCTAssertNil(lifecycle.current)
    }

    @MainActor
    func testReconcileKeepsAlarmWhenPlanStillValid() async throws {
        let (lifecycle, scheduler, _) = makeLifecycle()
        _ = await lifecycle.schedule(plan: makePlan(wakeDate: Date().addingTimeInterval(3600)))

        let didCancel = lifecycle.reconcile(plan: makePlan(wakeDate: Date().addingTimeInterval(3600)))

        XCTAssertFalse(didCancel)
        XCTAssertTrue(scheduler.cancelled.isEmpty, "Un plan valide ne déclenche pas d'annulation.")
        XCTAssertNotNil(lifecycle.current)
    }

    @MainActor
    func testLifecycleIsolatedFromManualAlarmStore() throws {
        // L'alarme manuelle (SmartAlarmView) vit dans un autre store : les clés
        // UserDefaults doivent être distinctes pour ne jamais se contaminer.
        let autoWakeStore = UserDefaultsAutoWakeAlarmStore(defaults: UserDefaults(suiteName: "AutoWakeLifecycleTests-\(UUID().uuidString)")!)
        autoWakeStore.current = ScheduledAutoWakeAlarm(id: UUID(), fireDate: Date(), targetDayKey: "2026-10-17", isCustom: false)

        // Le store manuel ne doit pas voir l'alarme automatique.
        let manualStore = UserDefaultsScheduledAlarmStore(defaults: UserDefaults(suiteName: "AutoWakeLifecycleTests-\(UUID().uuidString)")!)
        XCTAssertNil(manualStore.current, "L'alarme automatique ne doit pas apparaître dans le store des alarmes manuelles.")
    }
}
