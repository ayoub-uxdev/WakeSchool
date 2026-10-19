import XCTest
@testable import WakeSchool

/// Provider mock pour tester le calendrier sans appel réseau réel.
final class MockSchoolDataProvider: SchoolDataProvider {
    var timetableEntries: [TimetableEntry] = []
    var timetableInRangeCallCount = 0
    var timetableInRangeResult: [TimetableEntry] = []
    var shouldThrow = false
    var throwError: Error = MockError.networkFailure

    func timetable() async throws -> [TimetableEntry] {
        if shouldThrow { throw throwError }
        return timetableEntries
    }

    func timetable(in range: ClosedRange<Date>) async throws -> [TimetableEntry] {
        timetableInRangeCallCount += 1
        if shouldThrow { throw throwError }
        return timetableInRangeResult
    }

    func homework() async throws -> [Homework] { [] }
    func grades() async throws -> [Grade] { [] }
    func exams() async throws -> [Exam] { [] }
    func events() async throws -> [SchoolEvent] { [] }
}

enum MockError: Error {
    case networkFailure
}

/// Repository mock pour tester le calendrier sans SwiftData.
final class MockSchoolRepository: SchoolRepository {
    var storedPeriods: [SchoolPeriod] = []
    var storedEntriesByPeriod: [String: [TimetableEntry]] = [:]
    var loadPeriodsCallCount = 0
    var saveTimetableCallCount = 0
    var shouldThrowOnLoadPeriods = false

    func loadSnapshot() throws -> SchoolSnapshot {
        let allEntries = storedEntriesByPeriod.values.flatMap { $0 }
        return SchoolSnapshot(timetable: ScheduleService.sorted(allEntries))
    }

    func save(_ snapshot: SchoolSnapshot) throws { }
    func setHomework(_ id: UUID, done: Bool) throws { }
    func clear() throws { }
    func loadAttendance() throws -> [AttendanceEvent] { [] }
    func saveAttendance(_ events: [AttendanceEvent]) throws { }

    func loadPeriods() throws -> [SchoolPeriod] {
        loadPeriodsCallCount += 1
        if shouldThrowOnLoadPeriods { throw MockError.networkFailure }
        return storedPeriods
    }

    func saveTimetable(_ entries: [TimetableEntry], for period: SchoolPeriod) throws {
        saveTimetableCallCount += 1
        storedEntriesByPeriod[period.id] = entries
    }

    func markPeriodComplete(_ period: SchoolPeriod, isComplete: Bool) throws { }
    func removeTimetable(for period: SchoolPeriod) throws { }
}

final class AcademicCalendarTests: XCTestCase {

    // MARK: - Helpers

    private func makeEnvironment(
        provider: SchoolDataProvider,
        repository: SchoolRepository
    ) -> AppEnvironment {
        AppEnvironment(
            preferences: PreferencesStore(),
            secrets: InMemorySecretStore(),
            repository: repository,
            provider: provider
        )
    }

    private func makeDataStore(environment: AppEnvironment) -> SchoolDataStore {
        SchoolDataStore(environment: environment)
    }

    private func makeEntry(day: Int, hour: Int, id: UUID) -> TimetableEntry {
        let start = TestSupport.date(day, hour)
        return TimetableEntry(
            id: id,
            subject: TestSupport.maths,
            start: start,
            end: start.addingTimeInterval(3600),
            isCancelled: false,
            isModified: false
        )
    }

    private func makePeriod(id: String, title: String, startDay: Int, endDay: Int) -> SchoolPeriod {
        SchoolPeriod(
            id: id,
            title: title,
            startDate: TestSupport.date(startDay),
            endDate: TestSupport.date(endDay, 23, 59),
            isTimetableComplete: false
        )
    }

    // MARK: - Navigation entre les mois

    func testNavigationBetweenMonths() throws {
        let repository = MockSchoolRepository()
        repository.storedPeriods = [
            makePeriod(id: "oct", title: "Octobre", startDay: 1, endDay: 31)
        ]
        let provider = MockSchoolDataProvider()
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.setPeriods(repository.storedPeriods)
        viewModel.visibleMonth = TestSupport.date(15)

        viewModel.nextMonth()
        let november = TestSupport.calendar.date(byAdding: .month, value: 1, to: TestSupport.date(15))!
        XCTAssertEqual(TestSupport.calendar.month(from: viewModel.visibleMonth), TestSupport.calendar.month(from: november))

        viewModel.previousMonth()
        XCTAssertEqual(TestSupport.calendar.month(from: viewModel.visibleMonth), 10)
    }

    // MARK: - Sélection d'une date

    func testSelectDateUpdatesSelectedDate() throws {
        let repository = MockSchoolRepository()
        repository.storedPeriods = [
            makePeriod(id: "oct", title: "Octobre", startDay: 1, endDay: 31)
        ]
        let provider = MockSchoolDataProvider()
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.setPeriods(repository.storedPeriods)

        let newDate = TestSupport.date(10)
        viewModel.selectDate(newDate)

        XCTAssertTrue(TestSupport.calendar.isDate(viewModel.selectedDate, inSameDayAs: newDate))
    }

    func testGoToTodaySetsSelectedDateToToday() throws {
        let repository = MockSchoolRepository()
        let provider = MockSchoolDataProvider()
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.selectDate(TestSupport.date(20))
        viewModel.goToToday()

        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertTrue(Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: today))
        XCTAssertTrue(Calendar.current.isDate(viewModel.visibleMonth, inSameDayAs: today))
    }

    // MARK: - Affichage des périodes en cache

    func testCachedPeriodIsShownWithoutNetworkCall() throws {
        let repository = MockSchoolRepository()
        let entry = makeEntry(day: 7, hour: 8, id: UUID())
        repository.storedEntriesByPeriod["oct"] = [entry]
        repository.storedPeriods = [
            makePeriod(id: "oct", title: "Octobre", startDay: 1, endDay: 31)
        ]
        let provider = MockSchoolDataProvider()
        provider.timetableInRangeResult = [entry]
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.setPeriods(repository.storedPeriods)

        try repository.saveTimetable([entry], for: repository.storedPeriods[0])

        let dateInOct = TestSupport.date(15)
        viewModel.selectDate(dateInOct)

        XCTAssertTrue(TestSupport.calendar.isDate(viewModel.selectedDate, inSameDayAs: dateInOct))
    }

    // MARK: - Chargement d'une période inconnue

    func testUnknownPeriodTriggersDownload() async throws {
        let repository = MockSchoolRepository()
        // Période connue : octobre seulement
        repository.storedPeriods = [
            makePeriod(id: "oct", title: "Octobre", startDay: 1, endDay: 31)
        ]
        let provider = MockSchoolDataProvider()
        provider.timetableInRangeResult = [makeEntry(day: 15, hour: 8, id: UUID())]
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.setPeriods(repository.storedPeriods)

        // Sélectionne une date en novembre (aucune période connue ne couvre novembre)
        let novemberDate = TestSupport.calendar.date(byAdding: .month, value: 1, to: TestSupport.date(15))!
        viewModel.selectDate(novemberDate)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Vérifie qu'un appel réseau a été effectué pour la période inconnue
        let callCount = (provider as! MockSchoolDataProvider).timetableInRangeCallCount
        XCTAssertGreaterThan(callCount, 0, "Une période inconnue doit déclencher un téléchargement")

        // Vérifie que la période a été marquée comme chargée
        let loadedPeriod = viewModel.periodStates.first { $0.value == .loaded }
        XCTAssertNotNil(loadedPeriod, "La période inconnue doit être marquée comme chargée après succès")
        XCTAssertNil(viewModel.errorMessage, "Aucune erreur ne doit être levée après un téléchargement réussi")
    }

    func testEmptyPeriodIsMarkedLoaded() async throws {
        let repository = MockSchoolRepository()
        repository.storedPeriods = []
        let provider = MockSchoolDataProvider()
        provider.timetableInRangeResult = [] // Période vide : aucun cours
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.setPeriods([])

        let date = TestSupport.date(15)
        viewModel.selectDate(date)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Même si vide, la période doit être marquée comme chargée
        let loadedPeriod = viewModel.periodStates.first { $0.value == .loaded }
        XCTAssertNotNil(loadedPeriod, "Une période téléchargée avec succès mais vide doit être marquée comme chargée")

        // Sélectionner la même date à nouveau ne doit pas déclencher un nouveau téléchargement
        let callCountBefore = (provider as! MockSchoolDataProvider).timetableInRangeCallCount
        viewModel.selectDate(date)
        try await Task.sleep(nanoseconds: 200_000_000)
        let callCountAfter = (provider as! MockSchoolDataProvider).timetableInRangeCallCount
        XCTAssertEqual(callCountAfter, callCountBefore, "Une période vide déjà chargée ne doit pas être retéléchargée")
    }

    // MARK: - Gestion d'une erreur réseau

    func testNetworkErrorIsReported() async throws {
        let repository = MockSchoolRepository()
        repository.storedPeriods = [
            makePeriod(id: "oct", title: "Octobre", startDay: 1, endDay: 31)
        ]
        let provider = MockSchoolDataProvider()
        provider.shouldThrow = true
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.setPeriods(repository.storedPeriods)

        let dateInOct = TestSupport.date(15)
        viewModel.selectDate(dateInOct)

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.periodStates["oct"], .failed(MockError.networkFailure))
    }

    // MARK: - Absence de requêtes inutiles

    func testNoDuplicateNetworkCallForSamePeriod() async throws {
        let repository = MockSchoolRepository()
        repository.storedPeriods = [
            makePeriod(id: "oct", title: "Octobre", startDay: 1, endDay: 31)
        ]
        let provider = MockSchoolDataProvider()
        provider.timetableInRangeResult = [makeEntry(day: 7, hour: 8, id: UUID())]
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.setPeriods(repository.storedPeriods)

        let dateInOct = TestSupport.date(15)
        viewModel.selectDate(dateInOct)

        try await Task.sleep(nanoseconds: 300_000_000)

        let firstCallCount = (provider as! MockSchoolDataProvider).timetableInRangeCallCount
        XCTAssertGreaterThan(firstCallCount, 0, "Une première récupération devrait avoir lieu")

        viewModel.selectDate(TestSupport.date(20))
        try await Task.sleep(nanoseconds: 200_000_000)

        let secondCallCount = (provider as! MockSchoolDataProvider).timetableInRangeCallCount
        XCTAssertEqual(secondCallCount, firstCallCount, "Aucun appel réseau supplémentaire pour une période déjà chargée")
    }

    // MARK: - Conservation des données précédemment téléchargées

    func testPreviouslyDownloadedCoursesArePreserved() throws {
        let repository = MockSchoolRepository()
        let entryOct = makeEntry(day: 10, hour: 8, id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let entryNov = makeEntry(day: 15, hour: 9, id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

        repository.storedPeriods = [
            makePeriod(id: "oct", title: "Octobre", startDay: 1, endDay: 31),
            makePeriod(id: "nov", title: "Novembre", startDay: 1, endDay: 30)
        ]
        repository.storedEntriesByPeriod["oct"] = [entryOct]
        repository.storedEntriesByPeriod["nov"] = [entryNov]

        let provider = MockSchoolDataProvider()
        let env = makeEnvironment(provider: provider, repository: repository)
        let dataStore = makeDataStore(environment: env)
        let viewModel = AcademicCalendarViewModel(dataStore: dataStore, syncService: env.sync)

        viewModel.setPeriods(repository.storedPeriods)

        try repository.saveTimetable([entryOct], for: repository.storedPeriods[0])
        try repository.saveTimetable([entryNov], for: repository.storedPeriods[1])

        let snapshot = try repository.loadSnapshot()
        XCTAssertEqual(snapshot.timetable.count, 2)
        XCTAssertTrue(snapshot.timetable.contains { $0.id == entryOct.id })
        XCTAssertTrue(snapshot.timetable.contains { $0.id == entryNov.id })

        viewModel.selectDate(TestSupport.date(10))
        XCTAssertTrue(viewModel.coursesForSelectedDate.contains { $0.id == entryOct.id })

        viewModel.selectDate(TestSupport.date(15))
        XCTAssertTrue(viewModel.coursesForSelectedDate.contains { $0.id == entryNov.id })
    }
}

// MARK: - Calendar convenience for tests

private extension Calendar {
    func month(from date: Date) -> Int {
        self.component(.month, from: date)
    }
}
