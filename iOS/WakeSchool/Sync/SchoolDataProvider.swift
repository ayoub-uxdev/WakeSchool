import Foundation

/// Source de données scolaires. Les Views et les Services n'en connaissent pas l'implémentation
/// (démo, Pronote, ou autre). Brancher une nouvelle source = écrire un nouveau provider.
protocol SchoolDataProvider {
    func timetable() async throws -> [TimetableEntry]
    /// Emploi du temps pour la plage de dates donnée.
    /// Implémentation par défaut : filtre le résultat de `timetable()` par plage de dates.
    /// Les providers capables de cibler une période (ex. Pronote par semaine) surchargent
    /// cette méthode pour éviter de télécharger inutilement toute l'année.
    func timetable(in range: ClosedRange<Date>) async throws -> [TimetableEntry]
    func homework() async throws -> [Homework]
    func grades() async throws -> [Grade]
    func averages() async throws -> [SubjectAverage]
    func exams() async throws -> [Exam]
    func events() async throws -> [SchoolEvent]
    /// Absences et retards. Fourni avec une implémentation par défaut (vide).
    func attendance() async throws -> [AttendanceEvent]
}

protocol HomeworkAttachmentDownloading {
    func downloadHomeworkAttachment(_ attachment: HomeworkAttachment) async throws -> Data
}

extension SchoolDataProvider {
    /// Par défaut, aucune absence/retard (sources qui ne les fournissent pas).
    func attendance() async throws -> [AttendanceEvent] { [] }

    /// Par défaut, les moyennes sont calculées localement à partir des notes.
    /// Un provider dont la source fournit ses propres moyennes peut surcharger cette méthode.
    func averages() async throws -> [SubjectAverage] {
        AverageCalculator.subjectAverages(from: try await grades())
    }

    /// Récupère les données scolaires de base (cours, devoirs, notes, contrôles, évènements).
    /// Échoue en entier si une récupération échoue : le cache local n'est ainsi jamais
    /// écrasé par des données partielles.
    ///
    /// Les absences/retards en sont volontairement EXCLUS : ils suivent un chemin de
    /// synchronisation indépendant (`SchoolSyncService.syncAttendance`) afin qu'un
    /// éventuel blocage de l'API vie scolaire n'empêche jamais la synchronisation du cache scolaire.
    func snapshot() async throws -> SchoolSnapshot {
        SchoolSnapshot(timetable: try await timetable(),
                       homework: try await homework(),
                       grades: try await grades(),
                       averages: try await averages(),
                       exams: try await exams(),
                       events: try await events())
    }

    /// Implémentation par défaut : filtre le résultat de `timetable()` par plage de dates.
    /// Les providers capables de cibler une période surchargent pour éviter de
    /// télécharger inutilement des données hors plage.
    func timetable(in range: ClosedRange<Date>) async throws -> [TimetableEntry] {
        let all = try await timetable()
        return all.filter { entry in
            (range.lowerBound...range.upperBound).contains(entry.start)
        }
    }
}
