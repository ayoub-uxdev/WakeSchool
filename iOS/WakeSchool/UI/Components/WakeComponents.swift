import SwiftUI

struct WakeSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .tint(WakeTheme.accent)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct WakeBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.18)))
    }
}

struct StatTile: View {
    let symbol: String
    let value: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.18)))
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .wakeCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(WakeTheme.accent)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .wakeCard(padding: 22)
        .accessibilityElement(children: .combine)
    }
}

struct SubjectLabel: View {
    let subject: Subject

    var body: some View {
        let tint = WakeTheme.color(for: subject)
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(subject.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

/// Ligne de cours : horaires, matière, professeur, salle, statut (annulé / modifié).
struct CourseRow: View {
    let entry: TimetableEntry
    var showsDay: Bool = false

    private var tint: Color { WakeTheme.color(for: entry.subject) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            timeColumn
            Capsule()
                .fill(entry.isCancelled ? Color.red.opacity(0.7) : tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.subject.name)
                        .font(.headline)
                        .strikethrough(entry.isCancelled)
                    Spacer(minLength: 8)
                    statusBadge
                }
                details
                if let note = entry.changeNote, entry.status != .normal {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(entry.isCancelled ? Color.red.opacity(0.9) : Color.orange)
                }
            }
        }
        .opacity(entry.isCancelled ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsDay {
                Text(DateLabels.weekdayShort(entry.start) + " " + DateLabels.dayNumber(entry.start))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WakeTheme.accent)
            }
            Text(DateLabels.time(entry.start))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(DateLabels.time(entry.end))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 52, alignment: .leading)
    }

    private var details: some View {
        HStack(spacing: 12) {
            if let teacher = entry.teacher {
                Label(teacher.name, systemImage: "person.fill")
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let room = entry.room {
                Label(room, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(entry.isModified ? Color.orange : Color.white.opacity(0.7))
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch entry.status {
        case .cancelled:
            WakeBadge(text: "Annulé", systemImage: "xmark.circle.fill", tint: .red)
        case .modified:
            WakeBadge(text: "Modifié", systemImage: "arrow.triangle.2.circlepath", tint: .orange)
        case .normal:
            EmptyView()
        }
    }
}

/// Ligne de devoir avec case à cocher.
struct HomeworkRow: View {
    let homework: Homework
    let now: Date
    let onToggle: (Bool) -> Void

    private var isOverdue: Bool { !homework.isDone && homework.dueDate < now }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.snappy) { onToggle(!homework.isDone) }
            } label: {
                Image(systemName: homework.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(homework.isDone ? Color.green : Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(homework.isDone ? "Marquer comme non terminé" : "Marquer comme terminé")

            VStack(alignment: .leading, spacing: 5) {
                SubjectLabel(subject: homework.subject)
                Text(homework.title)
                    .font(.headline)
                    .strikethrough(homework.isDone)
                if !homework.details.isEmpty {
                    Text(homework.details)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label(dueText, systemImage: isOverdue ? "exclamationmark.circle.fill" : "calendar")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isOverdue ? Color.red : Color.white.opacity(0.7))
                    priorityBadge
                }
            }
            .opacity(homework.isDone ? 0.55 : 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var dueText: String {
        let day = DateLabels.relativeDay(homework.dueDate, now: now)
        let time = DateLabels.time(homework.dueDate)
        return isOverdue ? "Était à rendre \(day)" : "Pour \(day) · \(time)"
    }

    @ViewBuilder
    private var priorityBadge: some View {
        switch homework.priority {
        case .high:
            WakeBadge(text: "Priorité haute", systemImage: "flame.fill", tint: .red)
        case .low:
            WakeBadge(text: "Basse", systemImage: "arrow.down", tint: .gray)
        case .normal:
            EmptyView()
        }
    }
}

struct ExamRow: View {
    let exam: Exam
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.body.weight(.semibold))
                .foregroundStyle(WakeTheme.color(for: exam.subject))
                .frame(width: 36, height: 36)
                .background(Circle().fill(WakeTheme.color(for: exam.subject).opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(exam.title).font(.headline)
                SubjectLabel(subject: exam.subject)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(DateLabels.capitalizedFirst(DateLabels.relativeDay(exam.date, now: now)))
                    .font(.subheadline.weight(.semibold))
                Text(DateLabels.time(exam.date))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
