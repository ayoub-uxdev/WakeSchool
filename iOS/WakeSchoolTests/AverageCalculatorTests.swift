import XCTest
@testable import WakeSchool

final class AverageCalculatorTests: XCTestCase {
    private typealias T = TestSupport

    func testWeightedAverageUsesCoefficients() throws {
        let value = try XCTUnwrap(AverageCalculator.weightedAverage(of: [T.grade(10), T.grade(15, coef: 2)]))
        XCTAssertEqual(value, 40.0 / 3.0, accuracy: 0.0001)
    }

    func testGradesAreNormalizedToTwenty() throws {
        let value = try XCTUnwrap(AverageCalculator.weightedAverage(of: [T.grade(8, 10)]))
        XCTAssertEqual(value, 16, accuracy: 0.0001)
    }

    func testInvalidGradesAreIgnored() throws {
        let value = try XCTUnwrap(AverageCalculator.weightedAverage(of: [T.grade(10), T.grade(5, 0), T.grade(20, coef: 0)]))
        XCTAssertEqual(value, 10, accuracy: 0.0001)
        XCTAssertNil(AverageCalculator.weightedAverage(of: [T.grade(5, 0)]))
        XCTAssertNil(AverageCalculator.weightedAverage(of: []))
    }

    func testSubjectAveragesGroupBySubject() {
        let grades = [T.grade(10, subject: T.maths), T.grade(14, subject: T.maths), T.grade(12, subject: T.french)]
        let averages = AverageCalculator.subjectAverages(from: grades)
        XCTAssertEqual(averages.count, 2)
        XCTAssertEqual(averages.first { $0.subject.id == T.maths.id }?.average ?? 0, 12, accuracy: 0.0001)
    }

    func testGeneralAverage() throws {
        let averages = [SubjectAverage(subject: T.maths, average: 10),
                        SubjectAverage(subject: T.french, average: 16)]
        XCTAssertEqual(try XCTUnwrap(AverageCalculator.generalAverage(of: averages)), 13, accuracy: 0.0001)
        XCTAssertNil(AverageCalculator.generalAverage(of: []))
    }

    func testRecentGradesAreNewestFirst() {
        let grades = [T.grade(10, day: 1), T.grade(11, day: 5), T.grade(12, day: 3)]
        XCTAssertEqual(AverageCalculator.recentGrades(grades, limit: 2).map(\.value), [11, 12])
    }
}
