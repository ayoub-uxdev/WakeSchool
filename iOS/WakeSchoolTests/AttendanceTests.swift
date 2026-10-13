import XCTest
@testable import WakeSchool

/// Tests LOT 7 — absences et retards.
///
/// Le contrat PRONOTE est celui confirmé via pronotepy : RPC « PagePresence »
/// (onglet 19), liste mixte `listeAbsences.V` filtrée par `G`
/// (13 = absence, 14 = retard).
final class AttendanceTests: XCTestCase {
    private typealias T = TestSupport

    /// Date construite dans le fuseau courant : PronoteJSON analyse les dates
    /// PRONOTE (« dd/MM/yyyy HH:mm:ss ») avec `TimeZone.current`.
    private func localDate(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Réponse PagePresence synthétique

    private func presenceResponse(items: [[String: Any]]) -> [String: Any] {
        [
            "dataSec": [
                "data": [
                    "listeAbsences": ["V": items]
                ]
            ]
        ]
    }

    private func absenceItem(id: String = "abs-1",
                             start: String = "05/10/2026 08:00:00",
                             end: String = "05/10/2026 10:00:00",
                             hours: String = "2",
                             justified: Bool = true,
                             motifs: [String] = ["Rendez-vous médical"]) -> [String: Any] {
        var item: [String: Any] = [
            "N": id,
            "G": 13,
            "dateDebut": ["_T": 7, "V": start],
            "dateFin": ["_T": 7, "V": end],
            "justifie": justified,
            "NbrHeures": hours
        ]
        if !motifs.isEmpty {
            item["listeMotifs"] = ["V": motifs.map { ["L": $0] }]
        }
        return item
    }

    private func delayItem(id: String = "ret-1",
                           date: String = "06/10/2026 08:15:00",
                           minutes: Int = 15,
                           justified: Bool = false,
                           justification: String? = nil) -> [String: Any] {
        var item: [String: Any] = [
            "N": id,
            "G": 14,
            "date": ["_T": 7, "V": date],
            "duree": minutes,
            "justifie": justified
        ]
        if let justification {
            item["justification"] = justification
        }
        return item
    }

    // MARK: - Mapping

    @MainActor
    func testMapsAbsenceWithConfirmedFields() throws {
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [absenceItem()]))
        XCTAssertEqual(events.count, 1)

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.kind, .absence)
        XCTAssertEqual(event.start, localDate(5, 8))
        XCTAssertEqual(event.end, localDate(5, 10))
        XCTAssertEqual(event.durationMinutes, 120)
        XCTAssertTrue(event.isJustified)
        XCTAssertEqual(event.reasons, ["Rendez-vous médical"])
        XCTAssertNil(event.justification)
    }

    @MainActor
    func testMapsDelayWithConfirmedFields() throws {
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [delayItem(justified: true, justification: "Bus en retard")]))
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.kind, .delay)
        XCTAssertEqual(event.start, localDate(6, 8, 15))
        XCTAssertNil(event.end)
        XCTAssertEqual(event.durationMinutes, 15)
        XCTAssertTrue(event.isJustified)
        XCTAssertEqual(event.justification, "Bus en retard")
    }

    @MainActor
    func testMixedListIsSeparatedByKindCode() throws {
        let items = [absenceItem(id: "a1"), delayItem(id: "d1"), absenceItem(id: "a2", justified: false)]
        let events = try PronoteMapper.attendance(from: presenceResponse(items: items))
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.filter { $0.kind == .absence }.count, 2)
        XCTAssertEqual(events.filter { $0.kind == .delay }.count, 1)
    }

    @MainActor
    func testOtherKindCodesAreIgnored() throws {
        // G = 41 (punition dans pronotepy) ne doit pas devenir une absence.
        var punishment = absenceItem(id: "p1")
        punishment["G"] = 41
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [punishment]))
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testMissingFieldsAreToleratedWithoutInvention() throws {
        // Item minimal : date seule. La durée ne doit PAS être inventée.
        let minimal: [String: Any] = [
            "N": "abs-min",
            "G": 13,
            "dateDebut": ["_T": 7, "V": "05/10/2026 08:00:00"]
        ]
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [minimal]))
        let event = try XCTUnwrap(events.first)
        XCTAssertNil(event.end)
        XCTAssertNil(event.durationMinutes)
        XCTAssertFalse(event.isJustified)
        XCTAssertTrue(event.reasons.isEmpty)
    }

    @MainActor
    func testMissingDateIsRejected() throws {
        let item: [String: Any] = ["N": "abs-bad", "G": 13, "justifie": true]
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [item]))
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Dates et durées

    @MainActor
    func testAbsenceDurationFallsBackToDates() throws {
        // Pas de NbrHeures : durée calculée depuis dateDebut/dateFin (90 min).
        let item = absenceItem(id: "a-h",
                               start: "05/10/2026 08:00:00",
                               end: "05/10/2026 09:30:00",
                               hours: "")
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [item]))
        XCTAssertEqual(try XCTUnwrap(events.first).durationMinutes, 90)
    }

    @MainActor
    func testHourDurationParsing() throws {
        // Test indirect via le mapping d'une absence « 1,5 h ».
        let item = absenceItem(id: "a-f", hours: "1,5",
                               start: "05/10/2026 08:00:00",
                               end: "05/10/2026 09:30:00")
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [item]))
        XCTAssertEqual(try XCTUnwrap(events.first).durationMinutes, 90)
    }

    @MainActor
    func testMissingListeAbsencesThrowsInsteadOfReturningEmpty() {
        // Réponse sans listeAbsences : invalide, pas « zéro évènement ».
        XCTAssertThrowsError(try PronoteMapper.attendance(from: [:])) {
            guard case PronoteMapperError.invalidResponse = $0 else {
                return XCTFail("Erreur inattendue : \($0)")
            }
        }

        // listeAbsences mal formée (ni tableau ni enveloppe V) : idem.
        let malformed: [String: Any] = ["dataSec": ["data": ["listeAbsences": "corrompu"]]]
        XCTAssertThrowsError(try PronoteMapper.attendance(from: malformed))
    }

    @MainActor
    func testMalformedPresenceResponseKeepsCachedAttendance() async throws {
        let repository = try makeRepository()
        let attendance = [
            AttendanceEvent(id: UUID(), kind: .absence, start: T.date(5, 8),
                            end: T.date(5, 10), durationMinutes: 120, isJustified: false)
        ]
        try repository.saveAttendance(attendance)

        // Provider renvoyant une réponse PagePresence sans listeAbsences.
        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "WakeSchoolTests-\(UUID().uuidString)")!)
        let service = SchoolSyncService(
            provider: MalformedAttendanceProvider(),
            repository: repository,
            preferences: preferences,
            now: { T.date(7, 8) }
        )

        // La synchronisation doit échouer : l'assertion est en dehors du do/catch.
        var didThrow = false
        do {
            _ = try await service.syncAttendance()
        } catch {
            didThrow = true
        }
        XCTAssertTrue(didThrow, "La synchronisation aurait dû échouer sur une réponse invalide.")

        // Le cache précédent est intégralement conservé.
        XCTAssertEqual(try repository.loadAttendance(), attendance)
    }

    // MARK: - Identifiants stables et déduplication

    @MainActor
    func testIdentifiersAreStableAcrossCalls() throws {
        let response = presenceResponse(items: [absenceItem(), delayItem()])
        let first = try PronoteMapper.attendance(from: response)
        let second = try PronoteMapper.attendance(from: response)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    @MainActor
    func testDuplicatesAreRemoved() throws {
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [absenceItem(), absenceItem()]))
        XCTAssertEqual(events.count, 1)
    }

    @MainActor
    func testEventsAreSortedNewestFirst() throws {
        let events = try PronoteMapper.attendance(from: presenceResponse(items: [
            absenceItem(id: "old", start: "01/10/2026 08:00:00", end: "01/10/2026 09:00:00"),
            absenceItem(id: "new", start: "10/10/2026 08:00:00", end: "10/10/2026 09:00:00")
        ]))
        XCTAssertEqual(events.first?.start, localDate(10, 8))
    }

    // MARK: - Persistance (SwiftData)

    @MainActor
    private func makeRepository() throws -> SwiftDataSchoolRepository {
        SwiftDataSchoolRepository(container: try SwiftDataSchoolRepository.makeContainer(inMemory: true))
    }

    @MainActor
    func testAttendanceRoundTripThroughSwiftData() throws {
        let repository = try makeRepository()
        let event = AttendanceEvent(id: UUID(), kind: .delay,
                                    start: T.date(6, 8, 15), end: nil,
                                    durationMinutes: 15, isJustified: true,
                                    justification: "Bus", reasons: ["Transport"],
                                    subjectName: "Français")
        try repository.saveAttendance([event])

        let loaded = try repository.loadAttendance()
        XCTAssertEqual(loaded, [event])
    }

    @MainActor
    func testSaveAttendanceReplacesWithoutDuplicates() throws {
        let repository = try makeRepository()
        let events = [
            AttendanceEvent(id: UUID(), kind: .absence, start: T.date(5, 8),
                            end: T.date(5, 10), durationMinutes: 120, isJustified: false),
            AttendanceEvent(id: UUID(), kind: .delay, start: T.date(6, 8, 15),
                            durationMinutes: 10, isJustified: false)
        ]
        try repository.saveAttendance(events)
        try repository.saveAttendance(events)
        XCTAssertEqual(try repository.loadAttendance().count, events.count)
    }

    @MainActor
    func testSchoolSyncDoesNotEraseAttendance() async throws {
        let repository = try makeRepository()
        let attendance = [
            AttendanceEvent(id: UUID(), kind: .absence, start: T.date(5, 8),
                            end: T.date(5, 10), durationMinutes: 120, isJustified: false)
        ]
        try repository.saveAttendance(attendance)

        // Une synchronisation scolaire complète ne touche pas à la vie scolaire.
        let provider = DemoSchoolDataProvider(referenceDate: T.date(7, 8), calendar: T.calendar)
        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "WakeSchoolTests-\(UUID().uuidString)")!)
        let service = SchoolSyncService(provider: provider, repository: repository,
                                        preferences: preferences, now: { T.date(7, 8) })
        _ = try await service.sync()

        XCTAssertEqual(try repository.loadAttendance(), attendance)
    }

    @MainActor
    func testAttendanceSyncFailureKeepsPreviousEvents() async throws {
        let repository = try makeRepository()
        let attendance = [
            AttendanceEvent(id: UUID(), kind: .delay, start: T.date(6, 8, 15),
                            durationMinutes: 10, isJustified: false)
        ]
        try repository.saveAttendance(attendance)

        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "WakeSchoolTests-\(UUID().uuidString)")!)
        let service = SchoolSyncService(
            provider: FailingAttendanceProvider(),
            repository: repository,
            preferences: preferences,
            now: { T.date(7, 8) }
        )

        // La synchronisation doit échouer : l'assertion est en dehors du do/catch.
        var didThrow = false
        do {
            _ = try await service.syncAttendance()
        } catch {
            didThrow = true
        }
        XCTAssertTrue(didThrow, "La synchronisation des absences aurait dû échouer.")

        XCTAssertEqual(try repository.loadAttendance(), attendance)
        // Le cache scolaire reste vide mais inchangé : aucune donnée corrompue.
        XCTAssertEqual(try repository.loadSnapshot(), .empty)
    }

    @MainActor
    func testAttendanceSyncIndependentlyOfSchoolSnapshot() async throws {
        let repository = try makeRepository()
        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "WakeSchoolTests-\(UUID().uuidString)")!)
        let provider = DemoSchoolDataProvider(referenceDate: T.date(7, 8), calendar: T.calendar)
        let service = SchoolSyncService(provider: provider, repository: repository,
                                        preferences: preferences, now: { T.date(7, 8) })

        // La démo fournit des absences de démonstration via le provider.
        let events = try await service.syncAttendance()
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(try repository.loadAttendance(), events)

        // Rechargement hors ligne : le cache est conservé.
        XCTAssertEqual(try service.loadCachedAttendance(), events)
    }

    // MARK: - Statistiques et filtres

    @MainActor
    func testAttendanceFilteringLogic() {
        let events = [
            AttendanceEvent(id: UUID(), kind: .absence, start: T.date(1, 8), durationMinutes: 60),
            AttendanceEvent(id: UUID(), kind: .delay, start: T.date(2, 8), durationMinutes: 10),
            AttendanceEvent(id: UUID(), kind: .absence, start: T.date(3, 8), durationMinutes: 30)
        ]

        let absences = events.filter { $0.kind == .absence }
        let delays = events.filter { $0.kind == .delay }
        XCTAssertEqual(absences.count, 2)
        XCTAssertEqual(delays.count, 1)

        let unjustified = events.filter { !$0.isJustified }.count
        XCTAssertEqual(unjustified, 3)
    }
}

/// Provider dont seule la récupération des absences échoue.
private struct FailingAttendanceProvider: SchoolDataProvider {
    func timetable() async throws -> [TimetableEntry] { [] }
    func homework() async throws -> [Homework] { [] }
    func grades() async throws -> [Grade] { [] }
    func exams() async throws -> [Exam] { [] }
    func events() async throws -> [SchoolEvent] { [] }
    func attendance() async throws -> [AttendanceEvent] { throw PronoteError.notImplemented }
}

/// Provider renvoyant une réponse PagePresence sans listeAbsences valide.
private struct MalformedAttendanceProvider: SchoolDataProvider {
    func timetable() async throws -> [TimetableEntry] { [] }
    func homework() async throws -> [Homework] { [] }
    func grades() async throws -> [Grade] { [] }
    func exams() async throws -> [Exam] { [] }
    func events() async throws -> [SchoolEvent] { [] }
    func attendance() async throws -> [AttendanceEvent] {
        try PronoteMapper.attendance(from: ["dataSec": ["data": [:]]])
    }
}
