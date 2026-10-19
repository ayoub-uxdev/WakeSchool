import Foundation
import SwiftUI

/// États de chargement d'une période scolaire dans le calendrier annuel.
enum PeriodLoadState: Equatable {
    case notLoaded
    case loading
    case loaded
    case failed(Error)

    static func == (lhs: PeriodLoadState, rhs: PeriodLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.notLoaded, .notLoaded), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

/// ViewModel du calendrier scolaire annuel.
/// Gère la navigation mensuelle, la sélection de jour et le chargement progressif
/// des périodes PRONOTE via `SchoolSyncService`.
@MainActor
final class AcademicCalendarViewModel: ObservableObject {

    // MARK - État publié

    /// Date actuellement sélectionnée par l'utilisateur.
    @Published private(set) var selectedDate: Date = Date()

    /// Mois actuellement affiché dans la grille.
    @Published private(set) var visibleMonth: Date = Date()

    /// Indique qu'un chargement de période est en cours.
    @Published private(set) var isLoading = false

    /// Message d'erreur affiché en cas d'échec de chargement.
    @Published private(set) var errorMessage: String?

    /// Toutes les périodes scolaires connues (même non encore récupérées).
    @Published private(set) var periods: [SchoolPeriod] = []

    /// État de chargement par identifiant de période.
    @Published private(set) var periodStates: [String: PeriodLoadState] = [:]

    // MARK - Dépendances

    private let dataStore: SchoolDataStore
    private let syncService: SchoolSyncService
    private let calendar: Calendar

    /// Tâches de chargement en cours par identifiant de période.
    private var loadingTasks: [String: Task<Void, Never>] = [:]

    // MARK - Initialisation

    init(
        dataStore: SchoolDataStore,
        syncService: SchoolSyncService,
        calendar: Calendar = .current
    ) {
        self.dataStore = dataStore
        self.syncService = syncService
        self.calendar = calendar
    }

    // MARK - Données dérivées

    /// Cours du jour sélectionné, triés (annulés exclus par défaut).
    var coursesForSelectedDate: [TimetableEntry] {
        ScheduleService.entries(
            on: selectedDate,
            in: dataStore.snapshot.timetable,
            calendar: calendar
        )
    }

    /// True si le jour sélectionné contient au moins un cours.
    var hasCoursesOnSelectedDate: Bool {
        !coursesForSelectedDate.isEmpty
    }

    /// Nombre total de cours connus dans le cache (toutes périodes confondues).
    var totalCachedCourses: Int {
        dataStore.snapshot.timetable.count
    }

    // MARK - Navigation

    /// Sélectionne une date et déclenche le chargement de sa période si nécessaire.
    func selectDate(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        guard day != calendar.startOfDay(for: selectedDate) else { return }
        selectedDate = day
        errorMessage = nil
        loadPeriodForDate(day)
    }

    /// Ramène à aujourd'hui.
    func goToToday() {
        let today = calendar.startOfDay(for: Date())
        selectedDate = today
        visibleMonth = today
        errorMessage = nil
        loadPeriodForDate(today)
    }

    /// Passe au mois précédent.
    func previousMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) else { return }
        visibleMonth = newMonth
    }

    /// Passe au mois suivant.
    func nextMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) else { return }
        visibleMonth = newMonth
    }

    // MARK - Chargement progressif

    /// Charge la période couvrant la date donnée si elle n'est pas déjà chargée ni en cours de chargement.
    /// Si aucune période connue ne couvre la date, une période est construite pour le mois
    /// contenant la date et son chargement est déclenché.
    func loadPeriodForDate(_ date: Date) {
        let day = calendar.startOfDay(for: date)

        // Cherche une période existante couvrant cette date
        if let period = periodForDate(day) {
            if periodStates[period.id] == .loaded { return }
            if periodStates[period.id] == .loading { return }
            loadPeriod(period)
            return
        }

        // Aucune période connue : construire la période du mois et la charger
        let newPeriod = periodForMonthContaining(day)
        periods.append(newPeriod)
        periodStates[newPeriod.id] = .notLoaded
        loadPeriod(newPeriod)
    }

    /// Retourne la période scolaire couvrant la date, ou nil si aucune période connue ne la couvre.
    private func periodForDate(_ date: Date) -> SchoolPeriod? {
        let day = calendar.startOfDay(for: date)
        return periods.first { ($0.startDate...$0.endDate).contains(day) }
    }

    /// Construit une période scolaire couvrant le mois contenant `date`.
    private func periodForMonthContaining(_ date: Date) -> SchoolPeriod {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let startOfMonth = calendar.date(from: components) else {
            return SchoolPeriod(
                id: "calendar-day-\(date.timeIntervalSince1970)",
                title: DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none),
                startDate: date,
                endDate: date,
                isTimetableComplete: false
            )
        }
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? startOfMonth
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfMonth) ?? endOfMonth
        return SchoolPeriod(
            id: "calendar-month-\(components.year!)-\(components.month!)",
            title: monthTitle(for: date),
            startDate: startOfMonth,
            endDate: endOfDay,
            isTimetableComplete: false
        )
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }

    /// Déclenche la récupération PRONOTE pour une période.
    private func loadPeriod(_ period: SchoolPeriod) {
        loadingTasks[period.id]?.cancel()

        periodStates[period.id] = .loading
        isLoading = true
        errorMessage = nil

        let task = Task {
            defer {
                isLoading = false
                loadingTasks[period.id] = nil
            }

            do {
                let entries = try await syncService.syncTimetable(for: period)
                // Même si la période est vide (aucun cours ce mois-ci), on la marque
                // comme chargée pour éviter de la retélécharger indéfiniment.
                periodStates[period.id] = .loaded
            } catch {
                periodStates[period.id] = .failed(error)
                errorMessage = error.localizedDescription
            }
        }

        loadingTasks[period.id] = task
    }

    /// Rafraîchit la liste des périodes connues depuis le stockage local.
    func refreshPeriods() throws {
        periods = try dataStore.repository.loadPeriods()
        for period in periods where periodStates[period.id] == nil {
            periodStates[period.id] = .notLoaded
        }
    }
}

// MARK: - Convenience pour les tests

extension AcademicCalendarViewModel {
    /// Force la liste des périodes connues (utilisé par les tests et l'initialisation).
    func setPeriods(_ periods: [SchoolPeriod]) {
        self.periods = periods
        for period in periods where periodStates[period.id] == nil {
            periodStates[period.id] = .notLoaded
        }
    }
}
