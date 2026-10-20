import XCTest
import UserNotifications
@testable import WakeSchool

/// Faux scheduler de notifications : enregistre les planifications sans UIKit réel.
final class MockNotificationScheduler: NotificationScheduling {
    var status: UNAuthorizationStatus = .notDetermined
    var requestResult = true
    private(set) var scheduled: [(notification: WakeNotification, date: Date?)] = []
    private(set) var cancelledIDs: [String] = []

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> Bool {
        if status == .notDetermined { status = requestResult ? .authorized : .denied }
        return requestResult
    }

    func schedule(_ notification: WakeNotification, at fireDate: Date?) async throws {
        scheduled.append((notification, fireDate))
    }

    func cancel(ids: [String]) { cancelledIDs.append(contentsOf: ids) }

    func pendingIDs() async -> [String] { scheduled.map { $0.notification.id } }

    func clearDelivered() async {}

    var lastWakeConfirmation: WakeNotification? {
        scheduled.last(where: { $0.notification.id.hasPrefix("wake.confirm") })?.notification
    }
}

final class NotificationTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        return calendar.date(from: c)!
    }

    private func makePlan(startHour: Int = 8, wakeHour: Int = 6, wakeMinute: Int = 45, day: Int = 17) -> AutoWakePlan {
        let subject = Subject(id: UUID(), name: "Mathématiques")
        let course = TimetableEntry(id: UUID(), subject: subject, teacher: nil, room: nil,
                                    start: date(day, startHour, 0),
                                    end: date(day, startHour + 1, 0))
        let recommendation = WakeTimeRecommendation(wakeTime: date(day, wakeHour, wakeMinute),
                                                    departureTime: date(day, 7, 0),
                                                    firstClassStart: course.start)
        return AutoWakePlan(targetDay: calendar.startOfDay(for: date(day, 0, 0)),
                            firstCourse: course,
                            recommendation: recommendation,
                            isCustom: false)
    }

    private let settings = WakeSettings(travelMinutes: 20, preparationMinutes: 30, safetyMarginMinutes: 10)

    // MARK: - Confirmation quotidienne

    func testConfirmationNextSendDateIsTodayAt21OrTomorrow() throws {
        let now = date(16, 20, 0)
        let send = try XCTUnwrap(WakeConfirmationService.nextSendDate(minutesFromMidnight: 21 * 60, now: now, calendar: calendar))
        XCTAssertEqual(send, date(16, 21, 0))

        let later = date(16, 21, 30)
        let next = try XCTUnwrap(WakeConfirmationService.nextSendDate(minutesFromMidnight: 21 * 60, now: later, calendar: calendar))
        XCTAssertEqual(next, date(17, 21, 0))
    }

    func testConfirmationSkippedWhenNoCourse() {
        let settings = WakeConfirmationSettings(isEnabled: true, confirmationTimeMinutes: 21 * 60)
        XCTAssertFalse(WakeConfirmationService.shouldSend(plan: nil, settings: settings, lastSync: Date(), now: Date()))
    }

    func testConfirmationSkippedWhenDisabled() {
        let settings = WakeConfirmationSettings(isEnabled: false, confirmationTimeMinutes: 21 * 60)
        XCTAssertFalse(WakeConfirmationService.shouldSend(plan: makePlan(), settings: settings, lastSync: Date(), now: Date()))
    }

    func testConfirmationSkippedWhenSyncTooOld() {
        let settings = WakeConfirmationSettings(isEnabled: true, confirmationTimeMinutes: 21 * 60)
        let old = Date().addingTimeInterval(-48 * 3600)
        XCTAssertFalse(WakeConfirmationService.shouldSend(plan: makePlan(), settings: settings, lastSync: old, now: Date()))
    }

    func testConfirmationSentWhenAllConditionsMet() {
        let settings = WakeConfirmationSettings(isEnabled: true, confirmationTimeMinutes: 21 * 60)
        XCTAssertTrue(WakeConfirmationService.shouldSend(plan: makePlan(), settings: settings, lastSync: Date(), now: Date()))
    }

    func testConfirmationMessageContainsCourseAndWakeTimes() {
        let plan = makePlan(startHour: 8, wakeHour: 6, wakeMinute: 45)
        let now = date(16, 20, 0)
        let message = WakeConfirmationService.message(plan: plan, now: now, calendar: calendar)
        XCTAssertTrue(message.body.contains("8h00"), "Le message doit contenir l'heure du premier cours.")
        XCTAssertTrue(message.body.contains("6h45"), "Le message doit contenir l'heure du réveil.")
    }

    func testConfirmationNotificationIDIsStablePerTargetDay() {
        let plan1 = makePlan(day: 17)
        let plan2 = makePlan(day: 17)
        XCTAssertEqual(WakeConfirmationService.notification(plan: plan1, now: Date(), calendar: calendar)?.id,
                       WakeConfirmationService.notification(plan: plan2, now: Date(), calendar: calendar)?.id)
        let plan3 = makePlan(day: 18)
        XCTAssertNotEqual(WakeConfirmationService.notification(plan: plan1, now: Date(), calendar: calendar)?.id,
                          WakeConfirmationService.notification(plan: plan3, now: Date(), calendar: calendar)?.id)
    }

    // MARK: - Détection de nouveautés

    private func grade(_ value: Double, id: UUID = UUID(), subjectName: String = "Maths") -> Grade {
        Grade(id: id, subject: Subject(id: stableSubjectID(subjectName), name: subjectName), value: value, outOf: 20, date: Date())
    }

    private func stableSubjectID(_ name: String) -> UUID {
        UUID()
    }

    func testNewGradeDetectedVersusAlreadyKnown() {
        let knownID = UUID()
        let knownGrade = grade(12, id: knownID)
        let newGrade = grade(15)
        let oldSnapshot = SchoolSnapshot(grades: [knownGrade])
        let newSnapshot = SchoolSnapshot(grades: [knownGrade, newGrade])

        let changes = ChangeDetectionService.detect(
            previousKnownGradeIDs: ChangeDetectionService.gradeIDs(in: oldSnapshot),
            previousKnownExamIDs: [],
            newSnapshot: newSnapshot)

        XCTAssertEqual(changes.newGrades.count, 1)
        XCTAssertEqual(changes.newGrades.first?.id, newGrade.id)
    }

    func testKnownGradeIsNeverReDetected() {
        let knownGrade = grade(12)
        let snapshot = SchoolSnapshot(grades: [knownGrade])
        let changes = ChangeDetectionService.detect(
            previousKnownGradeIDs: ChangeDetectionService.gradeIDs(in: snapshot),
            previousKnownExamIDs: [],
            newSnapshot: snapshot)
        XCTAssertTrue(changes.isEmpty, "Une note déjà connue ne doit pas être re-signalée à chaque synchronisation.")
    }

    func testAbsentGradeIsDetectedLikeNumericOne() {
        let absent = Grade(id: UUID(), subject: Subject(id: UUID(), name: "Histoire"), status: .absent, outOf: 20, date: Date())
        let changes = ChangeDetectionService.detect(previousKnownGradeIDs: [], previousKnownExamIDs: [],
                                                    newSnapshot: SchoolSnapshot(grades: [absent]))
        XCTAssertEqual(changes.newGrades.count, 1, "Une ABS a un id stable et peut être signalée comme évaluation publiée.")
    }

    func testNewExamDetected() {
        let exam = Exam(id: UUID(), subject: Subject(id: UUID(), name: "Physique"), date: Date(), title: "DS")
        let changes = ChangeDetectionService.detect(previousKnownGradeIDs: [], previousKnownExamIDs: [],
                                                    newSnapshot: SchoolSnapshot(exams: [exam]))
        XCTAssertEqual(changes.newExams.count, 1)
    }

    // MARK: - Règles

    func testDisabledRuleProducesNoNotification() {
        let rules = [NotificationRule.default(for: .newGrade)] // désactivée par défaut
        let changes = ChangeDetectionService.Changes(newGrades: [grade(15)])
        let notifications = NotificationRuleService.notifications(for: rules, changes: changes)
        XCTAssertTrue(notifications.isEmpty, "Une règle désactivée ne produit aucune notification.")
    }

    func testEnabledNewGradeRuleProducesNotificationPerGrade() {
        var rule = NotificationRule.default(for: .newGrade)
        rule.isEnabled = true
        let changes = ChangeDetectionService.Changes(newGrades: [grade(15), grade(10, subjectName: "Histoire")])
        let notifications = NotificationRuleService.notifications(for: rulesWith([rule]), changes: changes)
        XCTAssertEqual(notifications.count, 2)
        // Identifiants stables et distincts par note.
        XCTAssertNotEqual(notifications[0].id, notifications[1].id)
    }

    func testGradeRuleDoesNotRepeatOnNextSync() {
        var rule = NotificationRule.default(for: .newGrade)
        rule.isEnabled = true
        let newGrade = grade(15)
        let changes = ChangeDetectionService.Changes(newGrades: [newGrade])
        let first = NotificationRuleService.notifications(for: rulesWith([rule]), changes: changes)
        // Deuxième synchronisation sans nouveauté : aucun doublon.
        let second = NotificationRuleService.notifications(for: rulesWith([rule]), changes: .init())
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
    }

    func testHomeworkDueTomorrowMessage() throws {
        let calendar = self.calendar
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date(16, 0, 0)))!
        let dueHomework = Homework(id: UUID(), subject: Subject(id: UUID(), name: "Maths"),
                                   title: "Exercices 1 à 5", details: "", dueDate: tomorrow)
        let laterHomework = Homework(id: UUID(), subject: Subject(id: UUID(), name: "Anglais"),
                                     title: "Essay", details: "", dueDate: calendar.date(byAdding: .day, value: 5, to: tomorrow)!)
        let message = try XCTUnwrap(NotificationRuleService.homeworkDueTomorrowMessage(
            homework: [dueHomework, laterHomework], now: date(16, 19, 0), calendar: calendar))
        XCTAssertTrue(message.body.contains("Maths"))
        XCTAssertFalse(message.body.contains("Anglais"))
    }

    func testHomeworkDueTomorrowReturnsNilWhenNothingDue() {
        let calendar = self.calendar
        let laterHomework = Homework(id: UUID(), subject: Subject(id: UUID(), name: "Anglais"),
                                     title: "Essay", details: "",
                                     dueDate: calendar.date(byAdding: .day, value: 5, to: date(16, 0, 0))!)
        XCTAssertNil(NotificationRuleService.homeworkDueTomorrowMessage(homework: [laterHomework], now: date(16, 19, 0), calendar: calendar))
    }

    // MARK: - Notification refusée / autorisations

    func testDeniedAuthorizationProducesNoScheduling() async {
        let scheduler = MockNotificationScheduler()
        scheduler.status = .denied
        let defaults = UserDefaults(suiteName: "NotificationTests-\(UUID().uuidString)")!
        let preferences = PreferencesStore(defaults: defaults)
        let orchestrator = (scheduler: scheduler,
                                                    center: NotificationCenterStore(defaults: defaults),
                                                    rules: NotificationRulesStore(defaults: defaults),
                                                    preferences: preferences)
        let result = await orchestrator.sendTestNotification()
        XCTAssertTrue(scheduler.scheduled.isEmpty, "Aucune notification planifiée si refusée.")
        XCTAssertTrue(result.lowercased().contains("désactiv") || result.lowercased().contains("refus"),
                      "L'UI doit expliquer pourquoi la notification n'apparaît pas.")
    }

    func testAuthorizedTestNotificationIsScheduled() async {
        let scheduler = MockNotificationScheduler()
        scheduler.status = .authorized
        let defaults = UserDefaults(suiteName: "NotificationTests-\(UUID().uuidString)")!
        let orchestrator = (scheduler: scheduler,
                                                    center: NotificationCenterStore(defaults: defaults),
                                                    rules: NotificationRulesStore(defaults: defaults),
                                                    preferences: PreferencesStore(defaults: defaults))
        _ = await orchestrator.sendTestNotification()
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled.first?.notification.id, "wake.test")
    }

    func testProcessAfterSyncPlansConfirmationWithStableID() async throws {
        let scheduler = MockNotificationScheduler()
        scheduler.status = .authorized
        let defaults = UserDefaults(suiteName: "NotificationTests-\(UUID().uuidString)")!
        let preferences = PreferencesStore(defaults: defaults)
        preferences.lastSyncDate = Date()
        let orchestrator = (scheduler: scheduler,
                                                    center: NotificationCenterStore(defaults: defaults),
                                                    rules: NotificationRulesStore(defaults: defaults),
                                                    preferences: preferences)

        let entries: [TimetableEntry] = [TimetableEntry(
            id: UUID(),
            subject: Subject(id: UUID(), name: "Maths"),
            teacher: nil, room: nil,
            start: date(17, 8, 0), end: date(17, 9, 0))]

        await orchestrator.processAfterSync(entries: entries,
                                            periods: nil,
                                            snapshot: SchoolSnapshot(timetable: entries),
                                            knownGradeIDs: [], knownExamIDs: [],
                                            wakeAlarmEnabled: false,
                                            wakeConfirmation: WakeConfirmationSettings(isEnabled: true, confirmationTimeMinutes: 21 * 60))

        let confirmation = try XCTUnwrap(scheduler.lastWakeConfirmation)
        XCTAssertTrue(confirmation.id.hasPrefix("wake.confirm."))
        // Re-process immédiat (nouvelle sync) : même identifiant → remplacement, pas de doublon.
        await orchestrator.processAfterSync(entries: entries,
                                            periods: nil,
                                            snapshot: SchoolSnapshot(timetable: entries),
                                            knownGradeIDs: [], knownExamIDs: [],
                                            wakeAlarmEnabled: false,
                                            wakeConfirmation: WakeConfirmationSettings(isEnabled: true, confirmationTimeMinutes: 21 * 60))
        let confirmations = scheduler.scheduled.filter { $0.notification.id.hasPrefix("wake.confirm.") }
        XCTAssertEqual(Set(confirmations.map { $0.notification.id }).count, confirmations.count, "Un seul identifiant par jour visé.")
    }

    func testNoConfirmationWhenSyncTooOldInOrchestrator() async {
        let scheduler = MockNotificationScheduler()
        scheduler.status = .authorized
        let defaults = UserDefaults(suiteName: "NotificationTests-\(UUID().uuidString)")!
        let preferences = PreferencesStore(defaults: defaults)
        preferences.lastSyncDate = Date().addingTimeInterval(-48 * 3600)
        let orchestrator = (scheduler: scheduler,
                                                    center: NotificationCenterStore(defaults: defaults),
                                                    rules: NotificationRulesStore(defaults: defaults),
                                                    preferences: preferences)
        let entries: [TimetableEntry] = [
            TimetableEntry(
                id: UUID(), subject: Subject(id: UUID(), name: "Maths"), teacher: nil, room: nil,
                start: date(17, 8, 0), end: date(17, 9, 0))
        ]
        await orchestrator.processAfterSync(entries: entries,
                                            periods: nil,
                                            snapshot: SchoolSnapshot(timetable: entries),
                                            knownGradeIDs: [], knownExamIDs: [],
                                            wakeAlarmEnabled: false,
                                            wakeConfirmation: WakeConfirmationSettings(isEnabled: true, confirmationTimeMinutes: 21 * 60))
        XCTAssertNil(scheduler.lastWakeConfirmation, "Aucune confirmation si la synchronisation est trop ancienne.")
    }

    // MARK: - Fuseau horaire / clé de jour

    func testDayKeyIsDateBasedNotTimeBased() {
        let morning = date(17, 6, 0)
        let evening = date(17, 23, 30)
        XCTAssertEqual(WakeNotification.dayKey(morning, calendar: calendar),
                       WakeNotification.dayKey(evening, calendar: calendar))
        let nextDay = date(18, 6, 0)
        XCTAssertNotEqual(WakeNotification.dayKey(morning, calendar: calendar),
                          WakeNotification.dayKey(nextDay, calendar: calendar))
    }

    // MARK: - Baseline de détection (première synchronisation) — LOT 8 consolidation

    /// La baseline PERSISTANTE détermine le premier lancement, pas un ensemble vide :
    /// un utilisateur sans note reçoit ensuite sa première note normalement.
    func testFirstGradeAfterEmptyBaselineIsDetected() {
        // 1re sync (baseline établie) : aucune note.
        let emptyBaseline = ChangeDetectionService.detect(previousKnownGradeIDs: [],
                                                          previousKnownExamIDs: [],
                                                          newSnapshot: SchoolSnapshot())
        XCTAssertTrue(emptyBaseline.isEmpty, "Aucune note au départ = aucune fausse alerte.")

        // 2e sync : la première note arrive → détectée exactement une fois.
        let firstGrade = grade(15)
        let changes = ChangeDetectionService.detect(previousKnownGradeIDs: [],
                                                    previousKnownExamIDs: [],
                                                    newSnapshot: SchoolSnapshot(grades: [firstGrade]))
        XCTAssertEqual(changes.newGrades.count, 1)
        XCTAssertEqual(changes.newGrades.first?.id, firstGrade.id)
    }

    private func rulesWith(_ list: [NotificationRule]) -> [NotificationRule] {
        list
    }
}
