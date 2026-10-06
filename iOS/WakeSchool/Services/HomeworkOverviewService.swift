import Foundation

/// Devoirs répartis pour l'écran Devoirs.
struct HomeworkSections: Equatable {
    var overdue: [Homework] = []
    var upcoming: [Homework] = []
    var done: [Homework] = []

    var isEmpty: Bool { overdue.isEmpty && upcoming.isEmpty && done.isEmpty }
    var total: Int { overdue.count + upcoming.count + done.count }
    /// Part de devoirs terminés, entre 0 et 1.
    var completion: Double { total == 0 ? 0 : Double(done.count) / Double(total) }
}

enum HomeworkOverviewService {
    static func sections(from homework: [Homework], now: Date) -> HomeworkSections {
        let overdue = HomeworkService.overdue(homework, now: now)
        let overdueIDs = Set(overdue.map { $0.id })
        let upcoming = HomeworkService.pending(homework).filter { !overdueIDs.contains($0.id) }
        return HomeworkSections(overdue: overdue,
                                upcoming: upcoming,
                                done: HomeworkService.completed(homework))
    }
}
