import SwiftUI

/// Emploi du temps par jour : sélecteur de jour, cours triés, annulations et modifications visibles.
struct TimetableView: View {
    @EnvironmentObject private var store: SchoolDataStore
    @State private var selection: Date?

    var body: some View {
        NavigationStack {
            let calendar = Calendar.current
            let days = ScheduleDayService.days(from: store.snapshot.timetable, calendar: calendar)
            let current = effectiveDay(in: days, calendar: calendar)

            VStack(spacing: 16) {
                if days.isEmpty {
                    EmptyStateCard(symbol: "calendar.badge.exclamationmark",
                                   title: "Aucun cours",
                                   message: "L'emploi du temps est vide. Tire vers le bas pour synchroniser.")
                        .padding(.horizontal, 20)
                    Spacer()
                } else {
                    daySelector(days, current: current)
                    ScrollView {
                        if let current = current {
                            dayContent(current, calendar: calendar)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 28)
                        }
                    }
                    .refreshable { await store.refresh() }
                }
            }
            .padding(.top, 8)
            .wakeScreenBackground()
            .navigationTitle("Emploi du temps")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aujourd'hui") { withAnimation(.snappy) { selection = nil } }
                        .disabled(days.isEmpty)
                }
            }
        }
    }

    private func effectiveDay(in days: [ScheduleDay], calendar: Calendar) -> ScheduleDay? {
        if let selection = selection, let match = days.first(where: { $0.date == selection }) {
            return match
        }
        return ScheduleDayService.defaultDay(in: days, now: Date(), calendar: calendar)
    }

    // MARK: - Sélecteur de jour

    private func daySelector(_ days: [ScheduleDay], current: ScheduleDay?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(days) { day in
                        chip(day, isSelected: day.date == current?.date)
                            .id(day.date)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                if let current = current { proxy.scrollTo(current.date, anchor: .center) }
            }
            .onChange(of: current?.date) { _, newValue in
                if let newValue = newValue {
                    withAnimation(.snappy) { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }

    private func chip(_ day: ScheduleDay, isSelected: Bool) -> some View {
        Button {
            withAnimation(.snappy) { selection = day.date }
        } label: {
            VStack(spacing: 4) {
                Text(DateLabels.weekdayShort(day.date).uppercased())
                    .font(.caption2.weight(.semibold))
                Text(DateLabels.dayNumber(day.date))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Circle()
                    .fill(indicatorColor(day))
                    .frame(width: 6, height: 6)
            }
            .frame(width: 54)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? WakeTheme.accent.opacity(0.35) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? WakeTheme.accent : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DateLabels.dayTitle(day.date))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Rouge s'il y a une annulation, orange s'il y a une modification, sinon transparent.
    private func indicatorColor(_ day: ScheduleDay) -> Color {
        if day.cancelledCount > 0 { return .red }
        if day.modifiedCount > 0 { return .orange }
        return .clear
    }

    // MARK: - Contenu du jour

    private func dayContent(_ day: ScheduleDay, calendar: Calendar) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateLabels.capitalizedFirst(DateLabels.dayTitle(day.date, calendar: calendar)))
                    .font(.title2.bold())
                Text(ScheduleDayService.summaryLine(for: day, calendar: calendar))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            ForEach(day.entries) { entry in
                CourseRow(entry: entry)
                    .wakeCard(padding: 14)
            }
        }
        .id(day.date)
        .transition(.opacity)
    }
}
