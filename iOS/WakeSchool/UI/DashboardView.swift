import SwiftUI

/// Écran d'accueil. Toutes les valeurs affichées viennent de `DashboardService` / `InsightService`.
struct DashboardView: View {
    @EnvironmentObject private var store: SchoolDataStore
    var onNavigate: (AppTab) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: Date(), by: 60)) { context in
                let summary = DashboardService.summary(from: store.snapshot,
                                                       now: context.date,
                                                       settings: store.wakeSettings)
                ScrollView {
                    VStack(spacing: 22) {
                        header(now: context.date)
                        if store.errorMessage != nil { offlineBanner }
                        insightsCard(summary)
                        courseHero(summary)
                        wakeCard(summary)
                        statsGrid(summary)
                        todaySection(summary)
                        changesSection(summary)
                        homeworkSection(summary)
                        examsSection(summary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .refreshable { await store.refresh() }
            }
            .wakeScreenBackground()
            .navigationTitle("Accueil")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(store.isSyncing)
                    .accessibilityLabel("Synchroniser")
                }
            }
        }
    }

    // MARK: - En-tête

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting(now))
                .font(.title2.weight(.bold))
            Text(DateLabels.capitalizedFirst(DateLabels.dayTitle(now)))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            if let lastSync = store.lastSync {
                Text("Synchronisé à \(DateLabels.time(lastSync))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func greeting(_ now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Bonjour"
        case 12..<18: return "Bon après-midi"
        default: return "Bonsoir"
        }
    }

    private var offlineBanner: some View {
        Label("Synchronisation impossible. Les données locales sont affichées.",
              systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.orange)
            .wakeCard(padding: 12)
    }

    // MARK: - Résumé intelligent

    private func insightsCard(_ summary: DashboardSummary) -> some View {
        let insights = InsightService.insights(from: summary, limit: 4)
        return VStack(alignment: .leading, spacing: 12) {
            Label("En bref", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WakeTheme.accent)
            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: insight.icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WakeTheme.accent)
                        .frame(width: 20)
                    Text(insight.message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .wakeCard()
    }

    // MARK: - Cours en cours / prochain cours

    @ViewBuilder
    private func courseHero(_ summary: DashboardSummary) -> some View {
        if let course = summary.currentCourse {
            heroCard(label: "EN COURS", course: course) {
                Text("Jusqu'à \(DateLabels.time(course.end))")
            }
        } else if let course = summary.nextCourse {
            heroCard(label: "PROCHAIN COURS", course: course) {
                if Calendar.current.isDate(course.start, inSameDayAs: summary.now) {
                    HStack(spacing: 4) {
                        Text("Dans")
                        Text(course.start, style: .relative)
                    }
                } else {
                    Text(DateLabels.capitalizedFirst(DateLabels.relativeDay(course.start, now: summary.now))
                         + " à " + DateLabels.time(course.start))
                }
            }
        } else {
            EmptyStateCard(symbol: "moon.stars.fill",
                           title: "Aucun cours à venir",
                           message: "Ton emploi du temps est vide pour le moment.")
        }
    }

    private func heroCard<Trailing: View>(label: String,
                                          course: TimetableEntry,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        let tint = WakeTheme.color(for: course.subject)
        return VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.75))
            Text(course.subject.name)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            HStack(spacing: 14) {
                Label("\(DateLabels.time(course.start)) – \(DateLabels.time(course.end))", systemImage: "clock")
                if let room = course.room {
                    Label(room, systemImage: "mappin.and.ellipse")
                }
                if let teacher = course.teacher {
                    Label(teacher.name, systemImage: "person.fill")
                }
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.85))
            trailing()
                .font(.headline)
                .foregroundStyle(tint)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WakeTheme.cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: WakeTheme.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Réveil recommandé

    @ViewBuilder
    private func wakeCard(_ summary: DashboardSummary) -> some View {
        if let wake = summary.wake {
            Button { onNavigate(.alarm) } label: {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RÉVEIL RECOMMANDÉ")
                            .font(.caption.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(DateLabels.time(wake.wakeTime))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("Départ \(DateLabels.time(wake.departureTime)) · cours \(DateLabels.relativeDay(wake.firstClassStart, now: summary.now)) à \(DateLabels.time(wake.firstClassStart))")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.orange)
                }
                .wakeCard()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre l'écran Réveil")
        } else {
            EmptyStateCard(symbol: "alarm",
                           title: "Pas de réveil à calculer",
                           message: "Aucun cours à venir dans les prochains jours.")
        }
    }

    // MARK: - Chiffres clés

    private func statsGrid(_ summary: DashboardSummary) -> some View {
        let activeToday = summary.todayCourses.filter { !$0.isCancelled }.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                         spacing: 12) {
            StatTile(symbol: "book.fill", value: "\(activeToday)",
                     title: "cours aujourd'hui", tint: .blue)
            StatTile(symbol: "checklist", value: "\(summary.pendingHomeworkCount)",
                     title: "devoirs à faire", tint: .pink)
            StatTile(symbol: "chart.bar.fill",
                     value: summary.generalAverage.map { WakeFormat.average($0) } ?? "—",
                     title: "moyenne générale", tint: .mint)
            StatTile(symbol: "pencil.and.list.clipboard", value: "\(summary.upcomingExams.count)",
                     title: "contrôles à venir", tint: .orange)
        }
    }

    // MARK: - Aujourd'hui

    private func todaySection(_ summary: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WakeSectionHeader(title: "Aujourd'hui", actionTitle: "Tout voir") { onNavigate(.timetable) }
            if summary.todayCourses.isEmpty {
                EmptyStateCard(symbol: "sun.max.fill", title: "Pas de cours aujourd'hui",
                               message: "Profite de ta journée.")
            } else {
                VStack(spacing: 14) {
                    ForEach(summary.todayCourses) { course in
                        CourseRow(entry: course)
                        if course.id != summary.todayCourses.last?.id {
                            Divider().overlay(Color.white.opacity(0.1))
                        }
                    }
                }
                .wakeCard()
            }
        }
    }

    // MARK: - Changements

    @ViewBuilder
    private func changesSection(_ summary: DashboardSummary) -> some View {
        let changes = ScheduleService.sorted(summary.cancelledUpcoming + summary.modifiedUpcoming)
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WakeSectionHeader(title: "Changements")
                VStack(spacing: 14) {
                    ForEach(Array(changes.prefix(4))) { course in
                        CourseRow(entry: course, showsDay: true)
                        if course.id != changes.prefix(4).last?.id {
                            Divider().overlay(Color.white.opacity(0.1))
                        }
                    }
                }
                .wakeCard()
            }
        }
    }

    // MARK: - Devoirs

    private func homeworkSection(_ summary: DashboardSummary) -> some View {
        let urgent = Array((summary.overdueHomework + summary.homeworkDueSoon).prefix(4))
        return VStack(alignment: .leading, spacing: 12) {
            WakeSectionHeader(title: "Devoirs", actionTitle: "Tout voir") { onNavigate(.homework) }
            if urgent.isEmpty {
                EmptyStateCard(symbol: "checkmark.seal.fill", title: "Rien d'urgent",
                               message: "Aucun devoir à rendre dans les prochains jours.")
            } else {
                VStack(spacing: 14) {
                    ForEach(urgent) { item in
                        HomeworkRow(homework: item, now: summary.now) { done in
                            store.setHomework(item.id, done: done)
                        }
                        if item.id != urgent.last?.id {
                            Divider().overlay(Color.white.opacity(0.1))
                        }
                    }
                }
                .wakeCard()
            }
        }
    }

    // MARK: - Contrôles

    @ViewBuilder
    private func examsSection(_ summary: DashboardSummary) -> some View {
        if !summary.upcomingExams.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WakeSectionHeader(title: "Contrôles à venir", actionTitle: "Notes") { onNavigate(.grades) }
                let exams = Array(summary.upcomingExams.prefix(3))
                VStack(spacing: 14) {
                    ForEach(exams) { exam in
                        ExamRow(exam: exam, now: summary.now)
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
