import Foundation

protocol PronoteClient {
    func getTimetable() async throws -> [TimetableEntry]
    func getHomework() async throws -> [Homework]
    func getGrades() async throws -> [Grade]
    /// Absences et retards de l'élève.
    func getAttendance() async throws -> [AttendanceEvent]
}
