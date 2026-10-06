import XCTest
@testable import WakeSchool

final class HomeworkServiceTests: XCTestCase {
    private typealias T = TestSupport
    private let now = TestSupport.date(7, 12)

    private func sample() -> [Homework] {
        [T.homework("En retard", due: T.date(6, 8)),
         T.homework("Aujourd'hui", due: T.date(7, 18), priority: .high),
         T.homework("Fait", due: T.date(8, 8), done: true),
         T.homework("Plus tard", due: T.date(20, 8), subject: T.french)]
    }

    func testPendingExcludesDoneAndIsSorted() {
        let pending = HomeworkService.pending(sample())
        XCTAssertEqual(pending.map(\.title), ["En retard", "Aujourd'hui", "Plus tard"])
        XCTAssertEqual(HomeworkService.completed(sample()).map(\.title), ["Fait"])
    }

    func testOverdue() {
        XCTAssertEqual(HomeworkService.overdue(sample(), now: now).map(\.title), ["En retard"])
    }

    func testDueSoonExcludesOverdueDoneAndFar() {
        XCTAssertEqual(HomeworkService.dueSoon(sample(), now: now, withinDays: 2).map(\.title), ["Aujourd'hui"])
    }

    func testDueOnDay() {
        let result = HomeworkService.due(on: T.date(7), in: sample(), calendar: T.calendar)
        XCTAssertEqual(result.map(\.title), ["Aujourd'hui"])
    }

    func testSameDueDateSortsByPriority() {
        let items = [T.homework("Basse", due: T.date(7, 8), priority: .low),
                     T.homework("Haute", due: T.date(7, 8), priority: .high)]
        XCTAssertEqual(HomeworkService.sorted(items).map(\.title), ["Haute", "Basse"])
    }

    func testFilterBySubject() {
        XCTAssertEqual(HomeworkService.forSubject(T.french, in: sample()).map(\.title), ["Plus tard"])
    }

    func testUpcomingExams() {
        let exams = [Exam(id: UUID(), subject: T.maths, date: T.date(3), title: "Passé"),
                     Exam(id: UUID(), subject: T.maths, date: T.date(10), title: "Bientôt"),
                     Exam(id: UUID(), subject: T.maths, date: T.date(30), title: "Loin")]
        XCTAssertEqual(ExamService.upcoming(exams, now: now, withinDays: 14).map(\.title), ["Bientôt"])
    }
}
