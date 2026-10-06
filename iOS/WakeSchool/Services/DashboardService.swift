import Foundation

/// Tout ce dont le Dashboard a besoin, déjà calculé. La vue n'a qu'à afficher.
struct DashboardSummary {
    let now: Date
    let currentCourse: TimetableEntry?
    let nextCourse: TimetableEntry?
    let firstCourseToday: TimetableEntry?
    let lastCourseToday: TimetableEntry?
    /// Cours du jour, annulés inclus, triés.
    let todayCourses: [TimetableEntry]
    /// Cours annulés pas encore terminés.
    let cancelledUpcoming: [TimetableEntry]
    /// Cours modifiés pas encore terminés.
    let modifiedUpcoming: [TimetableEntry]
    let pendingHomeworkCount: Int
    let overdueHomework: [Homework]
    /// Devoirs à rendre dans les 2 jours.
    let homeworkDueSoon: [Homework]
    /// Contrôles dans les 14 jours.
    let upcomingExams: [Exam]
    let generalAverage: Double?
    let recentGrades: [Grade]
    /// Réveil recommandé pour le prochain jour de cours (calculé par `WakeTimeCalculator`).
    let wake: WakeTimeRecommendation?
}

enum DashboardService {
    static let homeworkSoonDays = 2
    static let examHorizonDays = 14
    static let recentGradesCount = 3
    /// Nombre de jours explorés pour trouver le prochain jour de cours.
    static let wakeSearchDays = 8

    static func summary(from snapshot: SchoolSnapshot,
                        now: Date,
                        settings: WakeSettings = .default,
                        calendar: Calendar = .current) -> DashboardSummary {
        let timetable = snapshot.timetable
        let isUpcoming: (TimetableEntry) -> Bool = { $0.end > now }

        return DashboardSummary(
            now: now,
            currentCourse: ScheduleService.currentCourse(at: now, in: timetable),
            nextCourse: ScheduleService.nextCourse(after: now, in: timetable),
            firstCourseToday: ScheduleService.firstCourse(on: now, in: timetable, calendar: calendar),
            lastCourseToday: ScheduleService.lastCourse(on: now, in: timetable, calendar: calendar),
            todayCourses: ScheduleService.entries(on: now, in: timetable,
                                                  includeCancelled: true, calendar: calendar),
            cancelledUpcoming: ScheduleService.cancelled(timetable).filter(isUpcoming),
            modifiedUpcoming: ScheduleService.modified(timetable).filter(isUpcoming),
            pendingHomeworkCount: HomeworkService.pending(snapshot.homework).count,
            overdueHomework: HomeworkService.overdue(snapshot.homework, now: now),
            homeworkDueSoon: HomeworkService.dueSoon(snapshot.homework, now: now,
                                                     withinDays: homeworkSoonDays),
            upcomingExams: ExamService.upcoming(snapshot.exams, now: now, withinDays: examHorizonDays),
            generalAverage: AverageCalculator.generalAverage(of: snapshot.averages),
            recentGrades: AverageCalculator.recentGrades(snapshot.grades, limit: recentGradesCount),
            wake: nextWake(entries: timetable, now: now, settings: settings, calendar: calendar)
        )
    }

    /// Premier jour (aujourd'hui inclus) dont le premier cours est encore à venir,
    /// puis délégation à `WakeTimeCalculator`.
    static func nextWake(entries: [TimetableEntry],
                         now: Date,
                         settings: WakeSettings,
                         calendar: Calendar = .current) -> WakeTimeRecommendation? {
        let today = calendar.startOfDay(for: now)
        for offset in 0..<wakeSearchDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let start = WakeTimeCalculator.firstCourseStart(in: entries, on: day, calendar: calendar),
                  start > now else { continue }
            return try? WakeTimeCalculator.recommend(for: day,
                                                     entries: entries,
                                                     travelTime: settings.travelTime,
                                                     preparationTime: settings.preparationTime,
                                                     safetyMargin: settings.safetyMargin,
                                                     calendar: calendar)
        }
        return nil
    }
}
