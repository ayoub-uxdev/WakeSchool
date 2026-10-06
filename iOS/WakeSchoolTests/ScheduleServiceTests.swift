import XCTest
@testable import WakeSchool

final class ScheduleServiceTests: XCTestCase {
    private typealias T = TestSupport
    private let calendar = TestSupport.calendar

    /// Mercredi 7 : 8h-9h, 9h-10h (annulé), 10h15-11h15, 14h-15h. Jeudi 8 : 8h-9h.
    private func week() -> [TimetableEntry] {
        [T.entry(7, 14), T.entry(8, 8), T.entry(7, 10, 15),
         T.entry(7, 9, cancelled: true), T.entry(7, 8)]
    }

    func testSortedOrdersChronologically() {
        let sorted = ScheduleService.sorted(week())
        XCTAssertEqual(sorted.map(\.start), sorted.map(\.start).sorted())
        XCTAssertEqual(sorted.first?.start, T.date(7, 8))
        XCTAssertEqual(sorted.last?.start, T.date(8, 8))
    }

    func testEntriesOnDayExcludeCancelledByDefault() {
        let day = ScheduleService.entries(on: T.date(7), in: week(), calendar: calendar)
        XCTAssertEqual(day.count, 3)
        XCTAssertTrue(day.allSatisfy { !$0.isCancelled })

        let withCancelled = ScheduleService.entries(on: T.date(7), in: week(),
                                                    includeCancelled: true, calendar: calendar)
        XCTAssertEqual(withCancelled.count, 4)
    }

    func testCurrentCourseDuringACourse() {
        XCTAssertEqual(ScheduleService.currentCourse(at: T.date(7, 8, 30), in: week())?.start, T.date(7, 8))
    }

    func testNoCurrentCourseDuringCancelledSlot() {
        XCTAssertNil(ScheduleService.currentCourse(at: T.date(7, 9, 30), in: week()))
    }

    func testPastCourseIsNeverNext() {
        // 12h : les cours du matin sont passés, le prochain est celui de 14h.
        XCTAssertEqual(ScheduleService.nextCourse(after: T.date(7, 12), in: week())?.start, T.date(7, 14))
    }

    func testFutureCourseIsNext() {
        XCTAssertEqual(ScheduleService.nextCourse(after: T.date(7, 7), in: week())?.start, T.date(7, 8))
    }

    func testNextCourseSkipsCancelled() {
        // À 8h30, le cours de 9h est annulé : le prochain est 10h15.
        XCTAssertEqual(ScheduleService.nextCourse(after: T.date(7, 8, 30), in: week())?.start, T.date(7, 10, 15))
    }

    func testNextCourseRollsOverToNextDay() {
        XCTAssertEqual(ScheduleService.nextCourse(after: T.date(7, 16), in: week())?.start, T.date(8, 8))
    }

    func testNoNextCourseWhenNothingLeft() {
        XCTAssertNil(ScheduleService.nextCourse(after: T.date(9), in: week()))
    }

    func testFirstAndLastCourseOfDay() {
        XCTAssertEqual(ScheduleService.firstCourse(on: T.date(7), in: week(), calendar: calendar)?.start, T.date(7, 8))
        XCTAssertEqual(ScheduleService.lastCourse(on: T.date(7), in: week(), calendar: calendar)?.start, T.date(7, 14))
    }

    func testFirstCourseSkipsCancelledFirstCourse() {
        let entries = [T.entry(7, 8, cancelled: true), T.entry(7, 9, cancelled: true), T.entry(7, 10)]
        XCTAssertEqual(ScheduleService.firstCourse(on: T.date(7), in: entries, calendar: calendar)?.start, T.date(7, 10))
    }

    func testDayWithoutCourse() {
        XCTAssertTrue(ScheduleService.entries(on: T.date(10), in: week(), calendar: calendar).isEmpty)
        XCTAssertNil(ScheduleService.firstCourse(on: T.date(10), in: week(), calendar: calendar))
        XCTAssertNil(ScheduleService.lastCourse(on: T.date(10), in: week(), calendar: calendar))
    }

    func testDayWithOnlyCancelledCourses() {
        let entries = [T.entry(7, 8, cancelled: true)]
        XCTAssertNil(ScheduleService.firstCourse(on: T.date(7), in: entries, calendar: calendar))
    }

    func testCourseCrossingMidnightBelongsToItsStartDay() {
        let late = T.entry(7, 23, 30, minutes: 60)
        XCTAssertEqual(ScheduleService.entries(on: T.date(7), in: [late], calendar: calendar).count, 1)
        XCTAssertTrue(ScheduleService.entries(on: T.date(8), in: [late], calendar: calendar).isEmpty)
        XCTAssertEqual(ScheduleService.currentCourse(at: T.date(8, 0, 10), in: [late])?.id, late.id)
    }

    func testCancelledAndModifiedFilters() {
        let entries = week() + [T.entry(8, 10, modified: true), T.entry(8, 11, cancelled: true, modified: true)]
        XCTAssertEqual(ScheduleService.cancelled(entries).count, 2)
        XCTAssertEqual(ScheduleService.modified(entries).count, 1)
        XCTAssertEqual(ScheduleService.active(entries).count, entries.count - 2)
    }

    func testUpcomingWithLimit() {
        let result = ScheduleService.upcoming(after: T.date(7, 7), in: week(), limit: 2)
        XCTAssertEqual(result.map(\.start), [T.date(7, 8), T.date(7, 10, 15)])
    }

    func testStatus() {
        XCTAssertEqual(T.entry(7, 8).status, .normal)
        XCTAssertEqual(T.entry(7, 8, modified: true).status, .modified)
        XCTAssertEqual(T.entry(7, 8, cancelled: true, modified: true).status, .cancelled)
    }

    func testFirstCourseIsConsistentWithWakeTimeCalculator() {
        let first = ScheduleService.firstCourse(on: T.date(7), in: week(), calendar: calendar)
        XCTAssertEqual(first?.start, WakeTimeCalculator.firstCourseStart(in: week(), on: T.date(7), calendar: calendar))
    }
}
