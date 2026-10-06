import SwiftUI

/// Écran « Réveil intelligent » : affiche, avec des données de démonstration,
/// l'heure de départ et l'heure de réveil recommandées par `WakeTimeCalculator`.
/// Aucune alarme n'est programmée à cette étape.
struct SmartAlarmView: View {
    private let outcome: Result<WakeTimeRecommendation, Error>

    init(day: Date = Date(), calendar: Calendar = .current) {
        self.outcome = SmartAlarmDemo.recommendation(for: day, calendar: calendar)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.9), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    switch outcome {
                    case .success(let recommendation):
                        heroCard(recommendation)
                        timelineCard(recommendation)
                    case .failure(let error):
                        errorCard(error)
                    }

                    parametersCard
                    scheduleSection
                }
                .padding(20)
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "alarm.waves.left.and.right")
                .font(.system(size: 40))
            Text("Réveil intelligent")
                .font(.largeTitle.bold())
            Text("Données de démonstration")
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
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Paramètres")
                    .font(.headline)
                InfoRow(symbol: "bus.fill", title: "Temps de trajet",
                        value: "\(SmartAlarmDemo.travelMinutes) min", tint: .blue)
                InfoRow(symbol: "hourglass", title: "Temps de préparation",
                        value: "\(SmartAlarmDemo.preparationMinutes) min", tint: .purple)
                InfoRow(symbol: "shield.fill", title: "Marge de sécurité",
                        value: "\(SmartAlarmDemo.safetyMarginMinutes) min", tint: .pink)
            }
        }
    }

    private func errorCard(_ error: Error) -> some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.yellow)
                Text("Calcul impossible")
                    .font(.headline)
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var scheduleSection: some View {
        VStack(spacing: 8) {
            Button {
                // Volontairement vide : la programmation réelle de l'alarme
                // (AlarmManager) sera ajoutée dans une tâche dédiée.
            } label: {
                Label("Programmer ce réveil", systemImage: "alarm.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
            .disabled(true)

            Text("La programmation de l'alarme n'est pas encore disponible.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Formatage

    /// Heure au format HH:mm.
    private static func timeString(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
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

#Preview { SmartAlarmView() }