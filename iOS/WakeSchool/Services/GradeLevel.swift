import Foundation

/// Niveau qualitatif d'une note ou d'une moyenne sur 20.
enum GradeLevel: Equatable {
    case excellent
    case good
    case average
    case low

    init(value: Double) {
        switch value {
        case 16...: self = .excellent
        case 13..<16: self = .good
        case 10..<13: self = .average
        default: self = .low
        }
    }

    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Bien"
        case .average: return "Correct"
        case .low: return "À renforcer"
        }
    }
}
