import SwiftUI

/// Devoirs : en retard, à venir, terminés. L'état « terminé » est persisté par le store.
struct HomeworkView: View {
    @EnvironmentObject private var store: SchoolDataStore

    var body: some View {
        NavigationStack {
            let now = Date()
            let sections = HomeworkOverviewService.sections(from: store.snapshot.homework, now: now)

            ScrollView {
                VStack(spacing: 22) {
                    if sections.isEmpty {
                        EmptyStateCard(symbol: "checkmark.seal.fill",
                                       title: "Aucun devoir",
                                       message: "Tout est à jour. Tire vers le bas pour synchroniser.")
                    } else {
                        progressCard(sections)
                        section("En retard", icon: "exclamationmark.triangle.fill", tint: .red,
                                items: sections.overdue, now: now)
                        section("À venir", icon: "calendar", tint: WakeTheme.accent,
                                items: sections.upcoming, now: now)
                        section("Terminés", icon: "checkmark.circle.fill", tint: .green,
                                items: sections.done, now: now)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .animation(.snappy, value: sections)
            }
            .refreshable { await store.refresh() }
            .wakeScreenBackground()
            .navigationTitle("Devoirs")
        }
    }

    private func progressCard(_ sections: HomeworkSections) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(sections.done.count) sur \(sections.total) terminés")
                    .font(.headline)
                Spacer()
                Text("\(Int((sections.completion * 100).rounded())) %")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(WakeTheme.accent)
            }
            ProgressView(value: sections.completion)
                .tint(WakeTheme.accent)
        }
        .wakeCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, tint: Color,
                         items: [Homework], now: Date) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                VStack(spacing: 14) {
                    ForEach(items) { item in
                        HomeworkRow(homework: item, now: now) { done in
                            store.setHomework(item.id, done: done)
                        }
                        if item.id != items.last?.id {
                            Divider().overlay(Color.white.opacity(0.1))
                        }
                    }
                }
                .wakeCard()
            }
        }
    }
}
