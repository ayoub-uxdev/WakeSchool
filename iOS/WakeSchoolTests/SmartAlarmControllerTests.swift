import XCTest
@testable import WakeSchool

/// Teste la logique autour d'AlarmKit avec un faux `AlarmScheduling`.
/// Ces tests NE vérifient PAS le vrai AlarmKit (qui nécessite un iPhone) : voir le test manuel du LOT 3.
@MainActor
final class SmartAlarmControllerTests: XCTestCase {
    private typealias T = TestSupport

    private struct FakeError: LocalizedError {
        var errorDescription: String? { "boom" }
    }

    @MainActor
    private final class FakeScheduler: AlarmScheduling {
        var scheduleResult: Result<UUID, Error> = .success(UUID())
        var cancelError: Error?
        var isScheduledResult: Result<Bool, Error> = .success(true)
        private(set) var scheduledDates: [Date] = []
        private(set) var cancelledIDs: [UUID] = []

        func schedule(at date: Date) async throws -> UUID {
            scheduledDates.append(date)
            return try scheduleResult.get()
        }

        func cancel(id: UUID) throws {
            cancelledIDs.append(id)
            if let cancelError { throw cancelError }
        }

        func isScheduled(id: UUID) throws -> Bool {
            try isScheduledResult.get()
        }
    }

    private let now = T.date(7, 12)

    private func recommendation(wake: Date) -> WakeTimeRecommendation {
        WakeTimeRecommendation(
            wakeTime: wake,
            departureTime: wake.addingTimeInterval(40 * 60),
            firstClassStart: wake.addingTimeInterval(75 * 60)
        )
    }

    private func makeController(
        _ scheduler: FakeScheduler? = nil,
        store: InMemoryScheduledAlarmStore? = nil
    ) -> (SmartAlarmController, FakeScheduler, InMemoryScheduledAlarmStore) {
        let scheduler = scheduler ?? FakeScheduler()
        let store = store ?? InMemoryScheduledAlarmStore()
        let now = self.now

        return (
            SmartAlarmController(
                scheduler: scheduler,
                store: store,
                now: { now }
            ),
            scheduler,
            store
        )
    }

    // MARK: Date future / passée

    func testFutureDateIsScheduledAndPersisted() async {
        let (controller, scheduler, store) = makeController()
        let wake = T.date(8, 6, 45)
        let id = try! scheduler.scheduleResult.get()

        await controller.schedule(recommendation(wake: wake))

        XCTAssertEqual(scheduler.scheduledDates, [wake])
        XCTAssertEqual(controller.scheduledAlarm, ScheduledAlarm(id: id, fireDate: wake))
        XCTAssertEqual(store.current, controller.scheduledAlarm)
        XCTAssertNil(controller.issue)
        XCTAssertFalse(controller.isWorking)
    }

    func testPastDateNeverReachesAlarmKit() async {
        let (controller, scheduler, store) = makeController()

        await controller.schedule(recommendation(wake: T.date(7, 6, 45)))

        XCTAssertTrue(scheduler.scheduledDates.isEmpty)
        XCTAssertNil(controller.scheduledAlarm)
        XCTAssertNil(store.current)
        XCTAssertEqual(controller.issue, .message(AlarmError.dateInPast.localizedDescription))
    }

    func testDateEqualToNowIsRejected() async {
        let (controller, scheduler, _) = makeController()

        await controller.schedule(recommendation(wake: now))

        XCTAssertTrue(scheduler.scheduledDates.isEmpty)
        XCTAssertNotNil(controller.issue)
    }

    func testMissingRecommendationIsAnErrorWithoutCallingAlarmKit() async {
        let (controller, scheduler, _) = makeController()

        await controller.schedule(nil)

        XCTAssertTrue(scheduler.scheduledDates.isEmpty)
        XCTAssertEqual(controller.issue, .message(WakeTimeError.noCourse.localizedDescription))
    }

    func testValidate() {
        let future = recommendation(wake: T.date(8, 6, 45))
        if case .success(let date) = SmartAlarmController.validate(future, now: now) {
            XCTAssertEqual(date, future.wakeTime)
        } else {
            XCTFail("Une date future doit être valide")
        }

        if case .failure(let error) = SmartAlarmController.validate(
            recommendation(wake: T.date(7, 6)),
            now: now
        ), case AlarmError.dateInPast = error {
        } else {
            XCTFail("Une date passée doit donner dateInPast")
        }

        if case .failure(let error) = SmartAlarmController.validate(nil, now: now),
           let wakeError = error as? WakeTimeError {
            XCTAssertEqual(wakeError, .noCourse)
        } else {
            XCTFail("Pas de réveil doit donner noCourse")
        }
    }

    // MARK: Erreurs

    func testPermissionDeniedIsReportedAndNothingIsStored() async {
        let scheduler = FakeScheduler()
        scheduler.scheduleResult = .failure(AlarmError.notAuthorized)
        let (controller, _, store) = makeController(scheduler)

        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))

        XCTAssertEqual(controller.issue, .permissionDenied)
        XCTAssertNil(controller.scheduledAlarm)
        XCTAssertNil(store.current)
        XCTAssertFalse(controller.isWorking)
    }

    func testSchedulingFailureIsReadableAndAppStaysUsable() async {
        let scheduler = FakeScheduler()
        scheduler.scheduleResult = .failure(AlarmError.schedulingFailed(FakeError()))
        let (controller, _, _) = makeController(scheduler)

        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))

        XCTAssertEqual(controller.issue, .message("Impossible de programmer l'alarme : boom"))
        XCTAssertNil(controller.scheduledAlarm)

        // On peut réessayer ensuite.
        scheduler.scheduleResult = .success(UUID())
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))
        XCTAssertNil(controller.issue)
        XCTAssertNotNil(controller.scheduledAlarm)
    }

    func testUnexpectedErrorIsMappedToMessage() async {
        let scheduler = FakeScheduler()
        scheduler.scheduleResult = .failure(FakeError())
        let (controller, _, _) = makeController(scheduler)

        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))

        XCTAssertEqual(controller.issue, .message("boom"))
    }

    // MARK: Annulation / état

    func testCancelClearsAlarm() async {
        let (controller, scheduler, store) = makeController()
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))
        let id = controller.scheduledAlarm!.id

        controller.cancel()

        XCTAssertEqual(scheduler.cancelledIDs, [id])
        XCTAssertNil(controller.scheduledAlarm)
        XCTAssertNil(store.current)
        XCTAssertNil(controller.issue)
    }

    func testCancelFailureWhenSystemStillHasAlarmKeepsItAndReportsError() async {
        let (controller, scheduler, store) = makeController()
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))
        scheduler.cancelError = AlarmError.cancelFailed(FakeError())
        scheduler.isScheduledResult = .success(true)

        controller.cancel()

        XCTAssertNotNil(controller.scheduledAlarm)
        XCTAssertNotNil(store.current)
        XCTAssertEqual(controller.issue, .message("Impossible d'annuler l'alarme : boom"))
    }

    func testCancelFailureWhenAlarmAlreadyGoneClearsState() async {
        let (controller, scheduler, _) = makeController()
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))
        scheduler.cancelError = AlarmError.cancelFailed(FakeError())
        scheduler.isScheduledResult = .success(false)

        controller.cancel()

        XCTAssertNil(controller.scheduledAlarm)
        XCTAssertNil(controller.issue)
    }

    func testRefreshClearsAlarmUnknownToSystem() async {
        let (controller, scheduler, store) = makeController()
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))
        scheduler.isScheduledResult = .success(false)

        controller.refresh()

        XCTAssertNil(controller.scheduledAlarm)
        XCTAssertNil(store.current)
    }

    func testRefreshKeepsAlarmWhenSystemKnowsIt() async {
        let (controller, _, _) = makeController()
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))

        controller.refresh()

        XCTAssertNotNil(controller.scheduledAlarm)
    }

    func testRefreshKeepsAlarmWhenSystemQueryFails() async {
        let (controller, scheduler, _) = makeController()
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))
        scheduler.isScheduledResult = .failure(FakeError())

        controller.refresh()

        XCTAssertNotNil(controller.scheduledAlarm)
    }

    func testStoredAlarmIsRestoredAtInit() {
        let stored = ScheduledAlarm(id: UUID(), fireDate: T.date(8, 6, 45))
        let (controller, _, _) = makeController(
            store: InMemoryScheduledAlarmStore(current: stored)
        )

        XCTAssertEqual(controller.scheduledAlarm, stored)
    }

    func testNoAlarmKitCallAtInitOrRefreshWithoutAlarm() {
        let (controller, scheduler, _) = makeController()

        controller.refresh()

        XCTAssertTrue(scheduler.scheduledDates.isEmpty)
        XCTAssertTrue(scheduler.cancelledIDs.isEmpty)
    }

    // MARK: Remplacement

    func testRescheduleCancelsPreviousAlarmAfterSuccess() async {
        let (controller, scheduler, _) = makeController()
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))
        let first = controller.scheduledAlarm!
        let secondID = UUID()
        scheduler.scheduleResult = .success(secondID)

        await controller.schedule(recommendation(wake: T.date(8, 7, 0)))

        XCTAssertEqual(scheduler.cancelledIDs, [first.id])
        XCTAssertEqual(
            controller.scheduledAlarm,
            ScheduledAlarm(id: secondID, fireDate: T.date(8, 7, 0))
        )
    }

    func testFailedRescheduleKeepsPreviousAlarm() async {
        let (controller, scheduler, _) = makeController()
        await controller.schedule(recommendation(wake: T.date(8, 6, 45)))
        let first = controller.scheduledAlarm
        scheduler.scheduleResult = .failure(AlarmError.schedulingFailed(FakeError()))

        await controller.schedule(recommendation(wake: T.date(8, 7, 0)))

        XCTAssertEqual(controller.scheduledAlarm, first)
        XCTAssertTrue(scheduler.cancelledIDs.isEmpty)
        XCTAssertNotNil(controller.issue)
    }

    // MARK: Calcul de l'heure (réel, via le store/services)

    func testRecommendationUsesTimetableAndSettingsViaWakeTimeCalculator() throws {
        let entries = [T.entry(8, 9), T.entry(8, 8), T.entry(8, 7, cancelled: true)]
        let settings = WakeSettings(
            travelMinutes: 25,
            preparationMinutes: 40,
            safetyMarginMinutes: 10
        )

        let result = try XCTUnwrap(
            SmartAlarmController.recommendation(
                entries: entries,
                now: now,
                settings: settings,
                calendar: T.calendar
            )
        )

        XCTAssertEqual(result.firstClassStart, T.date(8, 8))
        XCTAssertEqual(result.departureTime, T.date(8, 7, 25))
        XCTAssertEqual(result.wakeTime, T.date(8, 6, 45))
        XCTAssertEqual(
            result,
            try WakeTimeCalculator.recommend(
                WakeTimeInput(
                    firstClassStart: T.date(8, 8),
                    travelMinutes: 25,
                    preparationMinutes: 40,
                    safetyMarginMinutes: 10
                )
            )
        )
    }

    func testNoUpcomingCourseGivesNoRecommendation() {
        XCTAssertNil(
            SmartAlarmController.recommendation(
                entries: [],
                now: now,
                settings: .default,
                calendar: T.calendar
            )
        )
    }

    func testWakeAlreadyPassedForTodaysCourseIsRejectedByValidation() throws {
        // Cours à 08:00 aujourd'hui, il est 07:00 : le réveil (06:45) est passé.
        let early = T.date(7, 7)
        let entries = [T.entry(7, 8)]
        let rec = try XCTUnwrap(
            SmartAlarmController.recommendation(
                entries: entries,
                now: early,
                settings: .default,
                calendar: T.calendar
            )
        )

        if case .failure(let error) = SmartAlarmController.validate(rec, now: early),
           case AlarmError.dateInPast = error {
        } else {
            XCTFail("Le réveil passé doit être refusé")
        }
    }

    // MARK: Persistance

    func testUserDefaultsStoreRoundTrip() {
        let defaults = UserDefaults(
            suiteName: "WakeSchoolAlarmTests-\(UUID().uuidString)"
        )!
        let store = UserDefaultsScheduledAlarmStore(defaults: defaults)
        XCTAssertNil(store.current)

        let alarm = ScheduledAlarm(id: UUID(), fireDate: T.date(8, 6, 45))
        store.current = alarm
        XCTAssertEqual(
            UserDefaultsScheduledAlarmStore(defaults: defaults).current,
            alarm
        )

        store.current = nil
        XCTAssertNil(store.current)
    }

    // MARK: Messages d'erreur

    func testAlarmErrorMessagesAreReadable() {
        XCTAssertNotNil(AlarmError.notAuthorized.errorDescription)
        XCTAssertNotNil(AlarmError.dateInPast.errorDescription)
        XCTAssertTrue(
            AlarmError.schedulingFailed(FakeError()).localizedDescription.contains("boom")
        )
        XCTAssertTrue(
            AlarmError.cancelFailed(FakeError()).localizedDescription.contains("boom")
        )
    }
}
