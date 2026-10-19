import SwiftUI
import WidgetKit

/// Vue du widget « Prochain cours » pour systemSmall et systemMedium.
struct WidgetEntryView: View {
    let entry: WidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .hasNextCourse(let course):
                if course.isCancelled {
                    CancelledCourseView(course: course)
                } else {
                    CourseView(course: course)
                }
            case .syncedNoFutureCourses:
                NoFutureCoursesView()
            case .neverSynced:
                NeverSyncedView()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        // Toucher le widget ouvre l'application sur l'emploi du temps.
        .widgetURL(URL(string: "wakeschool://widget/next-lesson")!)
    }
}

// MARK: - Cours normal

private struct CourseView: View {
    let course: WidgetCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            details
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(WakeWidgetTheme.accent.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WakeWidgetTheme.accent)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(course.subjectName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let teacher = course.teacherName {
                    Text(teacher)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WakeWidgetTheme.accent)
                Text(DateLabels.time(course.startDate))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if let room = course.room, !room.isEmpty {
                    Spacer(minLength: 8)
                    Image(systemName: "location")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WakeWidgetTheme.accent)
                    Text(room)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Text(DateLabels.relativeDay(course.startDate, now: Date()))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Cours annulé

private struct CancelledCourseView: View {
    let course: WidgetCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.red)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.subjectName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Annulé")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 8)
            }
            if let room = course.room, !room.isEmpty {
                Label(room, systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Aucun cours futur connu (synchronisation effectuée)

private struct NoFutureCoursesView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text("Aucun cours à venir")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Vos cours terminés n'apparaissent pas ici.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

// MARK: - Données jamais synchronisées

private struct NeverSyncedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text("Aucune donnée synchronisée")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Ouvrez WakeSchool pour synchroniser votre emploi du temps.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

// MARK: - Thème widget

enum WakeWidgetTheme {
    static let accent = Color(red: 0.66, green: 0.58, blue: 1.0)
}

// MARK: - Prévisualisations

#Preview("systemSmall - Cours") {
    WidgetEntryView(entry: WidgetEntry(
        date: Date(),
        state: .hasNextCourse(WidgetCourse(
            subjectName: "Mathématiques",
            teacherName: "M. Martin",
            room: "B204",
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(4500),
            isCancelled: false
        ))
    ))
    .previewContext(WidgetPreviewContext(family: .systemSmall))
}

#Preview("systemMedium - Cours") {
    WidgetEntryView(entry: WidgetEntry(
        date: Date(),
        state: .hasNextCourse(WidgetCourse(
            subjectName: "Physique-Chimie",
            teacherName: "Mme Bernard",
            room: "Labo 2",
            startDate: Date().addingTimeInterval(7200),
            endDate: Date().addingTimeInterval(8100),
            isCancelled: false
        ))
    ))
    .previewContext(WidgetPreviewContext(family: .systemMedium))
}

#Preview("systemSmall - Annulé") {
    WidgetEntryView(entry: WidgetEntry(
        date: Date(),
        state: .hasNextCourse(WidgetCourse(
            subjectName: "Français",
            teacherName: "Mme Dubois",
            room: "A110",
            startDate: Date().addingTimeInterval(3600),
            endDate: Date().addingTimeInterval(4500),
            isCancelled: true
        ))
    ))
    .previewContext(WidgetPreviewContext(family: .systemSmall))
}

#Preview("systemSmall - Jamais synchronisé") {
    WidgetEntryView(entry: .placeholder)
        .previewContext(WidgetPreviewContext(family: .systemSmall))
}

#Preview("systemSmall - Aucun cours futur") {
    WidgetEntryView(entry: WidgetEntry(
        date: Date(),
        state: .syncedNoFutureCourses
    ))
    .previewContext(WidgetPreviewContext(family: .systemSmall))
}

