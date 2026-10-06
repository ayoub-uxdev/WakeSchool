import Foundation

/// Source de données scolaires. Les Views et les Services n'en connaissent pas l'implémentation
/// (démo, Pronote, ou autre). Brancher une nouvelle source = écrire un nouveau provider.
protocol SchoolDataProvider {
    func timetable() async throws -> [TimetableEntry]
    func homework() async throws -> [Homework]
    func grades() async throws -> [Grade]
    func averages() async throws -> [SubjectAverage]
    func exams() async throws -> [Exam]
    func events() async throws -> [SchoolEvent]
}

extension SchoolDataProvider {
    /// Par défaut, les moyennes sont calculées localement à partir des notes.
    /// Un provider dont la source fournit ses propres moyennes peut surcharger cette méthode.
    func averages() async throws -> [SubjectAverage] {
        AverageCalculator.subjectAverages(from: try await grades())
    }

    /// Récupère toutes les données. Échoue en entier si une récupération échoue :
    /// le cache local n'est ainsi jamais écrasé par des données partielles.
    func snapshot() async throws -> SchoolSnapshot {
        SchoolSnapshot(timetable: try await timetable(),
                       homework: try await homework(),
                       grades: try await grades(),
                       averages: try await averages(),
                       exams: try await exams(),
                       events: try await events())
    }
}
