/// Modèles partagés entre l'application WakeSchool et l'extension Widget.
///
/// Aucun identifiant ni jeton PRONOTE n'est stocké ici : seules des données
/// d'affichage non sensibles sont échangées via le App Group.
import Foundation

/// Instantané minimal d'un cours, partagé via App Group.
struct WidgetCourse: Codable, Equatable {
    let subjectName: String
    let teacherName: String?
    let room: String?
    let startDate: Date
    let endDate: Date
    let isCancelled: Bool
}

/// Libellés de dates en français, partagés par l'UI de l'app et la vue du widget.
/// Décliné dans un fichier partagé car l'extension Widget ne peut pas importer le module de l'app.
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

    /// « aujourd'hui », « demain », « hier », sinon le nom du jour.
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "aujourd'hui" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "demain" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "hier" }
        return weekday(date, calendar: calendar)
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

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}