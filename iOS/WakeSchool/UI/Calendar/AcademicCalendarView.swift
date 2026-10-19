import SwiftUI

/// Calendrier scolaire annuel : navigation mensuelle, sélection de jour,
/// chargement progressif des périodes PRONOTE et affichage des cours par jour.
struct AcademicCalendarView: View {
    @EnvironmentObject private var dataStore: SchoolDataStore
    @StateObject private var viewModel: AcademicCalendarViewModel

    init(dataStore: SchoolDataStore) {
        _viewModel = StateObject(wrappedValue: AcademicCalendarViewModel(
            dataStore: dataStore,
            syncService: dataStore.syncService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                monthGrid
                if viewModel.hasCoursesOnSelectedDate {
                    dayCoursesSection
                } else if viewModel.isLoading {
                    loadingSection
                } else if let error = viewModel.errorMessage {
                    errorSection(message: error)
                } else {
                    emptySection
                }
            }
            .wakeScreenBackground()
            .navigationTitle("Calendrier scolaire")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aujourd'hui") {
                        withAnimation(.snappy) { viewModel.goToToday() }
                    }
                    .disabled(isTodaySelected)
                }
            }
            .onAppear {
                loadInitialPeriods()
            }
        }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    withAnimation(.snappy) { viewModel.previousMonth() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WakeTheme.accent)
                }

                Spacer()

                Text(monthYearTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    withAnimation(.snappy) { viewModel.nextMonth() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WakeTheme.accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Divider()
                .background(Color.white.opacity(0.12))
        }
        .background(
            RoundedRectangle(cornerRadius: WakeTheme.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var monthYearTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: viewModel.visibleMonth).capitalized
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDate(viewModel.selectedDate, inSameDayAs: Date())
    }

    // MARK: - Grille mensuelle

    private var monthGrid: some View {
        CalendarMonthView(
            month: viewModel.visibleMonth,
            selectedDate: viewModel.selectedDate,
            coursesByDay: coursesByDay,
            onDateSelected: { viewModel.selectDate($0) }
        )
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// Cours par jour (clé = date au début de journée).
    private var coursesByDay: [Date: [TimetableEntry]] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: dataStore.snapshot.timetable) { entry in
            calendar.startOfDay(for: entry.start)
        }
        return groups
    }

    // MARK: - Cours du jour sélectionné

    private var dayCoursesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(DateLabels.dayTitle(viewModel.selectedDate, calendar: Calendar.current))
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ForEach(viewModel.coursesForSelectedDate) { entry in
                CourseRow(entry: entry)
                    .wakeCard(padding: 14)
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - États

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Chargement des cours…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorSection(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Réessayer") {
                viewModel.clearError()
                viewModel.loadPeriodForDate(viewModel.selectedDate)
            }
            .buttonStyle(.borderedProminent)
            .tint(WakeTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySection: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))
            Text("Aucun cours ce jour")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Text("Sélectionnez un autre jour ou tirez vers le bas pour synchroniser.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Initialisation

    private func loadInitialPeriods() {
        do {
            try viewModel.refreshPeriods()
        } catch {
            viewModel.setError(error.localizedDescription)
        }
        viewModel.loadPeriodForDate(viewModel.selectedDate)
    }
}

