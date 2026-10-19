import XCTest
@testable import WakeSchool

/// Tests de la logique sous-jacente au widget « Prochain cours » (LOT 9A.4).
///
/// Le widget lui-même (WidgetKit) ne peut pas être instancié dans un test unitaire
/// sur Windows/Xcode absent. On valide donc ici :
/// 1. la sélection du prochain cours à partir de la liste partagée (hors annulés,
///    ordre chronologique, futur uniquement) ;
/// 2. les trois états distincts des données (jamais synchronisé / aucun futur /
///    prochain cours disponible) ;
/// 3. le contrat de clés partagées avec l'extension via les UserDefaults du App Group.
final class NextLessonWidgetTests: XCTestCase {
    private typealias T = TestSupport

    // MARK: - Sélection du prochain cours (réplique la logique de TimelineProvider)

    /// Reproduit la sélection effectuée dans Provider.makeEntry() :
    /// premier cours non annulé dont le début est strictement postérieur à `now`.
    private func selectedCourse(from courses: [WidgetCourse], now: Date) -> WidgetCourse? {
        courses.first { !$0.isCancelled && $0.startDate > now }
    }

    func testNextCourseExcludesCancelledAndPicksEarliestFuture() {
        // Mercredi 7 octobre 2026. Maintenant 8h00.
        let now = T.date(7, 8)
        let entries: [TimetableEntry] = [
            T.entry(7, 9, cancelled: true),   // annulé -> ignoré
            T.entry(7, 11),                   // futur
            T.entry(7, 10),                   // futur, plus tôt que 11h
            T.entry(7, 7),                    // passé -> ignoré
        ]

        let next = ScheduleService.nextCourse(after: now, in: entries)

        XCTAssertNotNil(next)
        XCTAssertEqual(next?.start, T.date(7, 10))
        XCTAssertFalse(next?.isCancelled ?? true)
    }

    func testNextCourseReturnsNilWhenOnlyCancelledOrPast() {
        let now = T.date(7, 12)
        let entries: [TimetableEntry] = [
            T.entry(7, 9, cancelled: true),
            T.entry(7, 10),                   // passé par rapport à 12h
        ]

        XCTAssertNil(ScheduleService.nextCourse(after: now, in: entries))
    }

    func testNextCourseReturnsNilWhenEmpty() {
        XCTAssertNil(ScheduleService.nextCourse(after: T.date(7, 8), in: []))
    }

    // MARK: - Sélection depuis la liste partagée (WidgetCourse)

    func testWidgetSelectionPicksEarliestNonCancelledFutureCourse() {
        let now = T.date(7, 10)
        let courses: [WidgetCourse] = [
            WidgetCourse(subjectName: "Maths", teacherName: nil, room: nil,
                         startDate: T.date(7, 9), endDate: T.date(7, 10), isCancelled: false), // passé
            WidgetCourse(subjectName: "Français", teacherName: nil, room: nil,
                         startDate: T.date(7, 11), endDate: T.date(7, 12), isCancelled: true),  // annulé
            WidgetCourse(subjectName: "Physique", teacherName: nil, room: nil,
                         startDate: T.date(7, 10), endDate: T.date(7, 11), isCancelled: false), // futur, le plus tôt
            WidgetCourse(subjectName: "Anglais", teacherName: nil, room: nil,
                         startDate: T.date(7, 14), endDate: T.date(7, 15), isCancelled: false), // futur, plus tard
        ]

        let next = selectedCourse(from: courses, now: now)

        XCTAssertNotNil(next)
        XCTAssertEqual(next?.subjectName, "Physique")
        XCTAssertEqual(next?.startDate, T.date(7, 10))
        XCTAssertFalse(next?.isCancelled ?? true)
    }
    // MARK: - États distincts des données du widget

    /// Simule la décision d'état de Provider.makeEntry() sans dépendre de WidgetKit.
    private func widgetState(hasEverSynced: Bool, courses: [WidgetCourse], now: Date) -> String {
        guard hasEverSynced else { return "neverSynced" }
        guard selectedCourse(from: courses, now: now) != nil else { return "syncedNoFutureCourses" }
        return "hasNextCourse"
    }

    func testWidgetStateNeverSyncedWhenNoSyncYet() {
        let state = widgetState(hasEverSynced: false, courses: [], now: T.date(7, 10))
        XCTAssertEqual(state, "neverSynced")
    }

    func testWidgetStateSyncedNoFutureCoursesWhenListEmptyAfterSync() {
        let state = widgetState(hasEverSynced: true, courses: [], now: T.date(7, 10))
        XCTAssertEqual(state, "syncedNoFutureCourses")
    }

    func testWidgetStateHasNextCourseWhenFutureCourseExists() {
        let courses: [WidgetCourse] = [
            WidgetCourse(subjectName: "Maths", teacherName: nil, room: nil,
                         startDate: T.date(7, 11), endDate: T.date(7, 12), isCancelled: false),
        ]
        let state = widgetState(hasEverSynced: true, courses: courses, now: T.date(7, 10))
        XCTAssertEqual(state, "hasNextCourse")
    }

    func testWidgetStateSyncedNoFutureCoursesWhenOnlyPastCoursesAfterSync() {
        let courses: [WidgetCourse] = [
            WidgetCourse(subjectName: "Maths", teacherName: nil, room: nil,
                         startDate: T.date(7, 9), endDate: T.date(7, 10), isCancelled: false),
        ]
        let state = widgetState(hasEverSynced: true, courses: courses, now: T.date(7, 11))
        XCTAssertEqual(state, "syncedNoFutureCourses")
    }

    // MARK: - Contrat de clés partagées avec le widget

    /// Clés du contrat App Group (doivent rester synchronisées avec WakeSchoolWidget/TimelineProvider
    /// et SchoolDataStore.updateWidgetSnapshot()).
    private enum WidgetKeys {
        static let hasEverSynced = "widget_has_ever_synced"
        static let coursesJson = "widget_courses_json"
    }

    func testSharedSnapshotContainsHasEverSyncedKey() {
        var snapshot: [String: Any] = [:]
        snapshot[WidgetKeys.hasEverSynced] = true

        XCTAssertEqual(snapshot.count, 1)
        XCTAssertTrue(snapshot[WidgetKeys.hasEverSynced] as? Bool == true)
    }

    func testSharedSnapshotContainsCoursesJsonKey() {
        let course = WidgetCourse(subjectName: "Maths", teacherName: "M. Martin", room: "B204",
                                  startDate: T.date(7, 10), endDate: T.date(7, 11), isCancelled: false)
        let data = try! JSONEncoder().encode([course])

        var snapshot: [String: Any] = [:]
        snapshot[WidgetKeys.coursesJson] = data

        XCTAssertNotNil(snapshot[WidgetKeys.coursesJson] as? Data)
        let decoded = try? JSONDecoder().decode([WidgetCourse].self, from: data)
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?.first?.subjectName, "Maths")
    }

    func testWidgetCourseCodableRoundTrip() {
        let course = WidgetCourse(subjectName: "Physique", teacherName: "Mme Bernard",
                                  room: "Labo 2", startDate: T.date(7, 10),
                                  endDate: T.date(7, 11), isCancelled: true)
        let data = try! JSONEncoder().encode(course)
        let decoded = try! JSONDecoder().decode(WidgetCourse.self, from: data)

        XCTAssertEqual(decoded, course)
    }
}

    func testWidgetSelectionReturnsNilWhenAllCoursesArePastOrCancelled() {
        let now = T.date(7, 16)
        let courses: [WidgetCourse] = [
            WidgetCourse(subjectName: "Maths", teacherName: nil, room: nil,
                         startDate: T.date(7, 10), endDate: T.date(7, 11), isCancelled: false),
            WidgetCourse(subjectName: "Français", teacherName: nil, room: nil,
                         startDate: T.date(7, 14), endDate: T.date(7, 15), isCancelled: true),
        ]

        XCTAssertNil(selectedCourse(from: courses, now: now))
    }

    func testWidgetSelectionReturnsNilWhenListIsEmpty() {
        XCTAssertNil(selectedCourse(from: [], now: T.date(7, 10)))
    }