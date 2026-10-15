import Foundation

protocol PronoteClient {
    func getTimetable() async throws -> [TimetableEntry]
    func getHomework() async throws -> [Homework]
    func getGrades() async throws -> [Grade]
    /// Absences et retards de l'élève.
    func getAttendance() async throws -> [AttendanceEvent]
    /// Emploi du temps ET contrôles (DS) en UNE SEULE récupération.
    /// Implémentation par défaut : emploi du temps puis contrôles dérivés.
    /// Les clients qui dérivent les DS de la réponse emploi du temps surchargent
    /// cette méthode pour éviter une deuxième récupération réseau.
    func getTimetableAndExams() async throws -> (entries: [TimetableEntry], exams: [Exam])
}

extension PronoteClient {
    func getTimetableAndExams() async throws -> (entries: [TimetableEntry], exams: [Exam]) {
        let entries = try await getTimetable()
        return (entries, [])
    }
}
