import XCTest
@testable import WakeSchool

final class DashboardServiceTests: XCTestCase {
    private typealias T = TestSupport

    private func summary(now: Date) async throws -> DashboardSummary {
        let provider = DemoSchoolDataProvider(referenceDate: T.date(7, 8), calendar: T.calendar)
        return DashboardService.summary(from: try await provider.snapshot(), now: now, calendar: T.calendar)
    }

    func testMorningBeforeFirstCourse() async throws {
        // Mercredi 8h : premiers cours du jour 9h-9h55 et 10h-10h55.
        let s = try await summary(now: T.date(7, 8))
        XCTAssertNil(s.currentCourse)
        XCTAssertEqual(s.nextCourse?.start, T.date(7, 9))
        XCTAssertEqual(s.firstCourseToday?.start, T.date(7, 9))
        XCTAssertEqual(s.lastCourseToday?.start, T.date(7, 10))
        XCTAssertEqual(s.todayCourses.count, 2)
    }

    func testWakeRecommendationUsesWakeTimeCalculator() async throws {
        let s = try await summary(now: T.date(7, 8))
        // 9h00 - (25 trajet + 10 marge) - 40 préparation = 7h45
        XCTAssertEqual(s.wake?.firstClassStart, T.date(7, 9))
        XCTAssertEqual(s.wake?.wakeTime, T.date(7, 7, 45))
    }

    func testWakeMovesToNextDayAfterLastCourseStarted() async throws {
        let s = try await summary(now: T.date(7, 12))
        XCTAssertNil(s.currentCourse)
        XCTAssertEqual(s.wake?.firstClassStart, T.date(8, 8))
    }

    func testCancelledAndModifiedCoursesAreReported() async throws {
        let s = try await summary(now: T.date(7, 8))
        XCTAssertGreaterThanOrEqual(s.cancelledUpcoming.count, 1)
        XCTAssertGreaterThanOrEqual(s.modifiedUpcoming.count, 1)
    }

    func testHomeworkExamsAndGrades() async throws {
        let s = try await summary(now: T.date(7, 8))
        XCTAssertEqual(s.overdueHomework.count, 1)
        XCTAssertGreaterThanOrEqual(s.pendingHomeworkCount, 5)
        XCTAssertFalse(s.homeworkDueSoon.isEmpty)
        XCTAssertFalse(s.upcomingExams.isEmpty)
        XCTAssertNotNil(s.generalAverage)
        XCTAssertEqual(s.recentGrades.count, 3)
    }

    func testEmptySnapshot() {
        let s = DashboardService.summary(from: .empty, now: T.date(7, 8), calendar: T.calendar)
        XCTAssertNil(s.nextCourse)
        XCTAssertNil(s.wake)
        XCTAssertNil(s.generalAverage)
        XCTAssertTrue(s.todayCourses.isEmpty)
        XCTAssertEqual(s.pendingHomeworkCount, 0)
    }
}
