import Foundation

enum InsightKind: String, Equatable {
    case currentCourse
    case cancelledCourse
    case modifiedCourse
    case overdueHomework
    case upcomingExam
    case homeworkDueSoon
    case nextCourse
    case allClear
}

/// Une phrase du « résumé intelligent » du Dashboard.
struct SmartInsight: Identifiable, Equatable {
    let kind: InsightKind
    /// Nom de SF Symbol.
    let icon: String
    let message: String

    var id: String { kind.rawValue }
}

/// Résumé simple : règles fixes, par ordre d'importance. Pas d'IA ici.
enum InsightService {
    static let examHorizonDays = 7

    static func insights(from summary: DashboardSummary,
                         calendar: Calendar = .current,
                         limit: Int = 3) -> [SmartInsight] {
        let now = summary.now
        func day(_ date: Date) -> String { DateLabels.relativeDay(date, now: now, calendar: calendar) }
        func time(_ date: Date) -> String { DateLabels.time(date, calendar: calendar) }

        var result: [SmartInsight] = []

        if let course = summary.currentCourse {
            result.append(SmartInsight(kind: .currentCourse, icon: "book.fill",
                                       message: "En cours : \(course.subject.name) jusqu'à \(time(course.end))."))
        }
        if let course = summary.cancelledUpcoming.first {
            result.append(SmartInsight(kind: .cancelledCourse, icon: "xmark.circle.fill",
                                       message: "\(course.subject.name) est annulé \(day(course.start)) à \(time(course.start))."))
        }
        if let course = summary.modifiedUpcoming.first {
            let note = course.changeNote ?? "cours modifié"
            result.append(SmartInsight(kind: .modifiedCourse, icon: "arrow.triangle.2.circlepath",
                                       message: "\(course.subject.name) \(day(course.start)) à \(time(course.start)) — \(note)."))
        }
        if !summary.overdueHomework.isEmpty {
            let count = summary.overdueHomework.count
            let message = count == 1
                ? "1 devoir est en retard : \(summary.overdueHomework[0].title)."
                : "\(count) devoirs sont en retard."
            result.append(SmartInsight(kind: .overdueHomework, icon: "exclamationmark.triangle.fill", message: message))
        }
        let examLimit = now.addingTimeInterval(TimeInterval(examHorizonDays) * 86_400)
        if let exam = summary.upcomingExams.first(where: { $0.date <= examLimit }) {
            result.append(SmartInsight(kind: .upcomingExam, icon: "checklist",
                                       message: "Contrôle de \(exam.subject.name) \(day(exam.date)) à \(time(exam.date)) : \(exam.title)."))
        }
        if !summary.homeworkDueSoon.isEmpty {
            let count = summary.homeworkDueSoon.count
            let message = count == 1
                ? "À rendre bientôt : \(summary.homeworkDueSoon[0].title) (\(summary.homeworkDueSoon[0].subject.name))."
                : "\(count) devoirs à rendre dans les \(DashboardService.homeworkSoonDays) jours."
            result.append(SmartInsight(kind: .homeworkDueSoon, icon: "tray.full.fill", message: message))
        }
        if let course = summary.nextCourse {
            result.append(SmartInsight(kind: .nextCourse, icon: "clock.fill",
                                       message: "Prochain cours : \(course.subject.name) \(day(course.start)) à \(time(course.start))."))
        }

        if result.isEmpty {
            return [SmartInsight(kind: .allClear, icon: "sparkles", message: "Rien d'urgent. Profite de ta journée.")]
        }
        return Array(result.prefix(max(1, limit)))
    }
}
