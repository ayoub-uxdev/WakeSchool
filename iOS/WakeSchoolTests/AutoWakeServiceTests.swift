import XCTest
@testable import WakeSchool

final class AutoWakeServiceTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10, year: Int = 2026) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return calendar.date(from: c)!
    }

    private func course(day: Int, start: String, end: String, cancelled: Bool = false) -> TimetableEntry {
        let subject = Subject(id: UUID(), name: "Mathématiques")
        return TimetableEntry(id: UUID(), subject: subject, teacher: nil, room: nil,
                              start: PronoteJSON.date(["V": start])!,
                              end: PronoteJSON.date(["V": end])!,
                              isCancelled: cancelled)
    }

    private let settings = WakeSettings(travelMinutes: 20, preparationMinutes: 30, safetyMarginMinutes: 10)

    // MARK: - Plan

    func testNextRealSchoolDaySkipsCancelledFirstCourse() throws {
        // Vendredi 16/10 : premier cours annulé 08:00, remplacement 08:00 matière différente
        // et un vrai cours 10:00. Le premier cours ACTIF est 10:00 (08:00 annulé ignoré ;
        // le 08:00 restant est un cours distinct, non fusionné).
        let entries = [
            course(day: 16, start: "16/10/2026 08:00", end: "16/10/2026 09:00", cancelled: true),
            course(day: 16, start: "16/10/2026 10:00", end: "16/10/2026 11:00")
        ]
        let now = date(16, 7, 0)

        let plan = try XCTUnwrap(AutoWakeService.plan(entries: entries, now: now,
                                                      settings: settings, calendar: calendar))
        XCTAssertEqual(plan.recommendation.firstClassStart, PronoteJSON.date(["V": "16/10/2026 10:00"]))
    }

    func testModifiedCourseRemainsActive() throws {
        // Un cours modifié (isModified) reste un cours actif pour le réveil.
        let subject = Subject(id: UUID(), name: "Histoire")
        let modified = TimetableEntry(id: UUID(), subject: subject, teacher: nil, room: nil,
                                      start: PronoteJSON.date(["V": "16/10/2026 08:00"])!,
                                      end: PronoteJSON.date(["V": "16/10/2026 09:00"])!,
                                      isModified: true)
        let now = date(16, 7, 0)

        let plan = try XCTUnwrap(AutoWakeService.plan(entries: [modified], now: now,
                                                      settings: settings, calendar: calendar))
        XCTAssertEqual(plan.firstCourse.isModified, true)
        XCTAssertEqual(plan.recommendation.firstClassStart, modified.start)
    }

    func testNoCourseOnWeekendReturnsNil() {
        // Dimanche 18/10/2026 : aucun cours.
        let now = date(18, 7, 0)
        XCTAssertNil(AutoWakeService.plan(entries: [], now: now, settings: settings, calendar: calendar))
    }

    func testEmptyTimetableReturnsNil() {
        let now = date(16, 7, 0)
        XCTAssertNil(AutoWakeService.plan(entries: [], now: now, settings: settings, calendar: calendar))
    }

    func testCancelledOnlyDayFallsBackToNextDay() throws {
        // Vendredi 16 : uniquement un cours annulé (déjà passé ou pas).
        // Samedi 17 : rien. Lundi 19 : cours à 08:00 → le plan vise le lundi.
        let entries = [
            course(day: 16, start: "16/10/2026 08:00", end: "16/10/2026 09:00", cancelled: true),
            course(day: 19, start: "19/10/2026 08:00", end: "19/10/2026 09:00")
        ]
        let now = date(16, 7, 0)

        let plan = try XCTUnwrap(AutoWakeService.plan(entries: entries, now: now,
                                                      settings: settings, calendar: calendar))
        XCTAssertEqual(calendar.isDate(plan.targetDay, inSameDayAs: date(19, 0, 0)), true)
    }

    // MARK: - Réveil personnalisé

    func testCustomWakeTimeReplacesRecommendation() throws {
        let entries = [course(day: 16, start: "16/10/2026 08:00", end: "16/10/2026 09:00")]
        let now = date(16, 7, 0)

        let plan = try XCTUnwrap(AutoWakeService.plan(entries: entries, now: now,
                                                      settings: settings,
                                                      customWakeMinutesFromMidnight: 6 * 60 + 30,
                                                      calendar: calendar))
        XCTAssertTrue(plan.isCustom)
        XCTAssertEqual(plan.recommendation.wakeTime, date(16, 6, 30))
        // Le premier cours de référence reste inchangé.
        XCTAssertEqual(plan.recommendation.firstClassStart, PronoteJSON.date(["V": "16/10/2026 08:00"]))
    }

    func testCustomWakeInvalidMinutesIsIgnored() throws {
        let entries = [course(day: 16, start: "16/10/2026 08:00", end: "16/10/2026 09:00")]
        let now = date(16, 7, 0)

        let plan = try XCTUnwrap(AutoWakeService.plan(entries: entries, now: now,
                                                      settings: settings,
                                                      customWakeMinutesFromMidnight: 1500, // invalide
                                                      calendar: calendar))
        XCTAssertFalse(plan.isCustom)
    }

    // MARK: - Anti-doublon

    func testShouldReschedulePreventsDuplicates() {
        let alarm = date(17, 6, 45)
        XCTAssertFalse(AutoWakeService.shouldReschedule(existingFireDate: alarm, desiredFireDate: date(17, 6, 45)))
        XCTAssertFalse(AutoWakeService.shouldReschedule(existingFireDate: alarm, desiredFireDate: date(17, 6, 45, month: 10).addingTimeInterval(30)))
        XCTAssertTrue(AutoWakeService.shouldReschedule(existingFireDate: alarm, desiredFireDate: date(17, 6, 30)))
        XCTAssertTrue(AutoWakeService.shouldReschedule(existingFireDate: nil, desiredFireDate: alarm))
        XCTAssertTrue(AutoWakeService.shouldReschedule(existingFireDate: alarm, desiredFireDate: nil))
        XCTAssertFalse(AutoWakeService.shouldReschedule(existingFireDate: nil, desiredFireDate: nil))
    }

    // MARK: - Changement après synchronisation

    func testPlanChangesAfterTimetableUpdate() throws {
        // Avant sync : premier cours 08:00. Après sync : 09:00 (changé).
        let before = [course(day: 16, start: "16/10/2026 08:00", end: "16/10/2026 09:00")]
        let after = [course(day: 16, start: "16/10/2026 09:00", end: "16/10/2026 10:00")]
        let now = date(16, 7, 0)

        let planBefore = try XCTUnwrap(AutoWakeService.plan(entries: before, now: now, settings: settings, calendar: calendar))
        let planAfter = try XCTUnwrap(AutoWakeService.plan(entries: after, now: now, settings: settings, calendar: calendar))
        XCTAssertNotEqual(planBefore.recommendation.wakeTime, planAfter.recommendation.wakeTime)
        XCTAssertTrue(AutoWakeService.shouldReschedule(existingFireDate: planBefore.recommendation.wakeTime,
                                                       desiredFireDate: planAfter.recommendation.wakeTime))
    }
}
