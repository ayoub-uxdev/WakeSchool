import XCTest
@testable import WakeSchool

final class DateLabelsTests: XCTestCase {
    private typealias T = TestSupport
    private let calendar = TestSupport.calendar

    func testTimeAndWeekdayAreFrench() {
        XCTAssertEqual(DateLabels.time(T.date(7, 8, 5), calendar: calendar), "08:05")
        XCTAssertEqual(DateLabels.weekday(T.date(7), calendar: calendar), "mercredi")
        XCTAssertEqual(DateLabels.dayNumber(T.date(7), calendar: calendar), "7")
        XCTAssertEqual(DateLabels.dayTitle(T.date(7), calendar: calendar), "mercredi 7 octobre")
    }

    func testRelativeDay() {
        let now = T.date(7, 15)
        XCTAssertEqual(DateLabels.relativeDay(T.date(7, 8), now: now, calendar: calendar), "aujourd'hui")
        XCTAssertEqual(DateLabels.relativeDay(T.date(8, 8), now: now, calendar: calendar), "demain")
        XCTAssertEqual(DateLabels.relativeDay(T.date(6, 8), now: now, calendar: calendar), "hier")
        XCTAssertEqual(DateLabels.relativeDay(T.date(9, 8), now: now, calendar: calendar), "vendredi")
    }

    func testCapitalizedFirst() {
        XCTAssertEqual(DateLabels.capitalizedFirst("mercredi"), "Mercredi")
        XCTAssertEqual(DateLabels.capitalizedFirst(""), "")
    }
}

final class GradeLevelTests: XCTestCase {
    func testLevels() {
        XCTAssertEqual(GradeLevel(value: 18), .excellent)
        XCTAssertEqual(GradeLevel(value: 16), .excellent)
        XCTAssertEqual(GradeLevel(value: 14), .good)
        XCTAssertEqual(GradeLevel(value: 10), .average)
        XCTAssertEqual(GradeLevel(value: 9.9), .low)
    }
}

final class ScheduleDayServiceTests: XCTestCase {
    private typealias T = TestSupport
    private let calendar = TestSupport.calendar

    private func sample() -> [TimetableEntry] {
        [T.entry(12, 8), T.entry(7, 10, modified: true), T.entry(7, 8), T.entry(7, 9, cancelled: true), T.entry(8, 8)]
    }

    func testDaysAreGroupedAndSorted() {
        let days = ScheduleDayService.days(from: sample(), calendar: calendar)
        XCTAssertEqual(days.map(\.date), [T.date(7), T.date(8), T.date(12)])
        XCTAssertEqual(days[0].entries.map(\.start), [T.date(7, 8), T.date(7, 9), T.date(7, 10)])
        XCTAssertEqual(days[0].activeCount, 2)
        XCTAssertEqual(days[0].cancelledCount, 1)
        XCTAssertEqual(days[0].modifiedCount, 1)
    }

    func testNoEntriesNoDays() {
        XCTAssertTrue(ScheduleDayService.days(from: [], calendar: calendar).isEmpty)
        XCTAssertNil(ScheduleDayService.defaultDay(in: [], now: T.date(7), calendar: calendar))
    }

    func testDefaultDay() {
        let days = ScheduleDayService.days(from: sample(), calendar: calendar)
        XCTAssertEqual(ScheduleDayService.defaultDay(in: days, now: T.date(7, 15), calendar: calendar)?.date, T.date(7))
        // Jour sans cours : on prend le prochain jour de cours.
        XCTAssertEqual(ScheduleDayService.defaultDay(in: days, now: T.date(9, 10), calendar: calendar)?.date, T.date(12))
        // Après le dernier jour : le dernier jour connu.
        XCTAssertEqual(ScheduleDayService.defaultDay(in: days, now: T.date(20), calendar: calendar)?.date, T.date(12))
    }

    func testSummaryLine() {
        let day = ScheduleDayService.days(from: sample(), calendar: calendar)[0]
        XCTAssertEqual(ScheduleDayService.summaryLine(for: day, calendar: calendar),
                       "2 cours · 1 annulé · 1 modifié · 08:00 – 11:00")
    }
}

final class HomeworkOverviewServiceTests: XCTestCase {
    private typealias T = TestSupport

    func testSectionsSplitOverduePendingAndDone() {
        let now = T.date(7, 12)
        let items = [T.homework("Retard", due: T.date(6, 8)),
                     T.homework("À venir", due: T.date(9, 8)),
                     T.homework("Fait en retard", due: T.date(5, 8), done: true),
                     T.homework("Fait", due: T.date(10, 8), done: true)]
        let sections = HomeworkOverviewService.sections(from: items, now: now)

        XCTAssertEqual(sections.overdue.map(\.title), ["Retard"])
        XCTAssertEqual(sections.upcoming.map(\.title), ["À venir"])
        XCTAssertEqual(sections.done.map(\.title), ["Fait en retard", "Fait"])
        XCTAssertEqual(sections.total, 4)
        XCTAssertEqual(sections.completion, 0.5, accuracy: 0.0001)
    }

    func testEmptySections() {
        let sections = HomeworkOverviewService.sections(from: [], now: T.date(7))
        XCTAssertTrue(sections.isEmpty)
        XCTAssertEqual(sections.completion, 0)
    }
}

final class InsightServiceTests: XCTestCase {
    private typealias T = TestSupport
    private let calendar = TestSupport.calendar

    private func demoSummary(now: Date) async throws -> DashboardSummary {
        let provider = DemoSchoolDataProvider(referenceDate: T.date(7, 8), calendar: T.calendar)
        return DashboardService.summary(from: try await provider.snapshot(), now: now, calendar: calendar)
    }

    func testInsightsAreOrderedByImportance() async throws {
        let summary = try await demoSummary(now: T.date(7, 8))
        let kinds = InsightService.insights(from: summary, calendar: calendar, limit: 10).map(\.kind)
        XCTAssertEqual(kinds, [.cancelledCourse, .modifiedCourse, .overdueHomework,
                               .upcomingExam, .homeworkDueSoon, .nextCourse])
    }

    func testInsightMessages() async throws {
        let summary = try await demoSummary(now: T.date(7, 8))
        let messages = InsightService.insights(from: summary, calendar: calendar, limit: 3).map(\.message)
        XCTAssertEqual(messages[0], "Physique-Chimie est annulé demain à 09:00.")
        XCTAssertEqual(messages[1], "Mathématiques vendredi à 09:00 — Salle changée : B204 → C101.")
        XCTAssertEqual(messages[2], "1 devoir est en retard : Exercices 12 à 15.")
    }

    func testLimitIsRespected() async throws {
        let summary = try await demoSummary(now: T.date(7, 8))
        XCTAssertEqual(InsightService.insights(from: summary, calendar: calendar, limit: 2).count, 2)
    }

    func testCurrentCourseComesFirst() {
        let snapshot = SchoolSnapshot(timetable: [T.entry(7, 8)])
        let summary = DashboardService.summary(from: snapshot, now: T.date(7, 8, 30), calendar: calendar)
        XCTAssertEqual(InsightService.insights(from: summary, calendar: calendar).first?.kind, .currentCourse)
    }

    func testAllClearWhenNothingToReport() {
        let summary = DashboardService.summary(from: .empty, now: T.date(7, 8), calendar: calendar)
        XCTAssertEqual(InsightService.insights(from: summary, calendar: calendar).map(\.kind), [.allClear])
    }
}
