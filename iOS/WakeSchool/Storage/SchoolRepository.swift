import Foundation
import SwiftData

/// Accès au cache local des données scolaires.
@MainActor
protocol SchoolRepository {
    func loadSnapshot() throws -> SchoolSnapshot
    /// Remplace le contenu local par `snapshot`. L'état « terminé » local des devoirs est conservé.
    func save(_ snapshot: SchoolSnapshot) throws
    func setHomework(_ id: UUID, done: Bool) throws
    func clear() throws
}

@MainActor
final class SwiftDataSchoolRepository: SchoolRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredCourse.self, StoredHomework.self, StoredGrade.self,
                             StoredAverage.self, StoredExam.self, StoredEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func loadSnapshot() throws -> SchoolSnapshot {
        SchoolSnapshot(
            timetable: ScheduleService.sorted(try context.fetch(FetchDescriptor<StoredCourse>()).map { $0.entry }),
            homework: HomeworkService.sorted(try context.fetch(FetchDescriptor<StoredHomework>()).map { $0.homework }),
            grades: try context.fetch(FetchDescriptor<StoredGrade>()).map { $0.grade }.sorted { $0.date > $1.date },
            averages: try context.fetch(FetchDescriptor<StoredAverage>()).map { $0.subjectAverage }
                .sorted { $0.subject.name < $1.subject.name },
            exams: try context.fetch(FetchDescriptor<StoredExam>()).map { $0.exam }.sorted { $0.date < $1.date },
            events: try context.fetch(FetchDescriptor<StoredEvent>()).map { $0.event }.sorted { $0.start < $1.start }
        )
    }

    func save(_ snapshot: SchoolSnapshot) throws {
        var localDone: [UUID: Bool] = [:]
        for stored in try context.fetch(FetchDescriptor<StoredHomework>()) {
            localDone[stored.id] = stored.isDone
        }

        try deleteAll()

        snapshot.timetable.forEach { context.insert(StoredCourse($0)) }
        snapshot.homework.forEach {
            context.insert(StoredHomework($0, isDone: $0.isDone || (localDone[$0.id] ?? false)))
        }
        snapshot.grades.forEach { context.insert(StoredGrade($0)) }
        snapshot.averages.forEach { context.insert(StoredAverage($0)) }
        snapshot.exams.forEach { context.insert(StoredExam($0)) }
        snapshot.events.forEach { context.insert(StoredEvent($0)) }
        try context.save()
    }

    func setHomework(_ id: UUID, done: Bool) throws {
        let all = try context.fetch(FetchDescriptor<StoredHomework>())
        guard let target = all.first(where: { $0.id == id }) else { return }
        target.isDone = done
        try context.save()
    }

    func clear() throws {
        try deleteAll()
        try context.save()
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
