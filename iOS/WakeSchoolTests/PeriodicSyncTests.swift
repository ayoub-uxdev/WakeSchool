import XCTest
import SwiftData
@testable import WakeSchool

/// Tests du LOT 9A.1 : chargement progressif et fusion ciblÃ©e des pÃ©riodes scolaires.
@MainActor
final class PeriodicSyncTests: XCTestCase {
    private typealias T = TestSupport

    private func makeRepository() throws -> SwiftDataSchoolRepository {
        try SwiftDataSchoolRepository(container: SwiftDataSchoolRepository.makeContainer(inMemory: true))
    }

    private var period1: SchoolPeriod {
        SchoolPeriod(id: "P1", title: "Semaine 1", startDate: T.date(5), endDate: T.date(11, 23, 59), isTimetableComplete: false)
    }

    private var period2: SchoolPeriod {
        SchoolPeriod(id: "P2", title: "Semaine 2", startDate: T.date(12), endDate: T.date(18, 23, 59), isTimetableComplete: false)
    }

    private func entriesPeriod1() -> [TimetableEntry] {
        [T.entry(5, 8, subject: T.maths), T.entry(5, 10, subject: T.french), T.entry(7, 14, subject: T.maths, cancelled: true)]
    }

    private func entriesPeriod2() -> [TimetableEntry] {
        [T.entry(12, 8, subject: T.maths), T.entry(12, 10, subject: T.french, modified: true), T.entry(14, 14, subject: T.maths)]
    }

    private func entriesOverlap() -> [TimetableEntry] {
        [T.entry(11, 9, subject: T.maths), T.entry(12, 9, subject: T.french)]
    }

    private final class StubProvider: SchoolDataProvider {
        var timetableEntries: [TimetableEntry] = []
        var shouldThrow = false
        func timetable() async throws -> [TimetableEntry] { if shouldThrow { throw URLError(.notConnectedToInternet) }; return timetableEntries }
        func timetable(in range: ClosedRange<Date>) async throws -> [TimetableEntry] { if shouldThrow { throw URLError(.notConnectedToInternet) }; return timetableEntries.filter { range.contains($0.start) } }
        func homework() async throws -> [Homework] { [] }
        func grades() async throws -> [Grade] { [] }
        func exams() async throws -> [Exam] { [] }
        func events() async throws -> [SchoolEvent] { [] }
    }

    private func makeSyncService(provider: SchoolDataProvider, repository: SchoolRepository) -> SchoolSyncService {
        SchoolSyncService(provider: provider, repository: repository, preferences: PreferencesStore(defaults: UserDefaults(suiteName: "WakeSchoolTests-\(UUID().uuidString)")!))
    }

    // MARK: - 1. Fusion de deux pÃ©riodes distinctes

    func testMergeTwoDistinctPeriods() async throws {
        let repository = try makeRepository()
        let provider = StubProvider()
        provider.timetableEntries = entriesPeriod1() + entriesPeriod2()
        let sync = makeSyncService(provider: provider, repository: repository)

        try sync.syncTimetable(for: period1)
        var loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 3, "PÃ©riode 1 : 3 cours attendus")

        try sync.syncTimetable(for: period2)
        loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 6, "Deux pÃ©riodes : 6 cours au total")
        XCTAssertEqual(try repository.loadPeriods().count, 2, "Deux pÃ©riodes enregistrÃ©es")
    }

    // MARK: - 2. Actualisation d'une pÃ©riode dÃ©jÃ  enregistrÃ©e

    func testRefreshExistingPeriod() async throws {
        let repository = try makeRepository()
        let provider = StubProvider()
        provider.timetableEntries = entriesPeriod1()
        let sync = makeSyncService(provider: provider, repository: repository)

        try sync.syncTimetable(for: period1)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 3)

        let updated = entriesPeriod1().map { entry in
            var e = entry
            if entry.isCancelled { e.isCancelled = false }
            return e
        }
        provider.timetableEntries = updated
        try sync.syncTimetable(for: period1)

        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 3, "Toujours 3 cours aprÃ¨s actualisation (pas de duplication)")
        XCTAssertEqual(loaded.timetable.filter { $0.isCancelled }.count, 0, "Le cours prÃ©cÃ©demment annulÃ© est maintenant actif")
    }

    // MARK: - 3. PÃ©riodes chevauchantes (pas de doublons)

    func testOverlappingPeriodsNoDuplicates() async throws {
        let repository = try makeRepository()
        let provider = StubProvider()
        provider.timetableEntries = entriesPeriod1() + entriesOverlap()
        let sync = makeSyncService(provider: provider, repository: repository)

        try sync.syncTimetable(for: period1)
        try sync.syncTimetable(for: period2)

        let loaded = try repository.loadSnapshot()
        let ids = loaded.timetable.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "Aucun doublon d'ID entre pÃ©riodes chevauchantes")
    }

    // MARK: - 4. Ã‰chec de synchronisation

    func testFailedSyncKeepsCachedData() async throws {
        let repository = try makeRepository()
        let provider = StubProvider()
        provider.timetableEntries = entriesPeriod1()
        let sync = makeSyncService(provider: provider, repository: repository)

        try sync.syncTimetable(for: period1)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 3)

        provider.shouldThrow = true
        do {
            try sync.syncTimetable(for: period2)
            XCTFail("Une erreur aurait dÃ» Ãªtre levÃ©e")
        } catch { }

        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 3, "Les donnÃ©es en cache survivent Ã  l'Ã©chec")
    }

    func testHomeworkDoneStatePreservedDuringPeriodSync() throws {
        let repository = try makeRepository()
        let id = UUID()
        let due = T.date(10, 10)
        try repository.save(SchoolSnapshot(homework: [
            Homework(id: id, subject: T.maths, title: "Exercices", details: "", dueDate: due, isDone: false, priority: .normal)
        ]))
        try repository.setHomework(id, done: true)
        let provider = StubProvider()
        provider.timetableEntries = entriesPeriod1()
        let sync = makeSyncService(provider: provider, repository: repository)
        try sync.syncTimetable(for: period1)
        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.homework.first { $0.id == id }?.isDone, true)
    }

    func testNonFetchedPeriodsAreNotDeleted() async throws {
        let repository = try makeRepository()
        let provider = StubProvider()
        provider.timetableEntries = entriesPeriod1()
        let sync = makeSyncService(provider: provider, repository: repository)
        try sync.syncTimetable(for: period1)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 3)
        provider.timetableEntries = entriesPeriod2()
        try sync.syncTimetable(for: period2)
        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 6)
        let p1Courses = loaded.timetable.filter { $0.start <= period1.endDate }
        XCTAssertEqual(p1Courses.count, 3)
        let periods = try repository.loadPeriods()
        let p1 = periods.first { $0.id == "P1" }
        XCTAssertNotNil(p1)
        XCTAssertTrue(p1?.isTimetableComplete == true)
    }

    func testCancelledAndModifiedCoursesAreUpdated() async throws {
        let repository = try makeRepository()
        let provider = StubProvider()
        provider.timetableEntries = [T.entry(5, 8, subject: T.maths, cancelled: false, modified: false)]
        let sync = makeSyncService(provider: provider, repository: repository)
        try sync.syncTimetable(for: period1)
        provider.timetableEntries = [T.entry(5, 8, subject: T.maths, cancelled: true, modified: true)]
        try sync.syncTimetable(for: period1)
        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 1)
        XCTAssertTrue(loaded.timetable.first?.isCancelled == true)
        XCTAssertTrue(loaded.timetable.first?.isModified == true)
    }

    func testLoadPeriodsReturnsKnownPeriods() throws {
        let repository = try makeRepository()
        XCTAssertEqual(try repository.loadPeriods().count, 0)
        let provider = StubProvider()
        provider.timetableEntries = entriesPeriod1()
        let sync = makeSyncService(provider: provider, repository: repository)
        try sync.syncTimetable(for: period1)
        let periods = try repository.loadPeriods()
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods.first?.id, "P1")
        XCTAssertTrue(periods.first?.isTimetableComplete == true)
    }

    func testUnknownPeriodIsNotTreatedAsEmpty() throws {
        let repository = try makeRepository()
        XCTAssertEqual(try repository.loadPeriods().count, 0)
    }

    // MARK: - 5. Synchro partielle ne doit jamais effacer les autres pÃ©riodes

    /// `save(_:)` reÃ§oit une fenÃªtre partielle (ex. 3 semaines de novembre).
    /// Les cours d'octobre dÃ©jÃ  en cache doivent impÃ©rativement rester prÃ©sents.
    func testPartialSnapshotKeepsOtherPeriods() throws {
        let repository = try makeRepository()

        let octPeriod = SchoolPeriod(
            id: "OCT", title: "Octobre",
            startDate: T.date(1), endDate: T.date(31, 23, 59),
            isTimetableComplete: true
        )
        let octEntries = [
            TimetableEntry(id: UUID(uuidString: "11111111-1111-1111-1111-111111111101")!,
                           subject: T.maths, start: T.date(5, 8), end: T.date(5, 10)),
            TimetableEntry(id: UUID(uuidString: "11111111-1111-1111-1111-111111111102")!,
                           subject: T.french, start: T.date(10, 9), end: T.date(10, 11)),
            TimetableEntry(id: UUID(uuidString: "11111111-1111-1111-1111-111111111103")!,
                           subject: T.maths, start: T.date(15, 14), end: T.date(15, 16))
        ]
        try repository.saveTimetable(octEntries, for: octPeriod)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 3, "3 cours d'octobre en cache")

        let partialEntries = [
            TimetableEntry(id: UUID(uuidString: "22222222-2222-2222-2222-222222222201")!,
                           subject: T.maths, start: T.date(2, 8), end: T.date(2, 10)),
            TimetableEntry(id: UUID(uuidString: "22222222-2222-2222-2222-222222222202")!,
                           subject: T.french, start: T.date(3, 9), end: T.date(3, 11))
        ]
        try repository.save(SchoolSnapshot(timetable: partialEntries))

        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 5,
                       "Une synchro partielle ne doit pas supprimer les cours des autres pÃ©riodes")
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "11111111-1111-1111-1111-111111111101") })
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "11111111-1111-1111-1111-111111111103") })
    }

    /// Deux pÃ©riodes chevauchantes : un cours dans la zone de chevauchement appartient Ã  P1.
    /// Actualiser P2 ne doit ni supprimer ce cours ni le dupliquer.
    func testOverlappingPeriodsPreserveCourses() throws {
        let repository = try makeRepository()

        let p1 = SchoolPeriod(id: "P1", title: "P1", startDate: T.date(5), endDate: T.date(11, 23, 59), isTimetableComplete: false)
        let p2 = SchoolPeriod(id: "P2", title: "P2", startDate: T.date(9), endDate: T.date(15, 23, 59), isTimetableComplete: false)

        let overlapEntry = TimetableEntry(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333301")!,
            subject: T.maths, start: T.date(10, 9), end: T.date(10, 11))
        try repository.saveTimetable([overlapEntry], for: p1)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 1, "P1 : 1 cours")

        let p2Entries = [
            TimetableEntry(id: UUID(uuidString: "33333333-3333-3333-3333-333333333310")!,
                           subject: T.french, start: T.date(12, 9), end: T.date(12, 11)),
            TimetableEntry(id: UUID(uuidString: "33333333-3333-3333-3333-333333333311")!,
                           subject: T.maths, start: T.date(14, 14), end: T.date(14, 16))
        ]
        try repository.saveTimetable(p2Entries, for: p2)

        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 3,
                       "Les cours de P1 dans la zone de chevauchement doivent Ãªtre prÃ©servÃ©s")
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "33333333-3333-3333-3333-333333333301") },
                      "Le cours de chevauchement de P1 ne doit pas disparaÃ®tre")
        XCTAssertEqual(loaded.timetable.filter { Calendar(identifier: .gregorian).isDate($0.start, inSameDayAs: T.date(10)) }.count, 1,
                       "Un seul cours le 10 octobre (pas de duplication)")
    }

    /// Un cours annulÃ© ou modifiÃ© est actualisÃ© uniquement lorsque la synchro de sa
    /// pÃ©riode rÃ©ussit. En cas d'Ã©chec, le cache prÃ©cÃ©dent est intact.
    func testCancelledModifiedUpdatedOnlyOnSuccessfulPeriodSync() throws {
        let repository = try makeRepository()
        let provider = StubProvider()
        provider.shouldThrow = false
        let sync = makeSyncService(provider: provider, repository: repository)

        provider.timetableEntries = [T.entry(5, 8, subject: T.maths, cancelled: false, modified: false)]
        try sync.syncTimetable(for: period1)
        var loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 1)
        XCTAssertFalse(loaded.timetable.first?.isCancelled == true)
        XCTAssertFalse(loaded.timetable.first?.isModified == true)

        provider.timetableEntries = [T.entry(5, 8, subject: T.maths, cancelled: true, modified: true)]
        provider.shouldThrow = true
        do {
            try sync.syncTimetable(for: period1)
            XCTFail("Une erreur aurait dÃ» Ãªtre levÃ©e")
        } catch { }

        loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 1, "Le cours prÃ©cÃ©dent doit subsister aprÃ¨s un Ã©chec")
        XCTAssertFalse(loaded.timetable.first?.isCancelled == true, "Le cours ne doit pas Ãªtre marquÃ© annulÃ© aprÃ¨s un Ã©chec")
        XCTAssertFalse(loaded.timetable.first?.isModified == true, "Le cours ne doit pas Ãªtre marquÃ© modifiÃ© aprÃ¨s un Ã©chec")
    }

    /// Synchro initiale complÃ¨te â†’ synchro ciblÃ©e â†’ nouvelle synchro complÃ¨te :
    /// aucun cours ne doit Ãªtre perdu Ã  aucune Ã©tape.
    func testFullThenTargetedThenFullSyncPreservesAllCourses() throws {
        let repository = try makeRepository()

        let fullEntries = [
            TimetableEntry(id: UUID(uuidString: "44444444-4444-4444-4444-444444444401")!,
                           subject: T.maths, start: T.date(5, 8), end: T.date(5, 10)),
            TimetableEntry(id: UUID(uuidString: "44444444-4444-4444-4444-444444444402")!,
                           subject: T.french, start: T.date(12, 9), end: T.date(12, 11)),
            TimetableEntry(id: UUID(uuidString: "44444444-4444-4444-4444-444444444403")!,
                           subject: T.maths, start: T.date(18, 14), end: T.date(18, 16))
        ]
        try repository.save(SchoolSnapshot(timetable: fullEntries))
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 3, "3 cours aprÃ¨s synchro initiale")

        let targetPeriod = SchoolPeriod(id: "TGT", title: "Cible", startDate: T.date(12), endDate: T.date(12, 23, 59), isTimetableComplete: true)
        try repository.saveTimetable([
            TimetableEntry(id: UUID(uuidString: "44444444-4444-4444-4444-444444444402")!,
                           subject: T.french, start: T.date(12, 10), end: T.date(12, 12), modified: true)
        ], for: targetPeriod)
        var loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 3, "Toujours 3 cours aprÃ¨s synchro ciblÃ©e")
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "44444444-4444-4444-4444-444444444401") })
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "44444444-4444-4444-4444-444444444403") })
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "44444444-4444-4444-4444-444444444402") && $0.isModified == true })

        try repository.save(SchoolSnapshot(timetable: fullEntries))
        loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 3, "3 cours aprÃ¨s seconde synchro complÃ¨te")
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "44444444-4444-4444-4444-444444444401") })
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "44444444-4444-4444-4444-444444444402") })
        XCTAssertTrue(loaded.timetable.contains { $0.id == UUID(uuidString: "44444444-4444-4444-4444-444444444403") })
    }

    /// Distingue explicitement trois cas : pÃ©riode inconnue, pÃ©riode tÃ©lÃ©chargÃ©e vide, pÃ©riode tÃ©lÃ©chargÃ©e avec des cours.
    func testUnknownPeriodVsEmptyVsFilled() throws {
        let repository = try makeRepository()

        XCTAssertEqual(try repository.loadPeriods().count, 0, "Aucune pÃ©riode connue initialement")

        let emptyPeriod = SchoolPeriod(id: "EMPTY", title: "Vide", startDate: T.date(20), endDate: T.date(20, 23, 59), isTimetableComplete: true)
        try repository.saveTimetable([], for: emptyPeriod)
        let periods = try repository.loadPeriods()
        XCTAssertEqual(periods.count, 1, "Une pÃ©riode fetchÃ©e (mÃªme vide) est enregistrÃ©e")
        XCTAssertTrue(periods.first { $0.id == "EMPTY" }?.isTimetableComplete == true)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 0, "Aucun cours pour une pÃ©riode vide")

        let filledPeriod = SchoolPeriod(id: "FILLED", title: "Remplie", startDate: T.date(25), endDate: T.date(25, 23, 59), isTimetableComplete: true)
        try repository.saveTimetable([T.entry(25, 10, subject: T.maths)], for: filledPeriod)
        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 1, "Un cours pour la pÃ©riode remplie")
        XCTAssertEqual(try repository.loadPeriods().count, 2, "Deux pÃ©riodes connues au total")
    }

    /// Le mÃªme cours (mÃªme UUID) se retrouve dans deux pÃ©riodes chevauchantes.
    /// L'actualisation successive de chaque pÃ©riode ne doit produire ni doublon
    /// ni suppression accidentelle, et le cours finit rattachÃ© Ã  la derniÃ¨re pÃ©riode.
    func testOverlappingPeriodsSameCourseSuccessiveUpdates() throws {
        let repository = try makeRepository()

        let overlapCourse = TimetableEntry(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555501")!,
            subject: T.maths,
            start: T.date(10, 9),
            end: T.date(10, 11)
        )

        try repository.saveTimetable([overlapCourse], for: period1)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 1, "Un cours aprÃ¨s P1")

        try repository.saveTimetable([overlapCourse], for: period2)
        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 1, "Toujours un seul cours aprÃ¨s P2 (pas de doublon)")
        XCTAssertEqual(loaded.timetable.first?.id, overlapCourse.id, "Le cours conserve son ID")
        XCTAssertEqual(loaded.timetable.first?.id, overlapCourse.id, "Le cours conserve son ID")

        // Nouvelle actualisation de P1 avec un cours diffÃ©rent : le cours de chevauchement reste dans P2.
        let other = TimetableEntry(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555502")!,
            subject: T.french,
            start: T.date(6, 9),
            end: T.date(6, 11)
        )
        try repository.saveTimetable([other], for: period1)
        let loaded2 = try repository.loadSnapshot()
        XCTAssertEqual(loaded2.timetable.count, 2, "Deux cours distincts aprÃ¨s actualisation de P1")
        XCTAssertEqual(loaded2.timetable.filter { $0.id == overlapCourse.id }.count, 1, "Le cours de chevauchement est prÃ©sent")
        XCTAssertEqual(loaded2.timetable.filter { $0.id == other.id }.count, 1, "L'autre cours est prÃ©sent")
    }

    /// Une synchro ciblÃ©e rÃ©ussie remplace un ancien cours par sa version modifiÃ©e
    /// ou annulÃ©e, y compris lorsque son stableID a changÃ©.
    func testTargetedSyncReplacesCourseWhenStableIDChanges() throws {
        let repository = try makeRepository()

        let original = TimetableEntry(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666601")!,
            subject: T.maths,
            start: T.date(5, 8),
            end: T.date(5, 10),
            cancelled: false,
            modified: false
        )
        try repository.saveTimetable([original], for: period1)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 1, "Un cours initialement")

        let replacement = TimetableEntry(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666602")!,
            subject: T.maths,
            start: T.date(5, 8),
            end: T.date(5, 10),
            cancelled: true,
            modified: true
        )
        try repository.saveTimetable([replacement], for: period1)
        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 1, "Toujours un seul cours aprÃ¨s remplacement")
        XCTAssertEqual(loaded.timetable.first?.id, replacement.id, "Le nouvel ID est prÃ©sent")
        XCTAssertNotEqual(loaded.timetable.first?.id, original.id, "L'ancien ID a disparu")
        XCTAssertTrue(loaded.timetable.first?.isCancelled == true, "Le cours est annulÃ©")
        XCTAssertTrue(loaded.timetable.first?.isModified == true, "Le cours est modifiÃ©")
    }

    /// Scénario critique : un même cours A appartient à deux périodes chevauchantes.
    /// 1. P1 contient A
    /// 2. P2 contient également A (même UUID)
    /// 3. Synchro P1, puis P2
    /// 4. P2 est actualisée sans A (réponse complète ne contenant plus A)
    /// 5. P1 n'a pas été actualisée et contient toujours A dans ses dernières données valides
    /// Résultat attendu : A doit être conservé pour P1, aucun doublon dans loadSnapshot().
    func testOverlappingPeriodsCourseSurvivesPeriodRemoval() throws {
        let repository = try makeRepository()

        let courseA = TimetableEntry(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777701")!,
            subject: T.maths,
            start: T.date(10, 9),
            end: T.date(10, 11)
        )

        // 1. P1 contient A
        try repository.saveTimetable([courseA], for: period1)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 1, "P1 : un cours (A)")

        // 2. P2 contient également A (même UUID)
        try repository.saveTimetable([courseA], for: period2)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 1, "Toujours un seul cours (pas de doublon)")
        XCTAssertEqual(try repository.loadPeriods().count, 2, "Deux périodes connues")

        // 3. P2 est actualisée sans A (réponse complète ne contenant plus A)
        try repository.saveTimetable([], for: period2)
        let loaded = try repository.loadSnapshot()
        XCTAssertEqual(loaded.timetable.count, 1, "A doit subsister pour P1 après retrait de P2")
        XCTAssertEqual(loaded.timetable.first?.id, courseA.id, "Le cours survivant est bien A")

        // 4. Vérifier qu'il n'y a pas de doublon dans loadSnapshot()
        let ids = loaded.timetable.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "Aucun doublon d'ID dans le snapshot")

        // 5. P1 n'a pas été actualisée : A reste accessible
        XCTAssertEqual(loaded.timetable.filter { $0.id == courseA.id }.count, 1, "A est toujours prÃ©sent pour P1")
    }

    /// Cas inverse : un cours A disparaît de toutes les périodes qui le référencent.
    func testOverlappingPeriodsCourseDisappearsFromAllPeriods() throws {
        let repository = try makeRepository()

        let courseA = TimetableEntry(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888801")!,
            subject: T.maths,
            start: T.date(10, 9),
            end: T.date(10, 11)
        )

        try repository.saveTimetable([courseA], for: period1)
        try repository.saveTimetable([courseA], for: period2)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 1, "Un cours A partagÃ© par P1 et P2")

        // P1 est actualisée sans A : A reste via P2
        try repository.saveTimetable([], for: period1)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 1, "A subsiste encore via P2")

        // P2 est actualisée sans A : A n'a plus aucun lien, il doit disparaître
        try repository.saveTimetable([], for: period2)
        XCTAssertEqual(try repository.loadSnapshot().timetable.count, 0, "A a disparu de toutes les pÃ©riodes")
    }
}
