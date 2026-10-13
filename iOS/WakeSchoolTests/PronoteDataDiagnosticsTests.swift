import XCTest
@testable import WakeSchool

final class PronoteDataDiagnosticsTests: XCTestCase {
    func testErrorDiagnosticContainsOnlyStageAndCode() {
        var diagnostics = PronoteSyncDiagnostics()

        diagnostics.recordFailure(
            PronoteSessionError.pronoteError(403, "synthetic private response"),
            stage: "PageEmploiDuTemps"
        )

        XCTAssertEqual(diagnostics.errorStage, "PageEmploiDuTemps")
        XCTAssertEqual(diagnostics.errorCode, "PRONOTE_403")
        XCTAssertFalse(String(describing: diagnostics).contains("synthetic private response"))
    }

    @MainActor
    func testSyncReportsConvertedAndPersistedDatasetCounts() async throws {
        let client = DiagnosticPronoteClient()
        let provider = PronoteSchoolDataProvider(client: client)
        let repository = SwiftDataSchoolRepository(
            container: try SwiftDataSchoolRepository.makeContainer(inMemory: true)
        )
        let preferences = PreferencesStore(
            defaults: UserDefaults(suiteName: "WakeSchoolDiagnostics-\(UUID().uuidString)")!
        )
        let service = SchoolSyncService(
            provider: provider,
            repository: repository,
            preferences: preferences
        )

        let snapshot = try await service.sync()
        let diagnostics = try XCTUnwrap(service.diagnostics)

        XCTAssertTrue(diagnostics.authenticationSucceeded)
        XCTAssertTrue(diagnostics.userParametersRetrieved)
        XCTAssertTrue(diagnostics.studentResourceIdentified)
        XCTAssertTrue(diagnostics.schoolPeriodIdentified)
        XCTAssertEqual(diagnostics.timetable.rawCount, 1)
        XCTAssertEqual(diagnostics.timetable.convertedCount, 1)
        XCTAssertEqual(diagnostics.timetable.savedCount, snapshot.timetable.count)
        XCTAssertEqual(diagnostics.timetable.displayedCount, snapshot.timetable.count)
        XCTAssertEqual(diagnostics.homework.savedCount, snapshot.homework.count)
        XCTAssertEqual(diagnostics.grades.savedCount, snapshot.grades.count)
    }
}

private final class DiagnosticPronoteClient: PronoteClient, PronoteDataDiagnosticsReporting {
    private(set) var dataDiagnostics = PronoteSyncDiagnostics()

    private let subject = Subject(id: UUID(), name: "Matière synthétique")

    func resetDataDiagnostics() {
        dataDiagnostics = PronoteSyncDiagnostics(
            authenticationSucceeded: true,
            userParametersRetrieved: true,
            studentResourceIdentified: true,
            schoolPeriodIdentified: true,
            timetable: PronoteDatasetDiagnostics(
                callStatus: .succeeded,
                rawCount: 1,
                convertedCount: 1
            ),
            homework: PronoteDatasetDiagnostics(
                callStatus: .succeeded,
                rawCount: 1,
                convertedCount: 1
            ),
            grades: PronoteDatasetDiagnostics(
                callStatus: .succeeded,
                rawCount: 1,
                convertedCount: 1
            )
        )
    }

    func getTimetable() async throws -> [TimetableEntry] {
        [
            TimetableEntry(
                id: UUID(),
                subject: subject,
                start: Date(timeIntervalSince1970: 1_800_000_000),
                end: Date(timeIntervalSince1970: 1_800_003_600)
            )
        ]
    }

    func getHomework() async throws -> [Homework] {
        [
            Homework(
                id: UUID(),
                subject: subject,
                title: "Devoir synthétique",
                details: "",
                dueDate: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ]
    }

    func getGrades() async throws -> [Grade] {
        [
            Grade(
                id: UUID(),
                subject: subject,
                value: 15,
                outOf: 20,
                date: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ]
    }

    func getAttendance() async throws -> [AttendanceEvent] {
        [
            AttendanceEvent(
                id: UUID(),
                kind: .delay,
                start: Date(timeIntervalSince1970: 1_800_000_000),
                durationMinutes: 10,
                isJustified: false
            )
        ]
    }
}
