import Foundation

/// Interface d'accès aux données Pronote. Aucune implémentation réelle pour l'instant.
protocol PronoteClient {
    func getTimetable() async throws -> [TimetableEntry]
    func getHomework() async throws -> [Homework]
    func getGrades() async throws -> [Grade]
}
