import SwiftUI

/// Identité visuelle de WakeSchool : dégradé indigo -> noir, cartes translucides arrondies.
enum WakeTheme {
    static let accent = Color(red: 0.66, green: 0.58, blue: 1.0)
    static let cornerRadius: CGFloat = 22

    static var background: LinearGradient {
        LinearGradient(colors: [Color.indigo.opacity(0.9), Color.black],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static let subjectPalette: [Color] = [.blue, .pink, .orange, .mint, .purple, .teal, .yellow]

    /// Couleur stable d'une matière (dérivée de son identifiant).
    static func color(for subject: Subject) -> Color {
        subjectPalette[Int(subject.id.uuid.15) % subjectPalette.count]
    }

    static func color(for level: GradeLevel) -> Color {
        switch level {
        case .excellent: return .mint
        case .good: return .cyan
        case .average: return .yellow
        case .low: return .orange
        }
    }
}

struct WakeCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WakeTheme.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: WakeTheme.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

extension View {
    /// Carte arrondie translucide, identique à celle de l'écran Réveil.
    func wakeCard(padding: CGFloat = 18) -> some View {
        modifier(WakeCardModifier(padding: padding))
    }

    /// Fond dégradé de l'application.
    func wakeScreenBackground() -> some View {
        background { WakeTheme.background.ignoresSafeArea() }
    }
}

enum WakeFormat {
    /// Nombre au format français (virgule), `minFraction`...`maxFraction` décimales.
    static func number(_ value: Double, minFraction: Int = 0, maxFraction: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = minFraction
        formatter.maximumFractionDigits = maxFraction
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Moyenne : toujours une décimale.
    static func average(_ value: Double) -> String {
        number(value, minFraction: 1, maxFraction: 1)
    }
}
