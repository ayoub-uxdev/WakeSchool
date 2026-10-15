import Foundation

/// Valeur d'une évaluation : numérique ou statut non numérique (ABS, Disp, NA…).
/// Un statut non numérique n'est JAMAIS converti en zéro ni inclus dans les moyennes.
enum GradeValueStatus: String, Codable, Hashable {
    case absent = "ABS"
    case dispensed = "Disp"
    case notAssessed = "NA"
}

enum GradeValue: Codable, Hashable {
    case numeric(Double)
    case status(GradeValueStatus)

    /// Valeur numérique uniquement (nil pour un statut non numérique).
    var numeric: Double? {
        switch self {
        case .numeric(let value): return value
        case .status: return nil
        }
    }

    /// Texte affichable : « 12,5 » ou « ABS ». Format autonome (Models ne dépend
    /// ni de l'UI ni de Services, cf. ARCHITECTURE.md).
    var displayValue: String {
        switch self {
        case .numeric(let value):
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 1
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        case .status(let status):
            return status.rawValue
        }
    }

    /// True si la valeur participe aux calculs de moyenne.
    var isNumeric: Bool { numeric != nil }

    private enum CodingKeys: String, CodingKey {
        case numericValue
        case statusRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try container.decodeIfPresent(String.self, forKey: .statusRaw),
           let status = GradeValueStatus(rawValue: raw) {
            self = .status(status)
        } else {
            self = .numeric(try container.decode(Double.self, forKey: .numericValue))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .numeric(let value): try container.encode(value, forKey: .numericValue)
        case .status(let status): try container.encode(status.rawValue, forKey: .statusRaw)
        }
    }
}

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
    case unspecified = 3

    var displayLabel: String {
        switch self {
        case .low: return "Peu important"
        case .normal: return "Importance normale"
        case .high: return "Important"
        case .unspecified: return "Importance non renseignée"
        }
    }

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
    var priority: HomeworkPriority = .unspecified
    var attachments: [HomeworkAttachment] = []
}

struct HomeworkAttachment: Identifiable, Codable, Hashable {
    enum Kind: Int, Codable {
        case link = 0
        case file = 1
        case unsupported = -1
    }

    let protocolID: String
    let name: String
    let kind: Kind
    let linkURL: String?

    var id: String { "\(protocolID):\(kind.rawValue)" }
}

// MARK: - Notes et moyennes

struct Grade: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var value: GradeValue
    var outOf: Double
    var coefficient: Double = 1
    var date: Date
    var title: String? = nil

    /// Création d'une note numérique (cas le plus courant).
    init(id: UUID, subject: Subject, value: Double, outOf: Double, coefficient: Double = 1, date: Date, title: String? = nil) {
        self.id = id
        self.subject = subject
        self.value = .numeric(value)
        self.outOf = outOf
        self.coefficient = coefficient
        self.date = date
        self.title = title
    }

    /// Création d'une évaluation non numérique (ABS, Disp, NA…).
    /// `outOf` est conservé tel que PRONOTE l'a fourni ;
    /// il n'est jamais utilisé pour transformer le statut en valeur chiffrée.
    init(id: UUID, subject: Subject, status: GradeValueStatus, outOf: Double = 20, coefficient: Double = 1, date: Date, title: String? = nil) {
        self.id = id
        self.subject = subject
        self.value = .status(status)
        self.outOf = outOf
        self.coefficient = coefficient
        self.date = date
        self.title = title
    }

    /// Valeur numérique de la note, nil si la note est un statut non numérique.
    var numericValue: Double? { value.numeric }

    /// Note ramenée sur 20. Uniquement pour une note numérique ;
    /// une évaluation ABS/Disp/NA n'a pas de valeur normalisée.
    var normalizedValue: Double? {
        guard let value = value.numeric else { return nil }
        return outOf > 0 ? value / outOf * 20 : nil
    }

    /// Texte affichable : « 12,5 » ou « ABS ».
    var displayValue: String { value.displayValue }

    /// True si l'évaluation participe aux calculs de moyenne.
    var isNumeric: Bool { value.isNumeric }
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
