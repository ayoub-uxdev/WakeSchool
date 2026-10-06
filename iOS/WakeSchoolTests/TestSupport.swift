import XCTest
@testable import WakeSchool

/// Outils communs aux tests du socle de données (calendrier UTC, octobre 2026).
/// Le 7 octobre 2026 est un mercredi.
enum TestSupport {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    static let maths = Subject(id: DemoSchoolDataProvider.stableID(9, 1), name: "Maths")
    static let french = Subject(id: DemoSchoolDataProvider.stableID(9, 2), name: "Français")

    static func entry(_ day: Int, _ hour: Int, _ minute: Int = 0,
                      minutes: Int = 60,
                      subject: Subject = TestSupport.maths,
                      cancelled: Bool = false,
                      modified: Bool = false) -> TimetableEntry {
        let start = date(day, hour, minute)
        return TimetableEntry(id: UUID(), subject: subject, start: start,
                              end: start.addingTimeInterval(TimeInterval(minutes) * 60),
                              isCancelled: cancelled, isModified: modified)
    }

    static func homework(_ title: String, due: Date, done: Bool = false,
                         priority: HomeworkPriority = .normal,
                         subject: Subject = TestSupport.maths) -> Homework {
        Homework(id: UUID(), subject: subject, title: title, details: "", dueDate: due,
                 isDone: done, priority: priority)
    }

    static func grade(_ value: Double, _ outOf: Double = 20, coef: Double = 1,
                      subject: Subject = TestSupport.maths, day: Int = 1) -> Grade {
        Grade(id: UUID(), subject: subject, value: value, outOf: outOf,
              coefficient: coef, date: date(day, 10))
    }
}
