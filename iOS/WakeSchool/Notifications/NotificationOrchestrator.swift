import Foundation
import UserNotifications

/// Orchestrateur central des notifications WakeSchool.
///
/// Responsabilités :
/// - après chaque synchronisation utile : recalcul du plan AutoWake,
///   programmation de l'alarme (si activée) et de la confirmation quotidienne,
///   détection des nouveautés (notes / DS), alimentation du centre et des règles ;
/// - demande d'autorisation CONTEXTUELLE (jamais au premier lancement) ;
/// - notification de test.
///
/// HONNÊTETÉ iOS : l'alarme du réveil passe par AlarmKit (véritable alarme
/// système). Les confirmations et règles sont des NOTIFICATIONS LOCALES
/// classiques — iOS ne garantit ni leur heure exacte ni une requête PRONOTE
/// en arrière-plan ; leur contenu est calculé à partir des données déjà
/// connues de WakeSchool au moment de la planification.
@MainActor
final class NotificationOrchestrator: ObservableObject {
    private let scheduler: NotificationScheduling
    private let center: NotificationCenterStore
    private let rules: NotificationRulesStore
    private let preferences: PreferencesStore
    /// Alarme système (AlarmKit) pour le réveil automatique. Optionnel : nil = non géré ici.
    private let alarmScheduler: AlarmScheduling?
    /// Cycle de vie de l'alarme AUTOMATIQUE, isolé des alarmes manuelles.
    private let autoWakeLifecycle: AutoWakeLifecycle?
    private let now: () -> Date
    private let calendar: Calendar

    /// Dernière erreur à afficher dans les Réglages (sans données sensibles).
    @Published private(set) var lastIssue: String?

    init(scheduler: NotificationScheduling,
         center: NotificationCenterStore,
         rules: NotificationRulesStore,
         preferences: PreferencesStore,
         alarmScheduler: AlarmScheduling? = nil,
         autoWakeLifecycle: AutoWakeLifecycle? = nil,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.scheduler = scheduler
        self.center = center
        self.rules = rules
        self.preferences = preferences
        self.alarmScheduler = alarmScheduler
        self.autoWakeLifecycle = autoWakeLifecycle
        self.now = now
        self.calendar = calendar
    }

    static func live(preferences: PreferencesStore, center: NotificationCenterStore, rules: NotificationRulesStore) -> NotificationOrchestrator {
        NotificationOrchestrator(scheduler: SystemNotificationScheduler(),
                                 center: center,
                                 rules: rules,
                                 preferences: preferences)
    }

    // MARK: - Autorisation

    /// Demande l'autorisation : à appeler UNIQUEMENT depuis un écran qui a
    /// expliqué au préalable pourquoi les notifications sont utiles.
    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await scheduler.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await scheduler.requestAuthorization()
        case .denied:
            lastIssue = "Les notifications sont désactivées pour WakeSchool. Active-les dans Réglages pour recevoir les rappels."
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Traitement après synchronisation

    /// À appeler après chaque synchronisation (ou chargement du cache).
    /// Recalcule le plan AutoWake, met à jour les notifications, détecte
    /// les nouveautés. `knownGradeIDs`/`knownExamIDs` : état connu avant sync.
    func processAfterSync(entries: [TimetableEntry],
                          periods: [SchoolPeriod]?,
                          isDemoMode: Bool = false,
                          snapshot: SchoolSnapshot,
                          knownGradeIDs: Set<UUID>,
                          knownExamIDs: Set<UUID>,
                          wakeAlarmEnabled: Bool,
                          wakeConfirmation: WakeConfirmationSettings) async {
        let current = now()
        let settings = preferences.wakeSettings

        // 1. Plan AutoWake à partir de l'emploi du temps réel.
        let customMinutes = preferences.customWakeMinutes
        let planResult = AutoWakeService.plan(entries: entries,
                                              periods: periods,
                                              now: current,
                                              settings: settings,
                                              isDemoMode: isDemoMode,
                                              customWakeMinutesFromMidnight: customMinutes,
                                              calendar: calendar)
        let plan = planResult.plan
        center.addIfNew(kind: .wakeProposed,
                        title: "Réveil proposé",
                        message: plan.map { "\(DateLabels.dayTitle($0.targetDay)) à \(DateLabels.time($0.recommendation.wakeTime))" } ?? "Aucun cours à venir.")

        // 2. Détection des nouveautés (notes et DS).
        let changes = ChangeDetectionService.detect(previousKnownGradeIDs: knownGradeIDs,
                                                    previousKnownExamIDs: knownExamIDs,
                                                    newSnapshot: snapshot)
        if !changes.newGrades.isEmpty {
            center.addIfNew(kind: .newGrade,
                            title: "Nouvelle\(changes.newGrades.count > 1 ? "s" : "") note\(changes.newGrades.count > 1 ? "s" : "")",
                            message: changes.newGrades.map { $0.subject.name }.joined(separator: ", "))
        }
        if !changes.newExams.isEmpty {
            center.addIfNew(kind: .newExam,
                            title: "Nouveau\(changes.newExams.count > 1 ? "x" : "") contrôle\(changes.newExams.count > 1 ? "s" : "")",
                            message: changes.newExams.map { $0.subject.name }.joined(separator: ", "))
        }

        // 3. Cycle de vie de l'alarme automatique AutoWake (store ISOLÉ des
        // alarmes manuelles de SmartAlarmView) :
        // - alarme activée + plan valide → programme/reprogramme si l'heure
        //   a changé (anti-doublon) ; jamais d'inscription si AlarmKit échoue ;
        // - alarme activée mais plus de plan valide (cours annulé/disparu)
        //   → annule l'alarme obsolète ;
        // - une alarme manuelle n'est JAMAIS annulée ici.
        if let autoWakeLifecycle {
            switch planResult {
            case .planned(let plan):
                if wakeAlarmEnabled, plan.recommendation.wakeTime > current,
                   AutoWakeService.shouldReschedule(existingFireDate: autoWakeLifecycle.current?.fireDate,
                                                    desiredFireDate: plan.recommendation.wakeTime) {
                    if await autoWakeLifecycle.schedule(plan: plan) != nil {
                        center.addIfNew(kind: .wakeConfirmed,
                                        title: "Reveil programme",
                                        message: "\(DateLabels.dayTitle(plan.targetDay)) a \(DateLabels.time(plan.recommendation.wakeTime))" + (plan.isCustom ? " (personnalise)" : ""))
                    } else {
                        // AlarmKit indisponible : fallback honnete - une notification
                        // locale (moins fiable) a la meme heure, clairement signalee.
                        if let notification = WakeConfirmationService.notification(plan: plan, now: current, calendar: calendar) {
                            try? await scheduler.schedule(notification, at: plan.recommendation.wakeTime)
                        }
                        lastIssue = "Alarme systeme indisponible : une notification locale (moins fiable) a ete prevue a la place."
                    }
                }
            case .holidaysConfirmed:
                if wakeAlarmEnabled {
                    _ = autoWakeLifecycle.reconcile(plan: nil)
                }
            case .insufficientData:
                // Ne pas annuler aveuglement une alarme valide.
                // Si l'alarme existante est deja depassee, l'annuler.
                if wakeAlarmEnabled, let alarm = autoWakeLifecycle.current, alarm.fireDate <= current {
                    autoWakeLifecycle.cancel()
                }
            }
        }// 4. Notifications système planifiées.
        await scheduleSystem(plan: plan, changes: changes, homework: snapshot.homework,
                             wakeAlarmEnabled: wakeAlarmEnabled,
                             wakeConfirmation: wakeConfirmation)
    }

    private func scheduleSystem(plan: AutoWakePlan?,
                                changes: ChangeDetectionService.Changes,
                                homework: [Homework],
                                wakeAlarmEnabled: Bool,
                                wakeConfirmation: WakeConfirmationSettings) async {
        guard await requestAuthorizationIfNeeded() else { return }
        let current = now()

        // PURGE préalable : toute notification devenue obsolète est annulée.
        // - confirmation sans plan valide (cours annulé/disparu, confirmation
        //   désactivée, sync trop vieille) → annulée ;
        // - rappel « devoirs demain » sans devoir réellement à rendre demain
        //   → annulé ;
        // - règles désactivées : leurs notifications éventuelles sont annulées
        //   (une règle désactivée ne peut plus déclencher rien de futur).
        var obsoleteIDs: [String] = []
        if !WakeConfirmationService.shouldSend(plan: plan,
                                              settings: wakeConfirmation,
                                              lastSync: preferences.lastSyncDate,
                                              now: current) {
            // Annule les confirmations planifiées pour les prochains jours.
            let pending = await scheduler.pendingIDs()
            obsoleteIDs.append(contentsOf: pending.filter { $0.hasPrefix(WakeNotification.Kind.wakeConfirmation.prefix) })
        }
        let pendingNow = await scheduler.pendingIDs()
        // Règle « devoirs demain » désactivée ou sans devoir à rendre : purge.
        let homeworkRule = rules.rules.first(where: { $0.kind == .homeworkDueTomorrow })
        let homeworkDueTomorrow = NotificationRuleService.homeworkDueTomorrowMessage(
            homework: homework, now: current, calendar: calendar) != nil
        if homeworkRule?.isEnabled != true || !homeworkDueTomorrow {
            obsoleteIDs.append(contentsOf: pendingNow.filter { $0.hasPrefix("rule.homework.") })
        }
        // Règles événementielles désactivées : purge des notifications résiduelles.
        for rule in rules.rules where !rule.isEnabled {
            switch rule.kind {
            case .newGrade:
                obsoleteIDs.append(contentsOf: pendingNow.filter { $0.hasPrefix("rule.grade.") })
            case .newExam:
                obsoleteIDs.append(contentsOf: pendingNow.filter { $0.hasPrefix("rule.exam.") })
            case .homeworkDueTomorrow:
                break // déjà traité ci-dessus
            case .gradeDigestAtTime:
                obsoleteIDs.append(contentsOf: pendingNow.filter { $0.hasPrefix("rule.digest.") })
            }
        }
        if !obsoleteIDs.isEmpty {
            scheduler.cancel(ids: obsoleteIDs)
        }

        // Confirmation quotidienne : replanifiée à chaque sync, identifiant
        // STABLE par jour visé → remplacement, jamais de doublon.
        if WakeConfirmationService.shouldSend(plan: plan,
                                              settings: wakeConfirmation,
                                              lastSync: preferences.lastSyncDate,
                                              now: current) {
            if let notification = plan.flatMap({ WakeConfirmationService.notification(plan: $0, now: current, calendar: calendar) }),
               let sendDate = WakeConfirmationService.nextSendDate(
                    minutesFromMidnight: wakeConfirmation.confirmationTimeMinutes,
                    now: current,
                    calendar: calendar) {
                do {
                    try await scheduler.schedule(notification, at: sendDate)
                } catch {
                    lastIssue = "Planification impossible : \(error.localizedDescription)"
                }
            }
        }

        // Règles « événementielles » : déclenchées par les changements détectés.
        let ruleNotifications = NotificationRuleService.notifications(for: rules.rules, changes: changes)
        for notification in ruleNotifications {
            do {
                try await scheduler.schedule(notification, at: nil)
            } catch {
                lastIssue = "Planification impossible : \(error.localizedDescription)"
            }
        }

        // Règles à heure fixe (devoirs demain, résumé notes) : planifiées à
        // l'heure choisie avec le contenu DÉJÀ connu — iOS ne peut pas
        // interroger PRONOTE à cette heure. Identifiant stable par jour d'envoi :
        // la planification suivante remplace au lieu de dupliquer.
        if let homeworkRule = rules.rules.first(where: { $0.kind == .homeworkDueTomorrow }), homeworkRule.isEnabled,
           let sendDate = NotificationRuleService.nextFireDate(minutes: homeworkRule.timeMinutes, now: current, calendar: calendar),
           let message = NotificationRuleService.homeworkDueTomorrowMessage(
                homework: homework,
                now: current,
                calendar: calendar) {
            let notification = WakeNotification.rule(
                "homework",
                subjectKey: WakeNotification.dayKey(sendDate, calendar: calendar),
                title: message.title,
                body: message.body
            )
            try? await scheduler.schedule(notification, at: sendDate)
        }
    }

    // MARK: - Notification de test

    /// Envoie une notification de test. Retourne un message explicite pour l'UI.
    func sendTestNotification() async -> String {
        let status = await scheduler.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            do {
                try await scheduler.schedule(.test(title: "WakeSchool", body: "Notification de test : tout fonctionne."), at: nil)
                lastIssue = nil
                return "Notification de test envoyée. Vérifie ton Centre de notifications iOS."
            } catch {
                lastIssue = "Échec de la planification : \(error.localizedDescription)"
                return "Impossible de planifier la notification : \(error.localizedDescription)"
            }
        case .denied:
            return "Les notifications sont DÉSACTIVÉES pour WakeSchool : la notification de test ne peut pas apparaître. Active-les dans Réglages iOS → WakeSchool → Notifications."
        case .notDetermined:
            let granted = await scheduler.requestAuthorization()
            if granted {
                do {
                    try await scheduler.schedule(.test(title: "WakeSchool", body: "Notification de test : tout fonctionne."), at: nil)
                    return "Autorisation accordée : notification de test envoyée."
                } catch {
                    return "Autorisation accordée mais planification impossible : \(error.localizedDescription)"
                }
            }
            return "Autorisation refusée : la notification de test ne peut pas apparaître. Tu pourras l'activer dans Réglages iOS."
        @unknown default:
            return "État d'autorisation inconnu : la notification de test ne peut pas être envoyée."
        }
    }

    /// Envoie une notification de test dans `delay` secondes (outil de debug).
    func sendTestNotificationAfter(_ delay: TimeInterval) async throws {
        let status = await scheduler.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            throw NotificationTestError.authorizationRequired
        }
        let content = WakeNotification(id: "wake.test.\(Int(Date().timeIntervalSince1970))",
                                       title: "WakeSchool",
                                       body: "Notification de test programmée.",
                                       threadID: "wake",
                                       triggerDelay: max(0.1, delay))
        try await scheduler.schedule(content, at: nil)
    }

    /// Nombre de notifications locales actuellement planifiées (outil de debug).
    func pendingCount() async -> Int {
        await scheduler.pendingIDs().count
    }

    /// Annule UNIQUEMENT les notifications de test (jamais les confirmations,
    /// règles ni autres notifications de l'application).
    func cancelTestNotifications() async {
        let pending = await scheduler.pendingIDs()
        let testIDs = pending.filter { $0 == WakeNotification.Kind.test.prefix || $0.hasPrefix("wake.test.") || $0 == "wake.confirm.debug" }
        scheduler.cancel(ids: testIDs)
    }

    /// Planifie une notification de debug déjà construite (outil de debug).
    func scheduleDebug(_ notification: WakeNotification) async throws {
        try await scheduler.schedule(notification, at: nil)
    }

    enum NotificationTestError: LocalizedError {
        case authorizationRequired

        var errorDescription: String? {
            "L'autorisation de notifications est requise pour envoyer la notification de test."
        }
    }

    // MARK: - Accès centre / règles (pour l'UI)

    var centerStore: NotificationCenterStore { center }
    var rulesStore: NotificationRulesStore { rules }
}