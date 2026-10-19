import Foundation

/// Orchestre provider -> repository. Si le provider échoue (hors ligne, erreur Pronote...),
/// le cache local reste intact et l'erreur est propagée.
@MainActor
final class SchoolSyncService {
    private let provider: SchoolDataProvider
    private let repository: SchoolRepository
    private let preferences: PreferencesStore
    private let now: () -> Date
    private(set) var diagnostics: PronoteSyncDiagnostics?

    init(provider: SchoolDataProvider,
         repository: SchoolRepository,
         preferences: PreferencesStore,
         now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.repository = repository
        self.preferences = preferences
        self.now = now
    }

    /// Données déjà présentes sur l'appareil (fonctionne hors ligne).
    func loadCached() throws -> SchoolSnapshot {
        try repository.loadSnapshot()
    }

    func downloadHomeworkAttachment(_ attachment: HomeworkAttachment) async throws -> Data {
        guard let downloader = provider as? HomeworkAttachmentDownloading else {
            throw PronoteTransportError.attachmentDownloadUnsupported
        }
        return try await downloader.downloadHomeworkAttachment(attachment)
    }

    // MARK: - Absences et retards (synchronisation indépendante)

    /// Absences et retards déjà présents sur l'appareil (fonctionne hors ligne).
    func loadCachedAttendance() throws -> [AttendanceEvent] {
        try repository.loadAttendance()
    }

    /// Synchronise les absences et retards SÉPARÉMENT du cache scolaire.
    ///
    /// En cas d'échec, l'erreur est propagée mais **aucune donnée locale n'est effacée** :
    /// `saveAttendance` n'est appelé qu'après une récupération réussie. Un blocage de
    /// l'API vie scolaire n'affecte donc jamais les évènements précédemment enregistrés,
    /// ni la synchronisation des cours/devoirs/notes.
    @discardableResult
    func syncAttendance() async throws -> [AttendanceEvent] {
        let events = try await provider.attendance()
        try repository.saveAttendance(events)
        return events
    }

    /// Synchronise l'emploi du temps pour une période scolaire donnée, sans
    /// toucher aux autres périodes ni aux devoirs/notes déjà en cache.
    /// En cas d'échec réseau, les données précédemment enregistrées sont préservées.
    @discardableResult
    func syncTimetable(for period: SchoolPeriod) async throws -> [TimetableEntry] {
        let diagnosticProvider = provider as? SchoolSyncDiagnosticsReporting
        diagnosticProvider?.resetDataDiagnostics()

        let entries: [TimetableEntry]
        do {
            entries = try await provider.timetable(in: period.startDate...period.endDate)
        } catch {
            var result = diagnosticProvider?.dataDiagnostics
            if result?.errorStage == nil {
                result?.recordFailure(error, stage: "SchoolDataProvider.timetable(in:)")
            }
            diagnostics = result
            throw error
        }

        do {
            try repository.saveTimetable(entries, for: period)
        } catch {
            var result = diagnosticProvider?.dataDiagnostics
            result?.recordFailure(error, stage: "SwiftData.saveTimetable")
            diagnostics = result
            throw error
        }

        let saved: SchoolSnapshot
        do {
            saved = try repository.loadSnapshot()
        } catch {
            var result = diagnosticProvider?.dataDiagnostics
            result?.recordFailure(error, stage: "SwiftData.loadSnapshot")
            diagnostics = result
            throw error
        }

        var result = diagnosticProvider?.dataDiagnostics
        result?.recordPersistedSnapshot(saved)
        diagnostics = result
        return entries
    }

    /// Récupère les données, les persiste, puis renvoie l'état local à jour.
    @discardableResult
    func sync() async throws -> SchoolSnapshot {
        let diagnosticProvider = provider as? SchoolSyncDiagnosticsReporting
        diagnosticProvider?.resetDataDiagnostics()

        let fresh: SchoolSnapshot
        do {
            fresh = try await provider.snapshot()
        } catch {
            var result = diagnosticProvider?.dataDiagnostics
            if result?.errorStage == nil {
                result?.recordFailure(error, stage: "SchoolDataProvider.snapshot")
            }
            diagnostics = result
            throw error
        }

        do {
            try repository.save(fresh)
        } catch {
            var result = diagnosticProvider?.dataDiagnostics
            result?.recordFailure(error, stage: "SwiftData.save")
            diagnostics = result
            throw error
        }

        let saved: SchoolSnapshot
        do {
            saved = try repository.loadSnapshot()
        } catch {
            var result = diagnosticProvider?.dataDiagnostics
            result?.recordFailure(error, stage: "SwiftData.loadSnapshot")
            diagnostics = result
            throw error
        }

        var result = diagnosticProvider?.dataDiagnostics
        result?.recordPersistedSnapshot(saved)
        diagnostics = result
        preferences.lastSyncDate = now()
        return saved
    }
}
