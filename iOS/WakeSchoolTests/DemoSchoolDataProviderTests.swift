import XCTest
@testable import WakeSchool

final class DemoSchoolDataProviderTests: XCTestCase {
    private typealias T = TestSupport
    private let now = TestSupport.date(7, 8) // mercredi

    private func provider() -> DemoSchoolDataProvider {
        DemoSchoolDataProvider(referenceDate: now, calendar: T.calendar)
    }

    func testTimetableIsRich() async throws {
        let entries = try await provider().timetable()
        let days = Set(entries.map { T.calendar.startOfDay(for: $0.start) })
        let subjects = Set(entries.map { $0.subject.id })

        XCTAssertGreaterThanOrEqual(days.count, 5)
        XCTAssertGreaterThanOrEqual(subjects.count, 5)
        XCTAssertGreaterThanOrEqual(entries.filter { $0.isCancelled }.count, 1)
        XCTAssertGreaterThanOrEqual(entries.filter { $0.isModified }.count, 1)
        XCTAssertEqual(entries.map(\.start), entries.map(\.start).sorted())
    }

    func testNoCourseOnWeekends() async throws {
        let entries = try await provider().timetable()
        for entry in entries {
            let weekday = T.calendar.component(.weekday, from: entry.start)
            XCTAssertTrue((2...6).contains(weekday))
        }
    }

    func testCancelledAndModifiedAreInTheFuture() async throws {
        let entries = try await provider().timetable()
        XCTAssertTrue(entries.filter { $0.isCancelled || $0.isModified }.allSatisfy { $0.start > now })
    }

    func testDataIsDeterministic() async throws {
        let first = try await provider().snapshot()
        let second = try await provider().snapshot()
        XCTAssertEqual(first, second)
    }

    func testSnapshotContainsEveryKindOfData() async throws {
        let snapshot = try await provider().snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.homework.count, 5)
        XCTAssertTrue(snapshot.homework.contains { $0.isDone })
        XCTAssertTrue(snapshot.homework.contains { !$0.isDone })
        XCTAssertGreaterThanOrEqual(snapshot.grades.count, 8)
        XCTAssertFalse(snapshot.averages.isEmpty)
        XCTAssertFalse(snapshot.exams.isEmpty)
        XCTAssertFalse(snapshot.events.isEmpty)
    }

    func testAveragesMatchGrades() async throws {
        let snapshot = try await provider().snapshot()
        XCTAssertEqual(snapshot.averages, AverageCalculator.subjectAverages(from: snapshot.grades))
    }
}
