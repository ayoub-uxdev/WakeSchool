import Foundation

/// Une journée de l'emploi du temps (cours annulés inclus), pour l'affichage par jour.
struct ScheduleDay: Identifiable, Equatable {
    /// Début de journée.
    let date: Date
    /// Cours triés chronologiquement.
    let entries: [TimetableEntry]

    var id: Date { date }
    var activeCount: Int { entries.filter { !$0.isCancelled }.count }
    var cancelledCount: Int { entries.filter { $0.isCancelled }.count }
    var modifiedCount: Int { entries.filter { $0.isModified && !$0.isCancelled }.count }
}

enum ScheduleDayService {

    /// Regroupe les cours par jour de début. Seuls les jours ayant au moins un cours sont renvoyés.
    static func days(from entries: [TimetableEntry], calendar: Calendar = .current) -> [ScheduleDay] {
        let groups = Dictionary(grouping: entries, by: { calendar.startOfDay(for: $0.start) })
        return groups
            .map { ScheduleDay(date: $0.key, entries: ScheduleService.sorted($0.value)) }
            .sorted { $0.date < $1.date }
    }

    /// Jour à afficher par défaut : aujourd'hui s'il a des cours, sinon le prochain jour de cours,
    /// sinon le dernier jour connu.
    static func defaultDay(in days: [ScheduleDay], now: Date, calendar: Calendar = .current) -> ScheduleDay? {
        let today = calendar.startOfDay(for: now)
        if let current = days.first(where: { $0.date == today }) { return current }
        if let next = days.first(where: { $0.date > today }) { return next }
        return days.last
    }

    /// « 4 cours · 1 annulé · 8:00 – 15:55 »
    static func summaryLine(for day: ScheduleDay, calendar: Calendar = .current) -> String {
        var parts = ["\(day.activeCount) cours"]
        if day.cancelledCount > 0 {
            parts.append(day.cancelledCount == 1 ? "1 annulé" : "\(day.cancelledCount) annulés")
        }
        if day.modifiedCount > 0 {
            parts.append(day.modifiedCount == 1 ? "1 modifié" : "\(day.modifiedCount) modifiés")
        }
        let active = day.entries.filter { !$0.isCancelled }
        if let first = active.map({ $0.start }).min(), let last = active.map({ $0.end }).max() {
            parts.append("\(DateLabels.time(first, calendar: calendar)) – \(DateLabels.time(last, calendar: calendar))")
        }
        return parts.joined(separator: " · ")
    }
}
