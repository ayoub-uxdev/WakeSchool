import XCTest
@testable import WakeSchool

/// Tests unitaires pour `ExamService.upcoming`, qui alimente la section
/// « Prochains DS » / « Contrôles à venir » du tableau de bord.
final class ExamServiceTests: XCTestCase {
    private typealias T = TestSupport

    /// Les examens dans l'horizon (y compris à l'instant `now`) sont
    /// retournés triés par date croissante.
    func testUpcomingExamsWithinHorizonAreSorted() {
        let now = T.date(7, 8)
        let exams = [
            Exam(id: UUID(), subject: T.french, date: T.date(7, 15), title: "Dans 7 jours"),
            Exam(id: UUID(), subject: T.maths, date: T.date(7, 10), title: "Dans 2 jours"),
        ]
        let result = ExamService.upcoming(exams, now: now, withinDays: 14)
        XCTAssertEqual(result.map { $0.title }, ["Dans 2 jours", "Dans 7 jours"])
    }

    /// Les examens passés (date < now) sont exclus.
    func testExcludesPastExams() {
        let now = T.date(7, 8)
        let exams = [
            Exam(id: UUID(), subject: T.maths, date: T.date(7, 5), title: "Passé"),
            Exam(id: UUID(), subject: T.french, date: T.date(7, 10), title: "Futur"),
        ]
        let result = ExamService.upcoming(exams, now: now, withinDays: 14)
        XCTAssertEqual(result.map { $0.title }, ["Futur"])
    }

    /// Les examens au-delà de l'horizon sont exclus.
    func testExcludesExamsBeyondHorizon() {
        let now = T.date(7, 8)
        let exams = [
            Exam(id: UUID(), subject: T.maths, date: T.date(7, 10), title: "Dans 2 jours"),
            Exam(id: UUID(), subject: T.french, date: T.date(7, 30), title: "Dans 22 jours"),
        ]
        let result = ExamService.upcoming(exams, now: now, withinDays: 14)
        XCTAssertEqual(result.map { $0.title }, ["Dans 2 jours"])
    }

    /// Un examen dont la date est exactement `now` est inclus.
    func testIncludesExamAtNow() {
        let now = T.date(7, 8)
        let exams = [
            Exam(id: UUID(), subject: T.maths, date: now, title: "Maintenant"),
        ]
        let result = ExamService.upcoming(exams, now: now, withinDays: 14)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Maintenant")
    }

    /// Un tableau d'entrées vide retourne un tableau vide.
    func testEmptyExamsReturnsEmpty() {
        let result = ExamService.upcoming([], now: T.date(7, 8), withinDays: 14)
        XCTAssertTrue(result.isEmpty)
    }

    /// Un horizon de 0 jour ne retient que les examens à l'instant `now`.
    func testZeroDaysHorizonKeepsOnlyNow() {
        let now = T.date(7, 8)
        let exams = [
            Exam(id: UUID(), subject: T.maths, date: now, title: "Maintenant"),
            Exam(id: UUID(), subject: T.french, date: T.date(7, 9), title: "Demain"),
        ]
        let result = ExamService.upcoming(exams, now: now, withinDays: 0)
        XCTAssertEqual(result.map { $0.title }, ["Maintenant"])
    }
}
