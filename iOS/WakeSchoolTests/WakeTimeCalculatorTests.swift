import XCTest
@testable import WakeSchool

final class WakeTimeCalculatorTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
        return calendar.date(from: components)!
    }

    private func entry(start: Date, cancelled: Bool = false) -> TimetableEntry {
        TimetableEntry(id: UUID(),
                       subject: Subject(id: UUID(), name: "Maths"),
                       start: start,
                       end: start.addingTimeInterval(3600),
                       isCancelled: cancelled)
    }

    // MARK: - recommend(_:)

    func testWakeTimeIncludesTravelPreparationAndMargin() throws {
        let input = WakeTimeInput(firstClassStart: date(7, 8, 0),
                                  travelMinutes: 25,
                                  preparationMinutes: 40,
                                  safetyMarginMinutes: 10)
        let result = try WakeTimeCalculator.recommend(input)

        XCTAssertEqual(result.departureTime, date(7, 7, 25))
        XCTAssertEqual(result.wakeTime, date(7, 6, 45))
        XCTAssertEqual(result.firstClassStart, date(7, 8, 0))
        XCTAssertEqual(result.totalLeadTime, 75 * 60)
    }

    func testZeroDurationsGiveWakeTimeEqualToClassStart() throws {
        let input = WakeTimeInput(firstClassStart: date(7, 8, 0),
                                  travelMinutes: 0,
                                  preparationMinutes: 0,
                                  safetyMarginMinutes: 0)
        let result = try WakeTimeCalculator.recommend(input)

        XCTAssertEqual(result.wakeTime, date(7, 8, 0))
        XCTAssertEqual(result.departureTime, date(7, 8, 0))
    }

    func testWakeTimeCanFallOnPreviousDay() throws {
        let input = WakeTimeInput(firstClassStart: date(7, 0, 30),
                                  travelMinutes: 30,
                                  preparationMinutes: 30,
                                  safetyMarginMinutes: 15)
        let result = try WakeTimeCalculator.recommend(input)

        XCTAssertEqual(result.wakeTime, date(6, 23, 15))
    }

    func testOrderingWakeBeforeDepartureBeforeClass() throws {
        let input = WakeTimeInput(firstClassStart: date(7, 9, 0),
                                  travelMinutes: 20,
                                  preparationMinutes: 30,
                                  safetyMarginMinutes: 5)
        let result = try WakeTimeCalculator.recommend(input)

        XCTAssertLessThan(result.wakeTime, result.departureTime)
        XCTAssertLessThan(result.departureTime, result.firstClassStart)
    }

    func testNegativeDurationThrows() {
        let input = WakeTimeInput(firstClassStart: date(7, 8, 0),
                                  travelTime: -60,
                                  preparationTime: 600,
                                  safetyMargin: 300)
        XCTAssertThrowsError(try WakeTimeCalculator.recommend(input)) { error in
            XCTAssertEqual(error as? WakeTimeError, .invalidDuration)
        }
    }

    func testNonFiniteDurationThrows() {
        let input = WakeTimeInput(firstClassStart: date(7, 8, 0),
                                  travelTime: 600,
                                  preparationTime: .nan,
                                  safetyMargin: 300)
        XCTAssertThrowsError(try WakeTimeCalculator.recommend(input)) { error in
            XCTAssertEqual(error as? WakeTimeError, .invalidDuration)
        }
    }

    // MARK: - firstCourseStart(in:on:calendar:)

    func testFirstCourseStartPicksEarliestCourseOfTheDay() {
        let entries = [entry(start: date(7, 10, 0)),
                       entry(start: date(7, 8, 0)),
                       entry(start: date(7, 14, 0))]

        XCTAssertEqual(WakeTimeCalculator.firstCourseStart(in: entries, on: date(7, 6, 0), calendar: calendar),
                       date(7, 8, 0))
    }

    func testFirstCourseStartIgnoresCancelledCourses() {
        let entries = [entry(start: date(7, 8, 0), cancelled: true),
                       entry(start: date(7, 10, 0))]

        XCTAssertEqual(WakeTimeCalculator.firstCourseStart(in: entries, on: date(7, 6, 0), calendar: calendar),
                       date(7, 10, 0))
    }

    func testFirstCourseStartIgnoresOtherDays() {
        let entries = [entry(start: date(6, 8, 0)),
                       entry(start: date(8, 8, 0))]

        XCTAssertNil(WakeTimeCalculator.firstCourseStart(in: entries, on: date(7, 6, 0), calendar: calendar))
    }

    // MARK: - recommend(for:entries:...)

    func testRecommendForDayUsesFirstNonCancelledCourse() throws {
        let entries = [entry(start: date(7, 8, 0), cancelled: true),
                       entry(start: date(7, 9, 0))]

        let result = try WakeTimeCalculator.recommend(for: date(7, 6, 0),
                                                      entries: entries,
                                                      travelTime: 20 * 60,
                                                      preparationTime: 30 * 60,
                                                      safetyMargin: 10 * 60,
                                                      calendar: calendar)

        XCTAssertEqual(result.firstClassStart, date(7, 9, 0))
        XCTAssertEqual(result.wakeTime, date(7, 8, 0))
    }

    func testRecommendForDayThrowsWhenNoCourse() {
        XCTAssertThrowsError(try WakeTimeCalculator.recommend(for: date(7, 6, 0),
                                                              entries: [],
                                                              travelTime: 600,
                                                              preparationTime: 600,
                                                              safetyMargin: 600,
                                                              calendar: calendar)) { error in
            XCTAssertEqual(error as? WakeTimeError, .noCourse)
        }
    }
}