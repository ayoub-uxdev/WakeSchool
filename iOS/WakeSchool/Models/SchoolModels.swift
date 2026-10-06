import Foundation

// MARK: - Emploi du temps

/// Statut d'un cours, dérivé de `isCancelled` / `isModified`.
enum CourseStatus: String, Codable, Hashable {
    case normal
    case modified
    case cancelled
}

struct TimetableEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var teacher: Teacher?
    var room: String?
    var start: Date
    var end: Date
    var isCancelled: Bool = false
    /// Cours dont la salle, l'horaire ou le professeur a changé.
    var isModified: Bool = false
    /// Explication du changement (ex. « Salle changée : B204 → C101 »).
    var changeNote: String? = nil

    var status: CourseStatus {
        if isCancelled { return .cancelled }
        return isModified ? .modified : .normal
    }
}

// MARK: - Devoirs

enum HomeworkPriority: Int, Codable, Hashable, Comparable {
    case low = 0
    case normal = 1
    case high = 2

    static func < (lhs: HomeworkPriority, rhs: HomeworkPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Homework: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var title: String
    var details: String
    var dueDate: Date
    var isDone: Bool = false
    var priority: HomeworkPriority = .normal
}

// MARK: - Notes et moyennes

struct Grade: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var value: Double
    var outOf: Double
    var coefficient: Double = 1
    var date: Date
    var title: String? = nil

    /// Note ramenée sur 20. 0 si le barème est invalide.
    var normalizedValue: Double {
        outOf > 0 ? value / outOf * 20 : 0
    }
}

struct SubjectAverage: Identifiable, Codable, Hashable {
    var subject: Subject
    var average: Double
    var outOf: Double = 20
    /// Moyenne de la classe si la source la fournit.
    var classAverage: Double? = nil

    var id: UUID { subject.id }

    var normalizedAverage: Double {
        outOf > 0 ? average / outOf * 20 : 0
    }
}

// MARK: - Contrôles et évènements

/// Contrôle / devoir surveillé.
struct Exam: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var date: Date
    var title: String
}

enum SchoolEventKind: String, Codable, Hashable {
    case meeting
    case trip
    case holiday
    case other
}

/// Évènement de vie scolaire autre qu'un contrôle (conseil de classe, sortie, vacances...).
struct SchoolEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var start: Date
    var end: Date? = nil
    var kind: SchoolEventKind = .other
    var details: String? = nil
}

struct Reminder: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var fireDate: Date
}
