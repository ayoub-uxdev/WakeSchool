import SwiftUI

/// Règles de notifications personnalisées : première version simple et
/// extensible. Chaque règle est activable/désactivable et configurable.
/// Une règle à heure fixe planifie une notification À L'AVANCE à partir des
/// informations DÉJÀ connues de WakeSchool — iOS ne garantit pas une
/// exécution en arrière-plan à une heure exacte, et ne peut pas interroger
/// PRONOTE spontanément.
struct NotificationRulesView: View {
    @ObservedObject var rules: NotificationRulesStore
    let onTest: () async -> String

    @State private var testResult: String?
    @State private var explanationShown = false
    @State private var authorizationExplained = false

    var body: some View {
        Form {
            explanationSection
            rulesSection
            testSection
        }
        .navigationTitle("Règles de notifications")
        .navigationBarTitleDisplayMode(.inline)
        .tint(WakeTheme.accent)
        .sheet(isPresented: $explanationShown) {
            PermissionExplainerSheet(explained: $authorizationExplained)
        }
    }

    // MARK: - Explication préalable (autorisation contextuelle)

    private var explanationSection: some View {
        Section {
            Label {
                Text("Ces règles créent des notifications locales à partir des données déjà synchronisées dans WakeSchool. Elles ne consultent pas PRONOTE en arrière-plan.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.footnote)
        } footer: {
            Text("Une notification système est demandée à l'activation de la première règle.")
        }
    }

    private var rulesSection: some View {
        Section("Mes règles") {
            ForEach(NotificationRuleKind.allCases) { kind in
                let rule = rules.rule(for: kind)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in
                            // Autorisation demandée au moment où l'utilisateur active une règle.
                            if enabled && !authorizationExplained {
                                explanationShown = true
                            }
                            rules.setEnabled(enabled, for: kind)
                        })) {
                        Label(kind.displayName, systemImage: kind.systemImage)
                    }
                    if rule.isEnabled && kind.needsTime {
                        Picker("Heure", selection: Binding(
                            get: { rule.timeMinutes },
                            set: { rules.setTime(minutes: $0, for: kind) })) {
                            ForEach(timeChoices, id: \.minutes) { choice in
                                Text(choice.label).tag(choice.minutes)
                            }
                        }
                    }
                }
            }
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task { testResult = await onTest() }
            } label: {
                Label("Envoyer une notification de test", systemImage: "paperplane.fill")
            }
            if let testResult {
                Text(testResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("La notification de test utilise le même canal que les autres notifications : si elle apparaît, les autres aussi.")
        }
    }

    private var timeChoices: [(minutes: Int, label: String)] {
        let hours = [7, 12, 17, 18, 19, 20, 21]
        return hours.map { (minutes: $0 * 60, label: String(format: "%02d:00", $0)) }
    }
}

/// Fenêtre d'explication AVANT la demande d'autorisation système.
struct PermissionExplainerSheet: View {
    @Binding var explained: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundStyle(WakeTheme.accent)
            Text("Autoriser les notifications ?")
                .font(.title2.bold())
            Text("WakeSchool t'avertit des nouveaux contrôles et notes, te rappelle les devoirs à rendre et te propose ton réveil la veille. Ces notifications viennent uniquement des données déjà synchronisées.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                explained = true
                dismiss()
            } label: {
                Text("Compris, continuer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
    }
}
