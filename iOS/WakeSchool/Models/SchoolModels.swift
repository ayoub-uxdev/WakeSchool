import Foundation

struct TimetableEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var teacher: Teacher?
    var room: String?
    var start: Date
    var end: Date
    var isCancelled: Bool = false
}

struct Homework: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var details: String
    var dueDate: Date
    var isDone: Bool = false
}

struct Grade: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var value: Double
    var outOf: Double
    var coefficient: Double = 1
    var date: Date
}

struct Exam: Identifiable, Codable, Hashable {
    let id: UUID
    var subject: Subject
    var date: Date
    var title: String
}

struct Reminder: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var fireDate: Date
}
