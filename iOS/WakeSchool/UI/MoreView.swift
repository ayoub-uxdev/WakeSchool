import SwiftUI

/// Menu « Plus » : regroupe les accès secondaires (vie scolaire, réveil, réglages).
/// Architecture extensible : ajouter une carte dans `entries` suffit ; les
/// fonctionnalités à venir (Centre de notifications, WakeBot) sont volontairement
/// annoncées mais non cliquables tant qu'elles n'existent pas.
struct MoreView: View {
    @EnvironmentObject private var store: SchoolDataStore

    private enum Destination: Hashable {
        case absences
        case alarm
        case settings
        case notificationCenter
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Accès fonctionnels
                    NavigationLink(value: Destination.absences) {
                        MoreCard(symbol: "person.crop.circle.badge.exclamationmark",
                                 title: "Absences et retards",
                                 subtitle: "Vie scolaire de la période",
                                 tint: .orange)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: Destination.alarm) {
                        MoreCard(symbol: "alarm.fill",
                                 title: "Réveil intelligent",
                                 subtitle: "Réveils synchronisés avec l'emploi du temps",
                                 tint: .blue)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: Destination.settings) {
                        MoreCard(symbol: "gearshape.fill",
                                 title: "Réglages",
                                 subtitle: "Connexion, apparence et données",
                                 tint: .gray)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: Destination.notificationCenter) {
                        MoreCard(symbol: "bell.badge",
                                 title: "Centre de notifications",
                                 subtitle: store.notificationCenter.unreadCount > 0
                                     ? "\(store.notificationCenter.unreadCount) non lue\(store.notificationCenter.unreadCount > 1 ? "s" : "")"
                                     : "Historique des évènements",
                                 tint: .purple)
                    }
                    .buttonStyle(.plain)
                    MoreUpcomingCard(symbol: "bubble.left.and.text.bubble.right",
                                     title: "WakeBot",
                                     subtitle: "Bientôt disponible")
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 20)
            }
            .wakeScreenBackground()
            .navigationTitle("Plus")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .absences: AbsencesView()
                case .alarm: SmartAlarmView()
                case .settings: SettingsView()
                case .notificationCenter: NotificationCenterView(center: store.notificationCenter)
                }
            }
        }
    }
}

// MARK: - Cartes

private struct MoreCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .wakeCard(padding: 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

private struct MoreUpcomingCard: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.5))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()
        }
        .wakeCard(padding: 16)
        .opacity(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). Fonctionnalité à venir.")
    }
}

#Preview {
    MoreView()
        .environmentObject(SchoolDataStore(environment: AppEnvironment.inMemory()))
}
