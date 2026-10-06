import SwiftUI
import UIKit

/// Écran « Réveil intelligent » : affiche le réveil recommandé par `WakeTimeCalculator`
/// (à partir de l'emploi du temps du store) et le programme comme alarme système via AlarmKit.
/// L'autorisation n'est demandée que lorsque l'utilisateur appuie sur « Programmer ce réveil ».
@MainActor
struct SmartAlarmView: View {
    @EnvironmentObject private var store: SchoolDataStore
    @StateObject private var controller = SmartAlarmController.live()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        let now = Date()
        let recommendation = SmartAlarmController.recommendation(entries: store.snapshot.timetable,
                                                                 now: now,
                                                                 settings: store.wakeSettings)
        let validation = SmartAlarmController.validate(recommendation, now: now)

        ZStack {
            WakeTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    if let recommendation {
                        heroCard(recommendation)
                        timelineCard(recommendation)
                    }
                    if case .failure(let error) = validation {
                        errorCard(error)
                    }

                    parametersCard
                    scheduleSection(recommendation: recommendation, validation: validation)
                }
                .padding(20)
            }
        }
        .foregroundStyle(.white)
        .task { controller.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.refresh() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "alarm.waves.left.and.right")
                .font(.system(size: 40))
            Text("Réveil intelligent")
                .font(.largeTitle.bold())
            Text(store.dataSource == .demo ? "Données de démonstration" : "Données de l'établissement")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.15)))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func heroCard(_ recommendation: WakeTimeRecommendation) -> some View {
        let leadMinutes = Int((recommendation.totalLeadTime / 60).rounded())
        return Card {
            VStack(spacing: 6) {
                Text("RÉVEIL RECOMMANDÉ")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.7))
                Text(Self.timeString(recommendation.wakeTime))
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(Self.dayString(recommendation.wakeTime))
                    .font(.subheadline.weight(.semibold))
                Text("\(leadMinutes) min avant le premier cours")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func timelineCard(_ recommendation: WakeTimeRecommendation) -> some View {
        Card {
            VStack(spacing: 14) {
                InfoRow(symbol: "alarm.fill", title: "Réveil",
                        value: Self.timeString(recommendation.wakeTime), tint: .orange)
                InfoRow(symbol: "figure.walk", title: "Départ",
                        value: Self.timeString(recommendation.departureTime), tint: .mint)
                InfoRow(symbol: "graduationcap.fill", title: "Premier cours",
                        value: Self.timeString(recommendation.firstClassStart), tint: .cyan)
            }
        }
    }

    private var parametersCard: some View {
        let settings = store.wakeSettings
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Paramètres")
                    .font(.headline)
                InfoRow(symbol: "bus.fill", title: "Temps de trajet",
                        value: "\(settings.travelMinutes) min", tint: .blue)
                InfoRow(symbol: "hourglass", title: "Temps de préparation",
                        value: "\(settings.preparationMinutes) min", tint: .purple)
                InfoRow(symbol: "shield.fill", title: "Marge de sécurité",
                        value: "\(settings.safetyMarginMinutes) min", tint: .pink)
            }
        }
    }

    private func errorCard(_ error: Error) -> some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.yellow)
                Text("Réveil indisponible")
                    .font(.headline)
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scheduleSection(recommendation: WakeTimeRecommendation?,
                                 validation: Result<Date, Error>) -> some View {
        let canSchedule: Bool = {
            if case .success = validation { return true }
            return false
        }()
        let alreadyScheduledForThisTime = controller.scheduledAlarm?.fireDate == recommendation?.wakeTime

        return VStack(spacing: 14) {
            if let alarm = controller.scheduledAlarm {
                scheduledCard(alarm)
            }
            if let issue = controller.issue {
                issueCard(issue)
            }

            if !alreadyScheduledForThisTime {
                Button {
                    Task { await controller.schedule(recommendation) }
                } label: {
                    HStack {
                        if controller.isWorking { ProgressView().tint(.white) }
                        Label(controller.scheduledAlarm == nil ? "Programmer ce réveil" : "Reprogrammer ce réveil",
                              systemImage: "alarm.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
                .disabled(!canSchedule || controller.isWorking)
            }
        }
    }

    private func scheduledCard(_ alarm: ScheduledAlarm) -> some View {
        Card {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Réveil programmé")
                            .font(.headline)
                        Text("\(Self.dayString(alarm.fireDate)) à \(Self.timeString(alarm.fireDate))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                }
                Button(role: .destructive) {
                    controller.cancel()
                } label: {
                    Label("Annuler le réveil", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func issueCard(_ issue: SmartAlarmIssue) -> some View {
        Card {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.yellow)
                switch issue {
                case .permissionDenied:
                    Text(AlarmError.notAuthorized.localizedDescription)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Ouvrir les Réglages", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(.bordered)
                case .message(let text):
                    Text(text)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Formatage

    /// Heure au format HH:mm.
    private static func timeString(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private static func dayString(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

// MARK: - Composants

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct InfoRow: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tint.opacity(0.18)))
            Text(title)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
