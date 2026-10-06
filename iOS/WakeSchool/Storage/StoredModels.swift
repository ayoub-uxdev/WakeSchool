import Foundation
import SwiftData

// Modèles SwiftData : de simples « lignes » de persistance.
// Les structs de `Models/` restent la représentation utilisée partout ailleurs.

@Model
final class StoredCourse {
    @Attribute(.unique) var id: UUID
    var subjectID: UUID
    var subjectName: String
    var teacherID: UUID?
    var teacherName: String?
    var room: String?
    var start: Date
    var end: Date
    var isCancelled: Bool
    var isModified: Bool
    var changeNote: String?

    init(_ entry: TimetableEntry) {
        id = entry.id
        subjectID = entry.subject.id
        subjectName = entry.subject.name
        teacherID = entry.teacher?.id
        teacherName = entry.teacher?.name
        room = entry.room
        start = entry.start
        end = entry.end
        isCancelled = entry.isCancelled
        isModified = entry.isModified
        changeNote = entry.changeNote
    }

    var entry: TimetableEntry {
        var teacher: Teacher?
        if let teacherID = teacherID, let teacherName = teacherName {
            teacher = Teacher(id: teacherID, name: teacherName)
        }
        return TimetableEntry(id: id,
                              subject: Subject(id: subjectID, name: subjectName),
                              teacher: teacher,
                              room: room,
                              start: start,
                              end: end,
                              isCancelled: isCancelled,
                              isModified: isModified,
                              changeNote: changeNote)
    }
}

@Model
final class StoredHomework {
    @Attribute(.unique) var id: UUID
    var subjectID: UUID
    var subjectName: String
    var title: String
    var details: String
    var dueDate: Date
    var isDone: Bool
    var priorityRaw: Int

    init(_ homework: Homework, isDone: Bool) {
        id = homework.id
        subjectID = homework.subject.id
        subjectName = homework.subject.name
        title = homework.title
        details = homework.details
        dueDate = homework.dueDate
        self.isDone = isDone
        priorityRaw = homework.priority.rawValue
    }

    var homework: Homework {
        Homework(id: id,
                 subject: Subject(id: subjectID, name: subjectName),
                 title: title,
                 details: details,
                 dueDate: dueDate,
                 isDone: isDone,
                 priority: HomeworkPriority(rawValue: priorityRaw) ?? .normal)
    }
}

@Model
final class StoredGrade {
    @Attribute(.unique) var id: UUID
    var subjectID: UUID
    var subjectName: String
    var title: String?
    var value: Double
    var outOf: Double
    var coefficient: Double
    var date: Date

    init(_ grade: Grade) {
        id = grade.id
        subjectID = grade.subject.id
        subjectName = grade.subject.name
        title = grade.title
        value = grade.value
        outOf = grade.outOf
        coefficient = grade.coefficient
        date = grade.date
    }

    var grade: Grade {
        Grade(id: id,
              subject: Subject(id: subjectID, name: subjectName),
              value: value,
              outOf: outOf,
              coefficient: coefficient,
              date: date,
              title: title)
    }
}

@Model
final class StoredAverage {
    @Attribute(.unique) var subjectID: UUID
    var subjectName: String
    var average: Double
    var outOf: Double
    var classAverage: Double?

    init(_ average: SubjectAverage) {
        subjectID = average.subject.id
        subjectName = average.subject.name
        self.average = average.average
        outOf = average.outOf
        classAverage = average.classAverage
    }

    var subjectAverage: SubjectAverage {
        SubjectAverage(subject: Subject(id: subjectID, name: subjectName),
                       average: average,
                       outOf: outOf,
                       classAverage: classAverage)
    }
}

@Model
final class StoredExam {
    @Attribute(.unique) var id: UUID
    var subjectID: UUID
    var subjectName: String
    var title: String
    var date: Date

    init(_ exam: Exam) {
        id = exam.id
        subjectID = exam.subject.id
        subjectName = exam.subject.name
        title = exam.title
        date = exam.date
    }

    var exam: Exam {
        Exam(id: id, subject: Subject(id: subjectID, name: subjectName), date: date, title: title)
    }
}

@Model
final class StoredEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var start: Date
    var end: Date?
    var kindRaw: String
    var details: String?

    init(_ event: SchoolEvent) {
        id = event.id
        title = event.title
        start = event.start
        end = event.end
        kindRaw = event.kind.rawValue
        details = event.details
    }

    var event: SchoolEvent {
        SchoolEvent(id: id,
                    title: title,
                    start: start,
                    end: end,
                    kind: SchoolEventKind(rawValue: kindRaw) ?? .other,
                    details: details)
    }
}
