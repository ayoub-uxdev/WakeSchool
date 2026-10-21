import Foundation
import SwiftData

// ModÃ¨les SwiftData : de simples Â« lignes Â» de persistance.
// Les structs de `Models/` restent la reprÃ©sentation utilisÃ©e partout ailleurs.

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
final class StoredCoursePeriodLink {
    @Attribute(.unique) var id: UUID
    var courseID: UUID
    var periodID: String

    init(courseID: UUID, periodID: String) {
        self.id = UUID()
        self.courseID = courseID
        self.periodID = periodID
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
    var attachmentMetadata: Data?
    /// Identifiant natif PRONOTE (champ « N ») pour réconciliation stable.
    var pronoteID: String?
    /// Version de l'algorithme de génération d'UUID :
    /// 0 = ancien (incluait details dans le hash), 1 = nouveau (basé sur pronoteID ou clé métier stable).
    var legacyAlgorithmVersion: Int = 0
    /// Date de dernière synchronisation où ce devoir a été vu.
    /// Permet un nettoyage futur des devoirs obsolètes.
    var lastSyncedAt: Date?

    init(_ homework: Homework, isDone: Bool) throws {
        id = homework.id
        subjectID = homework.subject.id
        subjectName = homework.subject.name
        title = homework.title
        details = homework.details
        dueDate = homework.dueDate
        self.isDone = isDone
        priorityRaw = homework.priority.rawValue
        attachmentMetadata = try JSONEncoder().encode(homework.attachments)
        pronoteID = homework.pronoteID
        legacyAlgorithmVersion = 1
        lastSyncedAt = Date()
    }

    func homework() throws -> Homework {
        let attachments = try attachmentMetadata.map {
            try JSONDecoder().decode([HomeworkAttachment].self, from: $0)
        } ?? []
        return Homework(
            id: id,
            subject: Subject(id: subjectID, name: subjectName),
            title: title,
            details: details,
            dueDate: dueDate,
            isDone: isDone,
            priority: HomeworkPriority(rawValue: priorityRaw) ?? .unspecified,
            attachments: attachments,
            pronoteID: pronoteID
        )
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
    /// Statut non numÃ©rique de la note (Â« ABS Â», Â« Disp Â», Â« NA Â»).
    /// nil = note numÃ©rique (`value` fait foi). Ajout LOT 8 : les anciennes
    /// lignes crÃ©Ã©es avant cet attribut ont une valeur nil lue par SwiftData,
    /// ce qui correspond bien Ã  une note numÃ©rique.
    var statusRaw: String?

    init(_ grade: Grade) {
        id = grade.id
        subjectID = grade.subject.id
        subjectName = grade.subject.name
        title = grade.title
        value = grade.value.numeric ?? 0
        outOf = grade.outOf
        coefficient = grade.coefficient
        date = grade.date
        if case .status(let status) = grade.value {
            statusRaw = status.rawValue
        } else {
            statusRaw = nil
        }
    }

    var grade: Grade {
        if let statusRaw,
           let status = GradeValueStatus(rawValue: statusRaw) {
            return Grade(id: id,
                         subject: Subject(id: subjectID, name: subjectName),
                         status: status,
                         outOf: outOf,
                         coefficient: coefficient,
                         date: date,
                         title: title)
        }
        return Grade(id: id,
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

@Model
final class StoredSchoolPeriod {
    @Attribute(.unique) var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isTimetableComplete: Bool

    init(_ period: SchoolPeriod) {
        id = period.id
        title = period.title
        startDate = period.startDate
        endDate = period.endDate
        isTimetableComplete = period.isTimetableComplete
    }

    var period: SchoolPeriod {
        SchoolPeriod(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isTimetableComplete: isTimetableComplete
        )
    }
}

@Model
final class StoredAttendanceEvent {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var start: Date
    var end: Date?
    var durationMinutes: Int
    var isJustified: Bool
    var justification: String?
    var reasons: [String]
    var subjectName: String?

    init(_ event: AttendanceEvent) {
        id = event.id
        kindRaw = event.kind.rawValue
        start = event.start
        end = event.end
        // 0 = durÃ©e inconnue (le champ du modÃ¨le est non optionnel).
        durationMinutes = event.durationMinutes ?? 0
        isJustified = event.isJustified
        justification = event.justification
        reasons = event.reasons
        subjectName = event.subjectName
    }

    var event: AttendanceEvent {
        AttendanceEvent(
            id: id,
            kind: AttendanceKind(rawValue: kindRaw) ?? .absence,
            start: start,
            end: end,
            durationMinutes: durationMinutes > 0 ? durationMinutes : nil,
            isJustified: isJustified,
            justification: justification,
            reasons: reasons,
            subjectName: subjectName
        )
    }
}


