import SwiftUI

/// Notes : moyenne générale, moyennes par matière, dernières notes, contrôles à venir.
struct GradesView: View {
    @EnvironmentObject private var store: SchoolDataStore

    var body: some View {
        NavigationStack {
            let snapshot = store.snapshot
            let now = Date()
            let general = AverageCalculator.generalAverage(of: snapshot.averages)
            let grades = AverageCalculator.recentGrades(snapshot.grades, limit: snapshot.grades.count)
            let exams = ExamService.upcoming(snapshot.exams, now: now, withinDays: 60)

            ScrollView {
                VStack(spacing: 22) {
                    if snapshot.grades.isEmpty && snapshot.averages.isEmpty {
                        EmptyStateCard(symbol: "chart.bar.xaxis",
                                       title: "Aucune note",
                                       message: "Les notes apparaîtront ici après la synchronisation.")
                    } else {
                        generalCard(general)
                        averagesSection(snapshot.averages)
                        gradesSection(grades)
                    }
                    examsSection(exams, now: now)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .refreshable { await store.refresh() }
            .wakeScreenBackground()
            .navigationTitle("Notes")
        }
    }

    // MARK: - Moyenne générale

    @ViewBuilder
    private func generalCard(_ general: Double?) -> some View {
        if let general = general {
            let level = GradeLevel(value: general)
            let tint = WakeTheme.color(for: level)
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(general / 20, 0), 1)))
                        .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(WakeFormat.average(general))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("/ 20")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 6) {
                    Text("MOYENNE GÉNÉRALE")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))
                    WakeBadge(text: level.label, systemImage: "star.fill", tint: tint)
                    Text("Moyenne des matières")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .wakeCard()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Moyennes par matière

    @ViewBuilder
    private func averagesSection(_ averages: [SubjectAverage]) -> some View {
        if !averages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WakeSectionHeader(title: "Par matière")
                VStack(spacing: 16) {
                    ForEach(averages) { item in
                        let tint = WakeTheme.color(for: GradeLevel(value: item.normalizedAverage))
                        VStack(spacing: 8) {
                            HStack {
                                SubjectLabel(subject: item.subject)
                                Spacer()
                                Text(WakeFormat.average(item.average))
                                    .font(.headline)
                                    .monospacedDigit()
                                    .foregroundStyle(tint)
                            }
                            ProgressView(value: min(max(item.normalizedAverage, 0), 20), total: 20)
                                .tint(tint)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .wakeCard()
            }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private func gradesSection(_ grades: [Grade]) -> some View {
        if !grades.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WakeSectionHeader(title: "Dernières notes")
                VStack(spacing: 14) {
                    ForEach(grades) { grade in
                        gradeRow(grade)
                        if grade.id != grades.last?.id {
                            Divider().overlay(Color.white.opacity(0.1))
                        }
                    }
                }
                .wakeCard()
            }
        }
    }

    private func gradeRow(_ grade: Grade) -> some View {
        let tint = WakeTheme.color(for: GradeLevel(value: grade.normalizedValue))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(grade.title ?? "Note").font(.headline)
                HStack(spacing: 8) {
                    SubjectLabel(subject: grade.subject)
                    Text(DateLabels.dayNumber(grade.date) + " " + DateLabels.weekdayShort(grade.date))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(WakeFormat.number(grade.value))/\(WakeFormat.number(grade.outOf))")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if grade.coefficient != 1 {
                    Text("coef. \(WakeFormat.number(grade.coefficient))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Contrôles

    private func examsSection(_ exams: [Exam], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WakeSectionHeader(title: "Contrôles à venir")
            if exams.isEmpty {
                EmptyStateCard(symbol: "checklist", title: "Aucun contrôle prévu",
                               message: "Rien de planifié pour les prochaines semaines.")
            } else {
                VStack(spacing: 14) {
                    ForEach(exams) { exam in
                        ExamRow(exam: exam, now: now)
                        if exam.id != exams.last?.id {
                            Divider().overlay(Color.white.opacity(0.1))
                        }
                    }
                }
                .wakeCard()
            }
        }
    }
}
