import XCTest
import SwiftData
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

    // MARK: - Évaluations non numériques (ABS…) — LOT 8

    /// Une note ABS survive au round-trip SwiftData : statut conservé,
    /// jamais converti en zéro ni en valeur numérique.
    @MainActor
    func testAbsentGradeSurvivesStorageRoundTrip() throws {
        let repository = try makeRepository()
        let absent = Grade(id: UUID(), subject: T.maths, status: .absent, outOf: 20,
                           coefficient: 1, date: T.date(5, 10), title: "DS")
        let numeric = Grade(id: UUID(), subject: T.maths, value: 12, outOf: 20,
                            coefficient: 1, date: T.date(6, 10), title: "Interro")
        let snapshot = SchoolSnapshot(grades: [absent, numeric])

        try repository.save(snapshot)
        let loaded = try repository.loadSnapshot().grades

        XCTAssertEqual(loaded.count, 2)
        let loadedAbsent = try XCTUnwrap(loaded.first { !$0.isNumeric })
        XCTAssertEqual(loadedAbsent.value, .status(.absent))
        XCTAssertEqual(loadedAbsent.displayValue, "ABS")
        XCTAssertNil(loadedAbsent.numericValue, "Une ABS ne doit jamais devenir 0 après persistance.")
        XCTAssertTrue(loaded.first { $0.isNumeric }?.numericValue == 12)
    }

    /// Compatibilité LOT 7 : une ligne du NOUVEAU schéma dont `statusRaw` vaut
    /// nil (l'état lu par SwiftData pour les lignes créées avant l'ajout de
    /// l'attribut, après lightweight migration) doit se relire comme note
    /// numérique.
    ///
    /// ATTENTION : ce test valide la lecture d'une valeur nil, PAS la migration
    /// réelle d'un ancien schéma SwiftData vers le nouveau sur un store disque
    /// existant. Celle-ci nécessite un essai sur une installation IPA LOT 7
    /// avec des notes déjà enregistrées (cf. risques à valider sur iPhone).
    @MainActor
    func testLegacyGradeWithoutStatusRawStillLoadsAsNumeric() throws {
        let container = try SwiftDataSchoolRepository.makeContainer(inMemory: true)
        let directContext = ModelContext(container)

        let legacy = Grade(id: UUID(), subject: T.maths, value: 14, outOf: 20,
                           coefficient: 2, date: T.date(3, 10), title: "DS LOT 7")
        let stored = StoredGrade(legacy)
        directContext.insert(stored)
        stored.statusRaw = nil // état exact d'une ligne créée par l'IPA LOT 7
        try directContext.save()

        let repository = SwiftDataSchoolRepository(container: container)
        let loaded = try repository.loadSnapshot().grades

        XCTAssertEqual(loaded.count, 1)
        let reloaded = try XCTUnwrap(loaded.first)
        XCTAssertTrue(reloaded.isNumeric, "Une note de l'IPA LOT 7 doit rester numérique après migration.")
        XCTAssertEqual(reloaded.numericValue, 14)
        XCTAssertNotEqual(reloaded.value, .status(.absent))
        XCTAssertEqual(reloaded.outOf, 20)
        XCTAssertEqual(reloaded.coefficient, 2)
    }

    /// Round-trip COMPLET d'une note ABS : réponse PRONOTE → mapper → Grade →
    /// StoredGrade (repository) → relecture. Elle doit rester ABS, jamais 0,
    /// et être exclue de la moyenne après persistance.
    @MainActor
    func testAbsentGradeFullRoundTripFromPronoteResponseToRepository() throws {
        // 1. Réponse PRONOTE avec une note ABS et une note numérique.
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "listeDevoirs": [
                        "V": [
                            [
                                "N": "grade-abs",
                                "note": ["V": "ABS"],
                                "bareme": ["V": "20"],
                                "date": ["V": "09/10/2026"],
                                "service": ["V": ["N": "subject-1", "L": "Histoire"]]
                            ],
                            [
                                "N": "grade-num",
                                "note": ["V": "16"],
                                "bareme": ["V": "20"],
                                "date": ["V": "10/10/2026"],
                                "service": ["V": ["N": "subject-1", "L": "Histoire"]]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let mapped = PronoteMapper.gradeMapping(from: response).grades
        XCTAssertEqual(mapped.count, 2)

        // 2. Persistance via le repository (chemin réel de SchoolSyncService).
        let repository = try makeRepository()
        try repository.save(SchoolSnapshot(grades: mapped))

        // 3. Relecture après « redémarrage » (nouvelle lecture du store).
        let loaded = try repository.loadSnapshot().grades
        let absentAfterStorage = try XCTUnwrap(loaded.first { !$0.isNumeric })
        XCTAssertEqual(absentAfterStorage.value, .status(.absent), "L'ABS doit rester ABS après le round-trip complet.")
        XCTAssertEqual(absentAfterStorage.displayValue, "ABS")
        XCTAssertNil(absentAfterStorage.numericValue)

        // 4. L'ABS ne doit jamais entrer dans une moyenne.
        let averages = AverageCalculator.subjectAverages(from: loaded)
        XCTAssertEqual(averages.count, 1)
        XCTAssertEqual(try XCTUnwrap(averages.first).average, 16, accuracy: 0.0001,
                       "La moyenne ne doit compter que la note numérique (16), pas l'ABS comme 0.")
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
    func testHomeworkAttachmentsSurviveStorageRoundTripAndDoneState() async throws {
        let repository = try makeRepository()
        var snapshot = try await demoSnapshot()
        let attachment = HomeworkAttachment(
            protocolID: "synthetic-file",
            name: "worksheet.pdf",
            kind: .file,
            linkURL: nil
        )
        snapshot.homework[0].attachments = [attachment]
        try repository.save(snapshot)
        try repository.setHomework(snapshot.homework[0].id, done: true)

        let reloaded = try XCTUnwrap(
            repository.loadSnapshot().homework.first { $0.id == snapshot.homework[0].id }
        )
        XCTAssertEqual(reloaded.attachments, [attachment])
        XCTAssertTrue(reloaded.isDone)
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
