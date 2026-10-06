import XCTest
@testable import WakeSchool

final class SmartAlarmDemoTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
        return calendar.date(from: components)!
    }

    func testInputUsesGivenDayAtEightWithDemoDurations() throws {
        let input = try SmartAlarmDemo.input(for: date(7, 15, 42), calendar: calendar)

        XCTAssertEqual(input.firstClassStart, date(7, 8, 0))
        XCTAssertEqual(input.travelTime, 25 * 60)
        XCTAssertEqual(input.preparationTime, 40 * 60)
        XCTAssertEqual(input.safetyMargin, 10 * 60)
    }

    func testRecommendationMatchesWakeTimeCalculator() throws {
        let day = date(7, 15, 42)
        let recommendation = try SmartAlarmDemo.recommendation(for: day, calendar: calendar).get()
        let expected = try WakeTimeCalculator.recommend(try SmartAlarmDemo.input(for: day, calendar: calendar))

        XCTAssertEqual(recommendation, expected)
        XCTAssertEqual(recommendation.firstClassStart, date(7, 8, 0))
        XCTAssertEqual(recommendation.departureTime, date(7, 7, 25))
        XCTAssertEqual(recommendation.wakeTime, date(7, 6, 45))
    }
}