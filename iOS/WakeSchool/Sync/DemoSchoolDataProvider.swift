import Foundation

/// Provider de démonstration : données déterministes, relatives à `referenceDate`.
/// Contient plusieurs journées, matières, devoirs, notes, un cours annulé et un cours modifié.
///
/// - Premier jour de cours futur : le 2e cours est annulé.
/// - Deuxième jour de cours futur : le 2e cours est modifié (changement de salle).
struct DemoSchoolDataProvider: SchoolDataProvider {
    let referenceDate: Date
    let calendar: Calendar

    init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    // MARK: - Matières et professeurs (identifiants stables)

    static let maths = Subject(id: stableID(0, 1), name: "Mathématiques")
    static let french = Subject(id: stableID(0, 2), name: "Français")
    static let history = Subject(id: stableID(0, 3), name: "Histoire-Géographie")
    static let physics = Subject(id: stableID(0, 4), name: "Physique-Chimie")
    static let english = Subject(id: stableID(0, 5), name: "Anglais")
    static let biology = Subject(id: stableID(0, 6), name: "SVT")
    static let sport = Subject(id: stableID(0, 7), name: "EPS")

    static let allSubjects = [maths, french, history, physics, english, biology, sport]

    private static let teachers: [UUID: Teacher] = {
        let list: [(Subject, String)] = [
            (maths, "M. Martin"), (french, "Mme Dubois"), (history, "M. Leroy"),
            (physics, "Mme Bernard"), (english, "Mr Smith"), (biology, "Mme Petit"), (sport, "M. Roux")
        ]
        var result: [UUID: Teacher] = [:]
        for (index, item) in list.enumerated() {
            result[item.0.id] = Teacher(id: stableID(1, index + 1), name: item.1)
        }
        return result
    }()

    static func stableID(_ namespace: Int, _ number: Int) -> UUID {
        let text = String(format: "%08llX-0000-4000-8000-%012llX", UInt64(namespace), UInt64(number))
        return UUID(uuidString: text) ?? UUID()
    }

    // MARK: - Emploi du temps

    private struct Slot {
        let hour: Int
        let minute: Int
        let duration: Int
        let subject: Subject
        let room: String
    }

    /// Semaine type, clé = `Calendar.weekday` (2 = lundi ... 6 = vendredi).
    private static let week: [Int: [Slot]] = [
        2: [Slot(hour: 8, minute: 0, duration: 55, subject: maths, room: "B204"),
            Slot(hour: 9, minute: 0, duration: 55, subject: french, room: "A110"),
            Slot(hour: 10, minute: 15, duration: 55, subject: history, room: "A203"),
            Slot(hour: 14, minute: 0, duration: 55, subject: english, room: "C105")],
        3: [Slot(hour: 8, minute: 0, duration: 55, subject: physics, room: "Labo 2"),
            Slot(hour: 9, minute: 0, duration: 55, subject: maths, room: "B204"),
            Slot(hour: 11, minute: 0, duration: 55, subject: biology, room: "Labo 1"),
            Slot(hour: 15, minute: 0, duration: 110, subject: sport, room: "Gymnase")],
        4: [Slot(hour: 9, minute: 0, duration: 55, subject: french, room: "A110"),
            Slot(hour: 10, minute: 0, duration: 55, subject: english, room: "C105")],
        5: [Slot(hour: 8, minute: 0, duration: 55, subject: history, room: "A203"),
            Slot(hour: 9, minute: 0, duration: 55, subject: physics, room: "Labo 2"),
            Slot(hour: 10, minute: 15, duration: 55, subject: maths, room: "B204"),
            Slot(hour: 13, minute: 30, duration: 55, subject: biology, room: "Labo 1"),
            Slot(hour: 14, minute: 30, duration: 55, subject: french, room: "A110")],
        6: [Slot(hour: 8, minute: 0, duration: 55, subject: english, room: "C105"),
            Slot(hour: 9, minute: 0, duration: 55, subject: maths, room: "B204"),
            Slot(hour: 10, minute: 15, duration: 110, subject: sport, room: "Gymnase")]
    ]

    private func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = day(offset)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    func timetable() async throws -> [TimetableEntry] {
        var entries: [TimetableEntry] = []
        var futureSchoolDays = 0

        for offset in -3...9 {
            let weekday = calendar.component(.weekday, from: day(offset))
            guard let slots = Self.week[weekday] else { continue }
            if offset > 0 { futureSchoolDays += 1 }

            for (index, slot) in slots.enumerated() {
                let start = at(offset, slot.hour, slot.minute)
                var entry = TimetableEntry(
                    id: Self.stableID(2, (offset + 50) * 100 + index),
                    subject: slot.subject,
                    teacher: Self.teachers[slot.subject.id],
                    room: slot.room,
                    start: start,
                    end: start.addingTimeInterval(TimeInterval(slot.duration) * 60)
                )
                if offset > 0 && index == 1 {
                    if futureSchoolDays == 1 {
                        entry.isCancelled = true
                        entry.changeNote = "Professeur absent"
                    } else if futureSchoolDays == 2 {
                        entry.isModified = true
                        entry.room = "C101"
                        entry.changeNote = "Salle changée : \(slot.room) → C101"
                    }
                }
                entries.append(entry)
            }
        }
        return ScheduleService.sorted(entries)
    }

    // MARK: - Devoirs

    func homework() async throws -> [Homework] {
        func hw(_ n: Int, _ subject: Subject, _ title: String, _ details: String,
                due: Int, hour: Int = 8, done: Bool = false,
                priority: HomeworkPriority = .normal) -> Homework {
            Homework(id: Self.stableID(3, n), subject: subject, title: title, details: details,
                     dueDate: at(due, hour), isDone: done, priority: priority)
        }
        return HomeworkService.sorted([
            hw(1, Self.maths, "Exercices 12 à 15", "Page 87, dérivées et variations.",
               due: -1, priority: .high),
            hw(2, Self.french, "Commentaire de texte", "Rédiger l'introduction et le plan.",
               due: 0, hour: 18, priority: .high),
            hw(3, Self.english, "Learn vocabulary", "Unit 5, liste de vocabulaire.", due: 1, priority: .low),
            hw(4, Self.history, "Fiche de révision", "La Guerre froide, 1947-1991.", due: 2, done: true),
            hw(5, Self.physics, "Compte rendu de TP", "Mesure de la vitesse du son.", due: 3),
            hw(6, Self.biology, "Schéma de la cellule", "À légender et à coller dans le cahier.", due: 5, priority: .low),
            hw(7, Self.maths, "Réviser le DS", "Chapitres 4 à 6.", due: 6, priority: .high)
        ])
    }

    // MARK: - Notes

    func grades() async throws -> [Grade] {
        func grade(_ n: Int, _ subject: Subject, _ title: String,
                   _ value: Double, _ outOf: Double = 20, coef: Double = 1, daysAgo: Int) -> Grade {
            Grade(id: Self.stableID(4, n), subject: subject, value: value, outOf: outOf,
                  coefficient: coef, date: at(-daysAgo, 10), title: title)
        }
        return [
            grade(1, Self.maths, "DS 1", 14, coef: 2, daysAgo: 28),
            grade(2, Self.maths, "Interrogation", 16.5, daysAgo: 14),
            grade(3, Self.maths, "DS 2", 12, coef: 3, daysAgo: 4),
            grade(4, Self.french, "Dissertation", 11, coef: 2, daysAgo: 21),
            grade(5, Self.french, "Oral", 13.5, daysAgo: 9),
            grade(6, Self.history, "Contrôle", 15, daysAgo: 12),
            grade(7, Self.physics, "TP noté", 8, 10, daysAgo: 7),
            grade(8, Self.english, "Compréhension orale", 17, daysAgo: 16),
            grade(9, Self.biology, "Contrôle 1", 12, daysAgo: 25),
            grade(10, Self.biology, "Contrôle 2", 9, coef: 2, daysAgo: 6),
            grade(11, Self.sport, "Course de durée", 15, daysAgo: 18)
        ]
    }

    // MARK: - Contrôles et évènements

    func exams() async throws -> [Exam] {
        [
            Exam(id: Self.stableID(5, 1), subject: Self.history, date: at(-5, 9), title: "Contrôle Guerre froide"),
            Exam(id: Self.stableID(5, 2), subject: Self.maths, date: at(3, 8), title: "DS n°3"),
            Exam(id: Self.stableID(5, 3), subject: Self.english, date: at(6, 14), title: "Évaluation écrite"),
            Exam(id: Self.stableID(5, 4), subject: Self.physics, date: at(12, 9), title: "Contrôle chapitre 5")
        ]
    }

    func events() async throws -> [SchoolEvent] {
        [
            SchoolEvent(id: Self.stableID(6, 1), title: "Conseil de classe",
                        start: at(4, 17), end: at(4, 19), kind: .meeting, details: nil),
            SchoolEvent(id: Self.stableID(6, 2), title: "Sortie au musée",
                        start: at(8, 8), end: at(8, 17), kind: .trip, details: "Départ devant le lycée."),
            SchoolEvent(id: Self.stableID(6, 3), title: "Vacances",
                        start: at(40, 0), end: at(54, 0), kind: .holiday, details: nil)
        ]
    }
}
