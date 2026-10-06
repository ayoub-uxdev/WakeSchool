import Foundation

/// Photographie complète des données scolaires à un instant donné.
/// C'est ce que le provider produit, ce que le Storage persiste et ce que les Services consomment.
struct SchoolSnapshot: Codable, Equatable {
    var timetable: [TimetableEntry] = []
    var homework: [Homework] = []
    var grades: [Grade] = []
    var averages: [SubjectAverage] = []
    var exams: [Exam] = []
    var events: [SchoolEvent] = []

    static let empty = SchoolSnapshot()
}
