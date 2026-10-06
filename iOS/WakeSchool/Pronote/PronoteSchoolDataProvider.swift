import Foundation

/// Adaptateur `PronoteClient` -> `SchoolDataProvider`.
/// Pronote n'expose pour l'instant que l'emploi du temps, les devoirs et les notes ;
/// les contrôles et évènements restent vides tant que le client ne les fournit pas.
struct PronoteSchoolDataProvider: SchoolDataProvider {
    let client: PronoteClient

    func timetable() async throws -> [TimetableEntry] { try await client.getTimetable() }
    func homework() async throws -> [Homework] { try await client.getHomework() }
    func grades() async throws -> [Grade] { try await client.getGrades() }
    func exams() async throws -> [Exam] { [] }
    func events() async throws -> [SchoolEvent] { [] }
}
