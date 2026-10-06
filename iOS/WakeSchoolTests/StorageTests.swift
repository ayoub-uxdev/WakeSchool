import XCTest
@testable import WakeSchool

final class StorageTests: XCTestCase {
    private typealias T = TestSupport

    private func demoSnapshot() async throws -> SchoolSnapshot {
        try await DemoSchoolDataProvider(referenceDate: T.date(7, 8), calendar: T.calendar).snapshot()
    }

    @MainActor
    private func makeRepository() throws -> SwiftDataSchoolRepository {
        SwiftDataSchoolRepository(container: try SwiftDataSchoolRepository.makeContainer(inMemory: true))
    }

    private func makePreferences() -> PreferencesStore {
        PreferencesStore(defaults: UserDefaults(suiteName: "WakeSchoolTests-\(UUID().uuidString)")!)
    }

    // MARK: - SwiftData

    @MainActor
    func testSaveThenLoadRoundTrip() async throws {
        let repository = try makeRepository()
        let snapshot = try await demoSnapshot()
        try repository.save(snapshot)
        let loaded = try repository.loadSnapshot()

        XCTAssertEqual(Set(loaded.timetable), Set(snapshot.timetable))
        XCTAssertEqual(Set(loaded.homework), Set(snapshot.homework))
        XCTAssertEqual(Set(loaded.grades), Set(snapshot.grades))
        XCTAssertEqual(Set(loaded.averages), Set(snapshot.averages))
        XCTAssertEqual(Set(loaded.exams), Set(snapshot.exams))
        XCTAssertEqual(Set(loaded.events), Set(snapshot.events))
    }

    @MainActor
    func testSaveTwiceDoesNotDuplicate() async throws {
        let repository = try makeRepository()
        let snapshot = try await demoSnapshot()
        try repository.save(snapshot)
        try repository.save(snapshot)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, snapshot.timetable.count)
    }

    @MainActor
    func testLocalHomeworkDoneStateSurvivesResync() async throws {
        let repository = try makeRepository()
        let snapshot = try await demoSnapshot()
        let target = try XCTUnwrap(snapshot.homework.first { !$0.isDone })
        try repository.save(snapshot)
        try repository.setHomework(target.id, done: true)
        try repository.save(snapshot) // le provider dit toujours « non terminé »

        let reloaded = try repository.loadSnapshot().homework.first { $0.id == target.id }
        XCTAssertEqual(reloaded?.isDone, true)
    }

    @MainActor
    func testClear() async throws {
        let repository = try makeRepository()
        try repository.save(try await demoSnapshot())
        try repository.clear()
        XCTAssertEqual(try repository.loadSnapshot(), .empty)
    }

    // MARK: - Sync

    @MainActor
    func testSyncPersistsAndRecordsDate() async throws {
        let repository = try makeRepository()
        let preferences = makePreferences()
        let provider = DemoSchoolDataProvider(referenceDate: T.date(7, 8), calendar: T.calendar)
        let service = SchoolSyncService(provider: provider, repository: repository,
                                        preferences: preferences, now: { T.date(7, 8) })
        XCTAssertEqual(try service.loadCached(), .empty)

        let synced = try await service.sync()
        XCTAssertFalse(synced.timetable.isEmpty)
        XCTAssertEqual(preferences.lastSyncDate, T.date(7, 8))
        XCTAssertEqual(try service.loadCached().timetable.count, synced.timetable.count)
    }

    @MainActor
    func testFailedSyncKeepsCacheAndLastSyncDate() async throws {
        let repository = try makeRepository()
        let preferences = makePreferences()
        let good = SchoolSyncService(provider: DemoSchoolDataProvider(referenceDate: T.date(7, 8), calendar: T.calendar),
                                     repository: repository, preferences: preferences, now: { T.date(7, 8) })
        try await good.sync()

        let failing = SchoolSyncService(provider: FailingProvider(), repository: repository,
                                        preferences: preferences, now: { T.date(9, 8) })
        do {
            try await failing.sync()
            XCTFail("La synchronisation aurait dû échouer.")
        } catch {
            XCTAssertEqual(error as? PronoteError, .notImplemented)
        }
        XCTAssertFalse(try failing.loadCached().timetable.isEmpty)
        XCTAssertEqual(preferences.lastSyncDate, T.date(7, 8))
    }

    func testPronoteProviderPropagatesUnavailableClient() async {
        let provider = PronoteSchoolDataProvider(client: UnavailablePronoteClient())
        do {
            _ = try await provider.snapshot()
            XCTFail("Aurait dû échouer.")
        } catch {
            XCTAssertEqual(error as? PronoteError, .notImplemented)
        }
    }

    // MARK: - Préférences et secrets

    func testPreferencesDefaultsAndPersistence() {
        let preferences = makePreferences()
        XCTAssertEqual(preferences.dataSource, .demo)
        XCTAssertEqual(preferences.wakeSettings, .default)
        XCTAssertNil(preferences.lastSyncDate)

        preferences.dataSource = .pronote
        preferences.wakeSettings = WakeSettings(travelMinutes: 15, preparationMinutes: 30, safetyMarginMinutes: 5)
        XCTAssertEqual(preferences.dataSource, .pronote)
        XCTAssertEqual(preferences.wakeSettings.travelMinutes, 15)
    }

    func testCredentialsRoundTripThroughSecretStore() throws {
        let store = CredentialsStore(store: InMemorySecretStore())
        XCTAssertNil(try store.load())

        let credentials = PronoteCredentials(serverURL: "https://exemple.invalid", username: "eleve", password: "secret")
        try store.save(credentials)
        XCTAssertEqual(try store.load(), credentials)

        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testCredentialsDescriptionHidesPassword() {
        let credentials = PronoteCredentials(serverURL: "https://exemple.invalid", username: "eleve", password: "secret")
        XCTAssertFalse("\(credentials)".contains("secret"))
    }
}

private struct FailingProvider: SchoolDataProvider {
    func timetable() async throws -> [TimetableEntry] { throw PronoteError.notImplemented }
    func homework() async throws -> [Homework] { throw PronoteError.notImplemented }
    func grades() async throws -> [Grade] { throw PronoteError.notImplemented }
    func exams() async throws -> [Exam] { throw PronoteError.notImplemented }
    func events() async throws -> [SchoolEvent] { throw PronoteError.notImplemented }
}
