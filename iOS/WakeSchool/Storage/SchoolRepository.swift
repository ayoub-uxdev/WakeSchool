import Foundation
import SwiftData

/// Erreurs possibles du cache local scolaire.
enum SchoolRepositoryError: LocalizedError, Equatable {
    /// Le devoir que l'on cherche à modifier n'existe plus dans le cache local.
    case homeworkNotFound
    public var errorDescription: String? {
        switch self {
        case .homeworkNotFound:
            return "Devoir introuvable dans le cache local."
        }
    }
}

/// Accès au cache local des données scolaires.
@MainActor
protocol SchoolRepository {
    func loadSnapshot() throws -> SchoolSnapshot
    /// Remplace le contenu local par `snapshot`. L'état « terminé » local des devoirs est conservé.
    func save(_ snapshot: SchoolSnapshot) throws
    func setHomework(_ id: UUID, done: Bool) throws
    func clear() throws
    /// Absences et retards stockés localement (les plus récents d'abord).
    func loadAttendance() throws -> [AttendanceEvent]
    /// Remplace uniquement les absences et retards locaux (indépendant du cache scolaire).
    func saveAttendance(_ events: [AttendanceEvent]) throws

    // MARK: - Périodes scolaires (chargement progressif)

    /// Toutes les périodes connues, même non encore récupérées.
    func loadPeriods() throws -> [SchoolPeriod]
    /// Fusion ciblée de l'emploi du temps pour une période donnée.
    func saveTimetable(_ entries: [TimetableEntry], for period: SchoolPeriod) throws
    /// Marque une période comme récupérée (ou non).
    func markPeriodComplete(_ period: SchoolPeriod, isComplete: Bool) throws
    /// Supprime les cours d'une période avant re-fetch.
    func removeTimetable(for period: SchoolPeriod) throws
}

@MainActor
final class SwiftDataSchoolRepository: SchoolRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredCourse.self, StoredCoursePeriodLink.self, StoredHomework.self, StoredGrade.self,
                             StoredAverage.self, StoredExam.self, StoredEvent.self,
                             StoredAttendanceEvent.self, StoredSchoolPeriod.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func loadSnapshot() throws -> SchoolSnapshot {
        SchoolSnapshot(
            timetable: ScheduleService.sorted(try context.fetch(FetchDescriptor<StoredCourse>()).map { $0.entry }),
            homework: HomeworkService.sorted(try context.fetch(FetchDescriptor<StoredHomework>()).map { try $0.homework() }),
            grades: try context.fetch(FetchDescriptor<StoredGrade>()).map { $0.grade }.sorted { $0.date > $1.date },
            averages: try context.fetch(FetchDescriptor<StoredAverage>()).map { $0.subjectAverage }
                .sorted { $0.subject.name < $1.subject.name },
            exams: try context.fetch(FetchDescriptor<StoredExam>()).map { $0.exam }.sorted { $0.date < $1.date },
            events: try context.fetch(FetchDescriptor<StoredEvent>()).map { $0.event }.sorted { $0.start < $1.start },
            attendance: try loadAttendance()
        )
    }

    /// Toutes les périodes scolaires connues (même celles dont l'emploi du temps
    /// n'a pas encore été récupéré). Une période absente de cette liste n'a
    /// JAMAIS été fetchée ; elle ne doit pas être interprétée comme vide.
    func loadPeriods() throws -> [SchoolPeriod] {
        try context.fetch(FetchDescriptor<StoredSchoolPeriod>())
            .map { $0.period }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Absences et retards (persistance indépendante du cache scolaire)

    /// Absences et retards stockés localement, triés du plus récent au plus ancien.
    func loadAttendance() throws -> [AttendanceEvent] {
        try context.fetch(FetchDescriptor<StoredAttendanceEvent>())
            .map { $0.event }
            .sorted { $0.start > $1.start }
    }

    /// Remplace uniquement les absences et retards locaux.
    /// Volontairement indépendant de `save(_:)` : une synchronisation scolaire
    /// (cours, devoirs, notes) n'écrase jamais la vie scolaire, et inversement.
    func saveAttendance(_ events: [AttendanceEvent]) throws {
        try context.delete(model: StoredAttendanceEvent.self)
        events.forEach { context.insert(StoredAttendanceEvent($0)) }
        try context.save()
    }

    func save(_ snapshot: SchoolSnapshot) throws {
        let stored = try context.fetch(FetchDescriptor<StoredHomework>())

        var localDoneByID: [UUID: Bool] = [:]
        for item in stored { localDoneByID[item.id] = item.isDone }

        var localDoneByKey: [String: Bool] = [:]
        var storedKeyCounts: [String: Int] = [:]
        for item in stored {
            let key = Self.businessKey(subjectName: item.subjectName,
                                       dueDate: item.dueDate,
                                       title: item.title)
            storedKeyCounts[key, default: 0] += 1
            localDoneByKey[key] = item.isDone
        }

        var incomingKeyCounts: [String: Int] = [:]
        for homework in snapshot.homework {
            let key = Self.businessKey(subjectName: homework.subject.name,
                                       dueDate: homework.dueDate,
                                       title: homework.title)
            incomingKeyCounts[key, default: 0] += 1
        }

        try upsertTimetable(snapshot.timetable)

        try context.delete(model: StoredHomework.self)
        try context.delete(model: StoredGrade.self)
        try context.delete(model: StoredAverage.self)
        try context.delete(model: StoredExam.self)
        try context.delete(model: StoredEvent.self)

        for homework in snapshot.homework {
            let key = Self.businessKey(subjectName: homework.subject.name,
                                       dueDate: homework.dueDate,
                                       title: homework.title)
            let localByKey = (incomingKeyCounts[key] == 1 && storedKeyCounts[key] == 1)
                ? localDoneByKey[key]
                : nil
            let done = localDoneByID[homework.id] ?? localByKey ?? homework.isDone
            context.insert(try StoredHomework(homework, isDone: done))
        }
        snapshot.grades.forEach { context.insert(StoredGrade($0)) }
        snapshot.averages.forEach { context.insert(StoredAverage($0)) }
        snapshot.exams.forEach { context.insert(StoredExam($0)) }
        snapshot.events.forEach { context.insert(StoredEvent($0)) }

        try markPeriodsCovered(by: snapshot.timetable)
        try context.save()
    }

    /// Fusion ciblée de l'emploi du temps pour une période donnée.
    /// Un cours peut appartenir à plusieurs périodes chevauchantes. Les liens
    /// (courseID, periodID) sont gérés dans une table de liaison afin qu'une
    /// actualisation de P2 ne supprime pas un cours encore référencé par P1.
    func saveTimetable(_ entries: [TimetableEntry], for period: SchoolPeriod) throws {
        let existingCourses: [UUID: StoredCourse] = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<StoredCourse>())
                .map { ($0.id, $0) }
        )
        let existingLinks: [StoredCoursePeriodLink] = try context.fetch(FetchDescriptor<StoredCoursePeriodLink>())
        let incomingIDs = Set(entries.map { $0.id })

        // 1. Supprimer les liens de cette période pour les cours absents du snapshot entrant.
        for link in existingLinks where link.periodID == period.id && !incomingIDs.contains(link.courseID) {
            context.delete(link)
        }

        // 2. Supprimer les cours devenus orphelins (plus aucun lien vers une période).
        let linksForOtherPeriods = existingLinks.filter { $0.periodID != period.id }
        let linkedCourseIDsForOtherPeriods = Set(linksForOtherPeriods.map { $0.courseID })
        let orphanedCourseIDs = Set(existingLinks.map { $0.courseID })
            .subtracting(linkedCourseIDsForOtherPeriods)
        for courseID in orphanedCourseIDs where existingCourses[courseID] != nil {
            context.delete(existingCourses[courseID]!)
        }

        // 3. Insérer / mettre à jour les cours entrants et créer leurs liens.
        for entry in entries {
            if let existing = existingCourses[entry.id] {
                existing.subjectID = entry.subject.id
                existing.subjectName = entry.subject.name
                existing.teacherID = entry.teacher?.id
                existing.teacherName = entry.teacher?.name
                existing.room = entry.room
                existing.start = entry.start
                existing.end = entry.end
                existing.isCancelled = entry.isCancelled
                existing.isModified = entry.isModified
                existing.changeNote = entry.changeNote
            } else {
                context.insert(StoredCourse(entry))
            }
            let linkExists = existingLinks.contains { $0.courseID == entry.id && $0.periodID == period.id }
            if !linkExists {
                context.insert(StoredCoursePeriodLink(courseID: entry.id, periodID: period.id))
            }
        }

        var period = period
        period.isTimetableComplete = true
        try upsertPeriod(period)
        try context.save()
    }

    /// Marque une période comme récupérée (ou non) sans toucher aux cours.
    func markPeriodComplete(_ period: SchoolPeriod, isComplete: Bool = true) throws {
        var period = period
        period.isTimetableComplete = isComplete
        try upsertPeriod(period)
        try context.save()
    }

    /// Supprime les liens cours←→période pour une période donnée, puis les cours
    /// devenus orphelins (plus aucun lien vers aucune période). À n'appeler que
    /// avant un re-fetch complet et valide de cette période.
    /// Ne sauvegarde pas : l'appelant (`saveTimetable`) sauvera tout atomiquement.
    func removeTimetable(for period: SchoolPeriod) throws {
        let allLinks = try context.fetch(FetchDescriptor<StoredCoursePeriodLink>())
        let linksForPeriod = allLinks.filter { $0.periodID == period.id }
        for link in linksForPeriod {
            context.delete(link)
        }
        let linksForOtherPeriods = allLinks.filter { $0.periodID != period.id }
        let linkedCourseIDs = Set(linksForOtherPeriods.map { $0.courseID })
        let allCourses = try context.fetch(FetchDescriptor<StoredCourse>())
        for course in allCourses where !linkedCourseIDs.contains(course.id) {
            context.delete(course)
        }
    }

    func setHomework(_ id: UUID, done: Bool) throws {
        let all = try context.fetch(FetchDescriptor<StoredHomework>())
        // Un devoir introuvable n'est PAS une réussite silencieuse : l'erreur
        // remonte à l'appelant (sinon l'UI croit avoir enregistré une coche
        // qui n'existe nulle part).
        guard let target = all.first(where: { $0.id == id }) else {
            throw SchoolRepositoryError.homeworkNotFound
        }
        target.isDone = done
        try context.save()
    }

    func clear() throws {
        try deleteAll()
        try context.delete(model: StoredAttendanceEvent.self)
        try context.save()
    }

    /// Identité métier stable d'un devoir, indépendante de l'identifiant
    /// technique PRONOTE : même matière, même échéance (au jour), même titre.
    /// Volontairement prudemment : deux devoirs distincts avec des titres
    /// différents ne partagent JAMAIS de clé (aucun transfert de coche entre
    /// devoirs simplement semblables).
    static func businessKey(subjectName: String, dueDate: Date, title: String) -> String {
        let normalizedSubject = subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let day = Calendar(identifier: .gregorian).startOfDay(for: dueDate).timeIntervalSince1970
        return "\(normalizedSubject)|\(day)|\(normalizedTitle)"
    }

    private func deleteAll() throws {
        try context.delete(model: StoredCourse.self)
        try context.delete(model: StoredHomework.self)
        try context.delete(model: StoredGrade.self)
        try context.delete(model: StoredAverage.self)
        try context.delete(model: StoredExam.self)
        try context.delete(model: StoredEvent.self)
        try context.delete(model: StoredSchoolPeriod.self)
    }

    // MARK: - Privé : upsert

    /// Insère ou met à jour les cours par ID, sans jamais supprimer les cours
    /// absents de `entries`.
    ///
    /// Une synchronisation PRONOTE classique ne récupère qu'une fenêtre limitée
    /// (ex. trois semaines) : une suppression globale non bornée effacerait
    /// toutes les autres périodes déjà en cache. Les cours sont donc uniquement
    /// insérés ou mis à jour par ID. Un cours dont l'identifiant change peut
    /// temporairement apparaître en double ; il sera corrigé lors de la
    /// prochaine synchronisation ciblée de sa période (`saveTimetable(_:for:)`)
    /// qui appelle `removeTimetable(for:)` de façon bornée.
    private func upsertTimetable(_ entries: [TimetableEntry]) throws {
        let existing = try context.fetch(FetchDescriptor<StoredCourse>())
        let existingByID: [UUID: StoredCourse] = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.id, $0) }
        )

        for entry in entries {
            if let existing = existingByID[entry.id] {
                existing.subjectID = entry.subject.id
                existing.subjectName = entry.subject.name
                existing.teacherID = entry.teacher?.id
                existing.teacherName = entry.teacher?.name
                existing.room = entry.room
                existing.start = entry.start
                existing.end = entry.end
                existing.isCancelled = entry.isCancelled
                existing.isModified = entry.isModified
                existing.changeNote = entry.changeNote
            } else {
                context.insert(StoredCourse(entry))
            }
        }
    }

    /// Insère ou met à jour une période scolaire.
    private func upsertPeriod(_ period: SchoolPeriod) throws {
        let existing = try context.fetch(FetchDescriptor<StoredSchoolPeriod>())
            .first { $0.id == period.id }
        if let existing = existing {
            existing.title = period.title
            existing.startDate = period.startDate
            existing.endDate = period.endDate
            existing.isTimetableComplete = period.isTimetableComplete
        } else {
            context.insert(StoredSchoolPeriod(period))
        }
    }

    /// Marque comme complètes toutes les périodes couvertes par les cours donnés.
    /// Les modifications sont sauvegardées par l'appelant (`save(_:)` ou `saveTimetable(_:for:)`).
    private func markPeriodsCovered(by entries: [TimetableEntry]) throws {
        guard !entries.isEmpty else { return }
        let knownPeriods = try loadPeriods()
        let calendar = Calendar(identifier: .gregorian)
        for entry in entries {
            let entryDay = calendar.startOfDay(for: entry.start)
            for known in knownPeriods where !known.isTimetableComplete {
                if (known.startDate...known.endDate).contains(entryDay) {
                    var period = known
                    period.isTimetableComplete = true
                    try upsertPeriod(period)
                }
            }
        }
    }
}
