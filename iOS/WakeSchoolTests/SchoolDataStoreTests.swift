import XCTest
@testable import WakeSchool

@MainActor
final class SchoolDataStoreTests: XCTestCase {
    private typealias T = TestSupport

    private func makePreferences() -> PreferencesStore {
        PreferencesStore(defaults: UserDefaults(suiteName: "WakeSchoolStoreTests-\(UUID().uuidString)")!)
    }

    private func makeEnvironment(provider: SchoolDataProvider,
                                 repository: SchoolRepository? = nil) throws -> AppEnvironment {
        let repo: SchoolRepository
        if let repository = repository {
            repo = repository
        } else {
            repo = SwiftDataSchoolRepository(container: try SwiftDataSchoolRepository.makeContainer(inMemory: true))
        }
        return AppEnvironment(preferences: makePreferences(),
                              secrets: InMemorySecretStore(),
                              repository: repo,
                              provider: provider)
    }

    private var demo: DemoSchoolDataProvider {
        DemoSchoolDataProvider(referenceDate: T.date(7, 8), calendar: T.calendar)
    }

    func testStartLoadsAndSyncsDemoData() async throws {
        let store = SchoolDataStore(environment: try makeEnvironment(provider: demo))
        XCTAssertEqual(store.snapshot, .empty)

        await store.start()

        XCTAssertFalse(store.snapshot.timetable.isEmpty)
        XCTAssertFalse(store.snapshot.homework.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertNotNil(store.lastSync)
        XCTAssertFalse(store.isSyncing)
    }

    func testHomeworkDoneStateIsPersistedAndSurvivesSync() async throws {
        let store = SchoolDataStore(environment: try makeEnvironment(provider: demo))
        await store.start()
        let target = try XCTUnwrap(store.snapshot.homework.first { !$0.isDone })

        store.setHomework(target.id, done: true)
        XCTAssertEqual(store.snapshot.homework.first { $0.id == target.id }?.isDone, true)

        await store.refresh()
        XCTAssertEqual(store.snapshot.homework.first { $0.id == target.id }?.isDone, true)
    }

    func testHomeworkCanBeUnchecked() async throws {
        let store = SchoolDataStore(environment: try makeEnvironment(provider: demo))
        await store.start()
        let target = try XCTUnwrap(store.snapshot.homework.first { !$0.isDone })

        store.setHomework(target.id, done: true)
        store.setHomework(target.id, done: false)
        XCTAssertEqual(store.snapshot.homework.first { $0.id == target.id }?.isDone, false)
    }

    func testFailedSyncKeepsCachedDataAndReportsError() async throws {
        let repository = SwiftDataSchoolRepository(
            container: try SwiftDataSchoolRepository.makeContainer(inMemory: true))
        try repository.save(try await demo.snapshot())

        let store = SchoolDataStore(environment: try makeEnvironment(provider: OfflineProvider(),
                                                                     repository: repository))
        await store.start()

        XCTAssertFalse(store.snapshot.timetable.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    func testStartRunsOnlyOnce() async throws {
        let store = SchoolDataStore(environment: try makeEnvironment(provider: demo))
        await store.start()
        let first = store.lastSync
        await store.start()
        XCTAssertEqual(store.lastSync, first)
    }
}

private struct OfflineProvider: SchoolDataProvider {
    func timetable() async throws -> [TimetableEntry] { throw PronoteError.notConfigured }
    func homework() async throws -> [Homework] { throw PronoteError.notConfigured }
    func grades() async throws -> [Grade] { throw PronoteError.notConfigured }
    func exams() async throws -> [Exam] { throw PronoteError.notConfigured }
    func events() async throws -> [SchoolEvent] { throw PronoteError.notConfigured }
}
