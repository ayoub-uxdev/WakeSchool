import SwiftUI

/// Centre de notifications WakeSchool : historique des évènements utiles
/// (réveils, changements d'emploi du temps, nouvelles notes/DS, règles).
/// Consultable depuis l'onglet « Plus ». État lu/non lu et persistance locale.
struct NotificationCenterView: View {
    @ObservedObject var center: NotificationCenterStore

    var body: some View {
        Group {
            if center.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { center.markAllRead() }
        .toolbar {
            if !center.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        center.clear()
                    } label: {
                        Label("Tout effacer", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.35))
            Text("Aucune notification")
                .font(.headline)
            Text("Les réveils proposés, les changements d'emploi du temps, les nouvelles notes et contrôles apparaîtront ici.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .wakeScreenBackground()
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(center.items) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .wakeScreenBackground()
    }

    private func row(_ item: NotificationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(for: item.kind))
                .font(.body.weight(.semibold))
                .foregroundStyle(tint(for: item.kind))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11).fill(tint(for: item.kind).opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !item.isRead {
                        Circle().fill(WakeTheme.accent).frame(width: 8, height: 8)
                    }
                    Text(item.title)
                        .font(.headline)
                }
                Text(item.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                Text(DateLabels.dayTitle(item.date) + " à " + DateLabels.time(item.date))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .wakeCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.message). \(item.isRead ? "Lue" : "Non lue").")
    }

    private func symbol(for kind: NotificationItem.Kind) -> String {
        switch kind {
        case .wakeProposed: return "alarm"
        case .wakeConfirmed: return "alarm.fill"
        case .timetableChange: return "arrow.triangle.2.circlepath"
        case .newExam: return "checklist"
        case .newGrade: return "chart.bar.fill"
        case .rule: return "sparkles"
        }
    }

    private func tint(for kind: NotificationItem.Kind) -> Color {
        switch kind {
        case .wakeProposed, .wakeConfirmed: return .orange
        case .timetableChange: return .mint
        case .newExam: return .cyan
        case .newGrade: return .purple
        case .rule: return .pink
        }
    }
}
