import Foundation

/// Libellés de dates en français, partagés par l'UI et les services de synthèse.
/// Le calendrier est injecté (fuseau horaire compris) pour rester testable.
enum DateLabels {
    private static let locale = Locale(identifier: "fr_FR")

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// « 08:00 »
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "HH:mm", calendar: calendar)
    }

    /// « mercredi »
    static func weekday(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "EEEE", calendar: calendar)
    }

    /// « mer. »
    static func weekdayShort(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "EEE", calendar: calendar)
    }

    /// « 7 »
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "d", calendar: calendar)
    }

    /// « mercredi 7 octobre »
    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "EEEE d MMMM", calendar: calendar)
    }

    /// « aujourd'hui », « demain », « hier », sinon le nom du jour.
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "aujourd'hui" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "demain" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "hier" }
        return weekday(date, calendar: calendar)
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
