import SwiftUI

/// Cellule d'un jour dans le calendrier mensuel.
struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let hasCourses: Bool
    let courseStatus: CourseStatus?

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 4) {
            Text(calendar.dayNumber(from: date))
                .font(.title3.weight(.bold))
                .foregroundStyle(foregroundColor)
                .monospacedDigit()

            if hasCourses {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 44, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? WakeTheme.accent.opacity(0.35) : Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? WakeTheme.accent : Color.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityLabel(DateLabels.dayTitle(date, calendar: calendar))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foregroundColor: Color {
        isSelected ? .white : (hasCourses ? .white : Color.white.opacity(0.45))
    }

    private var indicatorColor: Color {
        switch courseStatus {
        case .cancelled: return .red
        case .modified: return .orange
        case .normal, .none: return WakeTheme.accent
        }
    }
}

// MARK: - Convenience Calendar

private extension Calendar {
    func dayNumber(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = self
        formatter.timeZone = self.timeZone
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}
