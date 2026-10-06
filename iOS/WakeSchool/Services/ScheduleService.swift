import Foundation

/// Requêtes pures sur l'emploi du temps. Aucune dépendance UI, stockage ou réseau.
/// Les calculs de réveil restent dans `WakeTimeCalculator`.
enum ScheduleService {

    /// Tri chronologique (début, puis fin, puis matière).
    static func sorted(_ entries: [TimetableEntry]) -> [TimetableEntry] {
        entries.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.subject.name < $1.subject.name
        }
    }

    /// Cours non annulés, triés.
    static func active(_ entries: [TimetableEntry]) -> [TimetableEntry] {
        sorted(entries.filter { !$0.isCancelled })
    }

    /// Cours annulés, triés.
    static func cancelled(_ entries: [TimetableEntry]) -> [TimetableEntry] {
        sorted(entries.filter { $0.isCancelled })
    }

    /// Cours modifiés (et non annulés), triés.
    static func modified(_ entries: [TimetableEntry]) -> [TimetableEntry] {
        sorted(entries.filter { $0.isModified && !$0.isCancelled })
    }

    /// Cours commençant le jour `day`, triés. Les cours annulés sont exclus par défaut.
    static func entries(on day: Date,
                        in entries: [TimetableEntry],
                        includeCancelled: Bool = false,
                        calendar: Calendar = .current) -> [TimetableEntry] {
        let ofDay = entries.filter { calendar.isDate($0.start, inSameDayAs: day) }
        return includeCancelled ? sorted(ofDay) : active(ofDay)
    }

    /// Premier cours non annulé du jour.
    static func firstCourse(on day: Date,
                            in entries: [TimetableEntry],
                            calendar: Calendar = .current) -> TimetableEntry? {
        self.entries(on: day, in: entries, calendar: calendar).first
    }

    /// Dernier cours non annulé du jour (celui qui finit le plus tard).
    static func lastCourse(on day: Date,
                           in entries: [TimetableEntry],
                           calendar: Calendar = .current) -> TimetableEntry? {
        self.entries(on: day, in: entries, calendar: calendar).max { $0.end < $1.end }
    }

    /// Cours en cours à l'instant `now` (non annulé), s'il y en a un.
    static func currentCourse(at now: Date, in entries: [TimetableEntry]) -> TimetableEntry? {
        active(entries).first { $0.start <= now && now < $0.end }
    }

    /// Prochain cours non annulé qui commence strictement après `now`.
    static func nextCourse(after now: Date, in entries: [TimetableEntry]) -> TimetableEntry? {
        active(entries).first { $0.start > now }
    }

    /// Cours non annulés qui commencent après `now`, triés, limités à `limit` si fourni.
    static func upcoming(after now: Date,
                         in entries: [TimetableEntry],
                         limit: Int? = nil) -> [TimetableEntry] {
        let result = active(entries).filter { $0.start > now }
        guard let limit = limit else { return result }
        return Array(result.prefix(max(0, limit)))
    }
}
