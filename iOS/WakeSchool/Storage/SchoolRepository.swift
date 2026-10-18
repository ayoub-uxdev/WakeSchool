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
}

@MainActor
final class SwiftDataSchoolRepository: SchoolRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredCourse.self, StoredHomework.self, StoredGrade.self,
                             StoredAverage.self, StoredExam.self, StoredEvent.self,
                             StoredAttendanceEvent.self])
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

        // État local par UUID technique…
        var localDoneByID: [UUID: Bool] = [:]
        for item in stored {
            localDoneByID[item.id] = item.isDone
        }

        // …et par identité métier stable (matière + jour d'échéance + titre),
        // qui survit au changement d'identifiant technique PRONOTE (`N`).
        // Transfert de coche par clé UNIQUEMENT si la clé est sans ambiguïté :
        // un seul ancien devoir ET un seul nouveau devoir portent cette clé
        // (jamais de transfert arbitraire entre devoirs simplement semblables).
        var localDoneByKey: [String: Bool] = [:]
        var storedKeyCounts: [String: Int] = [:]
        for item in stored {
            let key = Self.businessKey(subjectName: item.subjectName,
                                       dueDate: item.dueDate,
                                       title: item.title)
            storedKeyCounts[key, default: 0] += 1
            localDoneByKey[key] = item.isDone
        }

        // Deux devoirs entrants partageant la même clé : correspondance non
        // fiable, aucun transfert de coche pour ces clés.
        var incomingKeyCounts: [String: Int] = [:]
        for homework in snapshot.homework {
            let key = Self.businessKey(subjectName: homework.subject.name,
                                       dueDate: homework.dueDate,
                                       title: homework.title)
            incomingKeyCounts[key, default: 0] += 1
        }

        try deleteAll()

        snapshot.timetable.forEach { context.insert(StoredCourse($0)) }
        for homework in snapshot.homework {
            // Le choix local de l'utilisateur GAGNE toujours : un devoir décoché
            // localement (« false ») ne doit pas être recoché par PRONOTE
            // (l'ancien « OR » réactivait systématiquement les devoirs décochés).
            // La valeur PRONOTE ne sert que s'il n'y a aucun état local connu.
            let key = Self.businessKey(subjectName: homework.subject.name,
                                       dueDate: homework.dueDate,
                                       title: homework.title)
            let localByKey = (incomingKeyCounts[key] == 1 && storedKeyCounts[key] == 1)
                ? localDoneByKey[key]
                : nil
            let done = localDoneByID[homework.id] ?? localByKey ?? homework.isDone
            context.insert(try StoredHomework(
                homework,
                isDone: done
            ))
        }
        snapshot.grades.forEach { context.insert(StoredGrade($0)) }
        snapshot.averages.forEach { context.insert(StoredAverage($0)) }
        snapshot.exams.forEach { context.insert(StoredExam($0)) }
        snapshot.events.forEach { context.insert(StoredEvent($0)) }
        try context.save()
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
    }
}
