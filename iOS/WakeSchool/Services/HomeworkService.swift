import Foundation

enum HomeworkService {

    /// Tri par date limite, puis priorité décroissante, puis titre.
    static func sorted(_ homework: [Homework]) -> [Homework] {
        homework.sorted {
            if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.title < $1.title
        }
    }

    static func pending(_ homework: [Homework]) -> [Homework] {
        sorted(homework.filter { !$0.isDone })
    }

    static func completed(_ homework: [Homework]) -> [Homework] {
        sorted(homework.filter { $0.isDone })
    }

    /// Devoirs non terminés dont la date limite est dépassée.
    static func overdue(_ homework: [Homework], now: Date) -> [Homework] {
        pending(homework).filter { $0.dueDate < now }
    }

    /// Devoirs non terminés à rendre dans les `days` jours à venir (de `now` inclus).
    static func dueSoon(_ homework: [Homework], now: Date, withinDays days: Int) -> [Homework] {
        let limit = now.addingTimeInterval(TimeInterval(max(0, days)) * 86_400)
        return pending(homework).filter { $0.dueDate >= now && $0.dueDate <= limit }
    }

    /// Devoirs dont la date limite tombe le jour `day`.
    static func due(on day: Date, in homework: [Homework], calendar: Calendar = .current) -> [Homework] {
        sorted(homework.filter { calendar.isDate($0.dueDate, inSameDayAs: day) })
    }

    static func forSubject(_ subject: Subject, in homework: [Homework]) -> [Homework] {
        sorted(homework.filter { $0.subject.id == subject.id })
    }
}
