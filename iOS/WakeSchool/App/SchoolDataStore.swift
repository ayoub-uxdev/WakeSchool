import Foundation
import SwiftUI

/// État partagé par les écrans.
/// Charge le cache local, déclenche la synchronisation et relaie les actions utilisateur
/// vers les couches Sync / Storage.
@MainActor
final class SchoolDataStore: ObservableObject {
    @Published private(set) var snapshot: SchoolSnapshot = .empty
    @Published private(set) var isSyncing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncDiagnostics: PronoteSyncDiagnostics?

    // Absences et retards : état et erreur INDÉPENDANTS du cache scolaire.
    @Published private(set) var attendance: [AttendanceEvent] = []
    @Published private(set) var isSyncingAttendance = false
    @Published private(set) var attendanceError: String?

    private let environment: AppEnvironment
    private var hasStarted = false

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - Exposition contrôlée de l'environnement

    /// Permet aux écrans de connexion d'enregistrer les identifiants
    /// sans exposer directement l'environnement complet.
    var environmentSecrets: SecretStore {
        environment.secrets
    }

    var wakeSettings: WakeSettings {
        environment.preferences.wakeSettings
    }

    var dataSource: DataSourceKind {
        environment.preferences.dataSource
    }

    // MARK: - Apparence

    var appearance: AppearancePreference {
        environment.preferences.appearance
    }

    func setAppearance(_ value: AppearancePreference) {
        environment.preferences.appearance = value
    }

    // MARK: - Compte scolaire

    /// Résumé NON SENSIBLE du compte PRONOTE configuré.
    /// Ne contient jamais le mot de passe ni le jeton mobile.
    struct PronoteConnectionSummary: Equatable {
        var isConfigured: Bool
        var accountKind: PronoteAccountKind?
        var serverHost: String?
        var method: String?
    }

    var connectionSummary: PronoteConnectionSummary {
        guard let credentials = try? CredentialsStore(store: environment.secrets).load() else {
            return PronoteConnectionSummary(
                isConfigured: false,
                accountKind: nil,
                serverHost: nil,
                method: nil
            )
        }
        return PronoteConnectionSummary(
            isConfigured: true,
            accountKind: credentials.accountKind,
            serverHost: URLComponents(string: credentials.serverURL)?.host,
            method: credentials.usesMobileToken
                ? "Jeton mobile (QR / ENT)"
                : "Identifiants directs"
        )
    }

    // MARK: - Démarrage

    /// Affiche immédiatement le cache local puis synchronise.
    /// Ne s'exécute qu'une seule fois.
    func start() async {
        guard !hasStarted else { return }

        hasStarted = true

        do {
            snapshot = try environment.sync.loadCached()
            syncDiagnostics?.recordPersistedSnapshot(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }

        // Vie scolaire chargée séparément : une erreur ici n'empêche pas l'affichage du cache.
        attendance = (try? environment.sync.loadCachedAttendance()) ?? []

        lastSync = environment.preferences.lastSyncDate

        await refresh()
    }

    // MARK: - Synchronisation

    /// Synchronise avec le provider actuel.
    ///
    /// Si la synchronisation échoue, les données locales restent affichées.
    func refresh() async {
        guard !isSyncing else { return }

        isSyncing = true
        defer {
            isSyncing = false
        }

        do {
            snapshot = try await environment.sync.sync()
            syncDiagnostics = environment.sync.diagnostics
            lastSync = environment.preferences.lastSyncDate
            errorMessage = nil
            await processChangeDetection()
        } catch {
            syncDiagnostics = environment.sync.diagnostics
            syncDiagnostics?.recordPersistedSnapshot(snapshot)
            errorMessage = error.localizedDescription
        }

        // Les absences/retards se synchronisent indépendamment du cache scolaire.
        await refreshAttendance()
    }

    // MARK: - Détection des nouveautés et notifications (LOT 8)

    /// Détecte les nouveautés après synchronisation, met à jour les ids connus
    /// et alimente le centre de notifications.
    ///
    /// La référence est établie par un marqueur PERSISTANT explicite :
    /// à la première synchronisation réussie, les données du moment deviennent
    /// la baseline SANS notification — même si l'utilisateur n'a aucune note
    /// (un ensemble vide n'est pas « premier lancement »). Ensuite, toute note
    /// ou contrôle dont l'id stable n'était pas connu est signalé exactement
    /// une fois.
    private func processChangeDetection() async {
        let hadBaseline = environment.preferences.hasChangeDetectionBaseline
        let knownGrades = environment.preferences.knownGradeIDs
        let knownExams = environment.preferences.knownExamIDs

        // Mise à jour de la référence avec l'état courant.
        environment.preferences.knownGradeIDs = ChangeDetectionService.gradeIDs(in: snapshot)
        environment.preferences.knownExamIDs = ChangeDetectionService.examIDs(in: snapshot)
        environment.preferences.hasChangeDetectionBaseline = true

        // Avant la première baseline : rien à signaler (pas d'avalanche).
        guard hadBaseline else { return }

        let changes = ChangeDetectionService.detect(previousKnownGradeIDs: knownGrades,
                                                    previousKnownExamIDs: knownExams,
                                                    newSnapshot: snapshot)

        // Le centre enregistre les changements même si les notifications système
        // ne sont pas autorisées : le centre reste utile.
        if !changes.newGrades.isEmpty {
            notificationCenter.addIfNew(kind: .newGrade,
                                        title: "Nouvelle\(changes.newGrades.count > 1 ? "s" : "") note\(changes.newGrades.count > 1 ? "s" : "")",
                                        message: changes.newGrades.map { $0.subject.name }.joined(separator: ", "))
        }
        if !changes.newExams.isEmpty {
            notificationCenter.addIfNew(kind: .newExam,
                                        title: "Nouveau\(changes.newExams.count > 1 ? "x" : "") contrôle\(changes.newExams.count > 1 ? "s" : "")",
                                        message: changes.newExams.map { $0.subject.name }.joined(separator: ", "))
        }

        await environment.notifications.processAfterSync(
            entries: snapshot.timetable,
            snapshot: snapshot,
            knownGradeIDs: knownGrades,
            knownExamIDs: knownExams,
            wakeAlarmEnabled: environment.preferences.wakeAlarmEnabled,
            wakeConfirmation: environment.preferences.wakeConfirmation
        )
    }

    /// Centre de notifications WakeSchool (historique local).
    var notificationCenter: NotificationCenterStore { environment.notificationCenter }

    /// Orchestrateur des notifications (réglages).
    var notifications: NotificationOrchestrator { environment.notifications }

    /// Règles de notifications personnalisées.
    var notificationRules: NotificationRulesStore { environment.notificationRules }

    // MARK: - Réveil (LOT 8)

    /// Réveil automatique activé.
    var wakeAlarmEnabled: Bool {
        environment.preferences.wakeAlarmEnabled
    }

    func setWakeAlarmEnabled(_ enabled: Bool) {
        environment.preferences.wakeAlarmEnabled = enabled
        // Désactivation : annule l'alarme AUTOMATIQUE uniquement (jamais les
        // alarmes manuelles). Réactivation : le prochain cycle AutoWake
        // reprogrammera selon l'emploi du temps.
        if !enabled {
            environment.autoWakeLifecycle.disable()
        }
    }

    /// Heure de réveil personnalisée (minutes depuis minuit), nil = calcul AutoWake.
    var customWakeMinutes: Int? {
        environment.preferences.customWakeMinutes
    }

    func setCustomWakeMinutes(_ minutes: Int?) {
        environment.preferences.customWakeMinutes = minutes
        // Changement d'heure : reprogrammation immédiate à partir des données
        // déjà synchronisées (sans nouvelle connexion PRONOTE).
        Task { await recalculateAutoWake() }
    }

    /// Modification des préférences de préparation/trajet : le calcul du réveil
    /// change, donc l'alarme automatique est actualisée.
    func setWakeSettings(_ settings: WakeSettings) {
        environment.preferences.wakeSettings = settings
        Task { await recalculateAutoWake() }
    }

    /// Recalcule le plan AutoWake et met à jour l'alarme automatique à partir
    /// des données DÉJÀ synchronisées (aucun appel réseau PRONOTE).
    func recalculateAutoWake() async {
        await environment.notifications.processAfterSync(
            entries: snapshot.timetable,
            snapshot: snapshot,
            knownGradeIDs: environment.preferences.knownGradeIDs,
            knownExamIDs: environment.preferences.knownExamIDs,
            wakeAlarmEnabled: environment.preferences.wakeAlarmEnabled,
            wakeConfirmation: environment.preferences.wakeConfirmation
        )
    }

    /// Paramètres de la confirmation quotidienne.
    var wakeConfirmation: WakeConfirmationSettings {
        environment.preferences.wakeConfirmation
    }

    func setWakeConfirmation(_ settings: WakeConfirmationSettings) {
        environment.preferences.wakeConfirmation = settings
    }

    /// Synchronise les absences et retards. Totalement dissocié de `refresh` :
    /// un échec ici renseigne `attendanceError` SANS toucher au cache scolaire
    /// ni aux évènements précédemment enregistrés.
    func refreshAttendance() async {
        guard !isSyncingAttendance else { return }

        isSyncingAttendance = true
        defer { isSyncingAttendance = false }

        do {
            attendance = try await environment.sync.syncAttendance()
            attendanceError = nil
        } catch {
            attendanceError = error.localizedDescription
        }
    }

    // MARK: - Source de données

    /// Change la source de données puis reconstruit le provider.
    ///
    /// Exemple :
    /// Demo → PRONOTE
    func setDataSource(_ source: DataSourceKind) {
        environment.preferences.dataSource = source
        environment.reloadProvider()

        errorMessage = nil
        attendanceError = nil
    }

    /// Reconnecte le provider actuel.
    ///
    /// Utile après l'enregistrement de nouvelles identifiants PRONOTE.
    func reloadProvider() {
        environment.reloadProvider()
        errorMessage = nil
        attendanceError = nil
    }

    // MARK: - Devoirs

    /// Marque un devoir comme terminé / non terminé.
    /// L'état est persisté localement.
    func setHomework(_ id: UUID, done: Bool) {
        do {
            try environment.repository.setHomework(id, done: done)
            snapshot = try environment.sync.loadCached()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadHomeworkAttachment(_ attachment: HomeworkAttachment) async throws -> Data {
        try await environment.sync.downloadHomeworkAttachment(attachment)
    }
}