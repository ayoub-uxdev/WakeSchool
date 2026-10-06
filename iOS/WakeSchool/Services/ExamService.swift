import Foundation

enum ExamService {
    /// Contrôles à venir dans les `days` jours (de `now` inclus), triés par date.
    static func upcoming(_ exams: [Exam], now: Date, withinDays days: Int) -> [Exam] {
        let limit = now.addingTimeInterval(TimeInterval(max(0, days)) * 86_400)
        return exams
            .filter { $0.date >= now && $0.date <= limit }
            .sorted { $0.date < $1.date }
    }
}
