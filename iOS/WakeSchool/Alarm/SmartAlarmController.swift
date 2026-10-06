import Foundation

/// Problème à afficher à l'utilisateur après une action sur l'alarme.
enum SmartAlarmIssue: Equatable {
    /// L'utilisateur a refusé (ou n'a pas accordé) l'autorisation AlarmKit.
    case permissionDenied
    case message(String)
}

/// Logique de l'écran « Réveil intelligent » autour d'AlarmKit.
/// Ne calcule jamais l'heure du réveil (c'est `WakeTimeCalculator`) et ne parle à AlarmKit
/// que via `AlarmScheduling`. Aucune autorisation n'est demandée avant `schedule`.
@MainActor
final class SmartAlarmController: ObservableObject {
    @Published private(set) var scheduledAlarm: ScheduledAlarm?
    @Published private(set) var isWorking = false
    @Published private(set) var issue: SmartAlarmIssue?

    private let scheduler: AlarmScheduling
    private let store: ScheduledAlarmStoring
    private let now: () -> Date

    init(scheduler: AlarmScheduling,
         store: ScheduledAlarmStoring,
         now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.store = store
        self.now = now
        self.scheduledAlarm = store.current
    }

    static func live() -> SmartAlarmController {
        SmartAlarmController(scheduler: AlarmManager.shared,
                             store: UserDefaultsScheduledAlarmStore())
    }

    // MARK: - Recommandation

    /// Réveil recommandé à partir de l'emploi du temps réel. Calcul délégué à `DashboardService`
    /// puis `WakeTimeCalculator`.
    static func recommendation(entries: [TimetableEntry],
                               now: Date,
                               settings: WakeSettings,
                               calendar: Calendar = .current) -> WakeTimeRecommendation? {
        DashboardService.nextWake(entries: entries, now: now, settings: settings, calendar: calendar)
    }

    /// Date à programmer, ou l'erreur qui empêche de programmer (pas de réveil, heure passée).
    static func validate(_ recommendation: WakeTimeRecommendation?, now: Date) -> Result<Date, Error> {
        guard let recommendation else { return .failure(WakeTimeError.noCourse) }
        guard recommendation.wakeTime > now else { return .failure(AlarmError.dateInPast) }
        return .success(recommendation.wakeTime)
    }

    // MARK: - Actions

    func schedule(_ recommendation: WakeTimeRecommendation?) async {
        guard !isWorking else { return }
        issue = nil

        let fireDate: Date
        switch Self.validate(recommendation, now: now()) {
        case .failure(let error):
            issue = .message(error.localizedDescription)
            return
        case .success(let date):
            fireDate = date
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let id = try await scheduler.schedule(at: fireDate)
            // Remplacement : l'ancienne alarme n'est annulée qu'une fois la nouvelle programmée.
            if let previous = scheduledAlarm, previous.id != id {
                try? scheduler.cancel(id: previous.id)
            }
            let alarm = ScheduledAlarm(id: id, fireDate: fireDate)
            store.current = alarm
            scheduledAlarm = alarm
        } catch AlarmError.notAuthorized {
            issue = .permissionDenied
        } catch {
            issue = .message(error.localizedDescription)
        }
    }

    func cancel() {
        guard let alarm = scheduledAlarm else { return }
        issue = nil
        do {
            try scheduler.cancel(id: alarm.id)
            clear()
        } catch {
            // Si le système ne connaît déjà plus l'alarme (sonnée, supprimée), l'objectif est atteint.
            if (try? scheduler.isScheduled(id: alarm.id)) == false {
                clear()
            } else {
                issue = .message(error.localizedDescription)
            }
        }
    }

    /// Resynchronise l'état affiché avec le système (alarme sonnée ou supprimée dans l'app Horloge).
    /// En cas d'erreur de lecture, l'état actuel est conservé.
    func refresh() {
        guard let alarm = scheduledAlarm else { return }
        do {
            if try !scheduler.isScheduled(id: alarm.id) { clear() }
        } catch {
            return
        }
    }

    func dismissIssue() { issue = nil }

    private func clear() {
        store.current = nil
        scheduledAlarm = nil
    }
}
