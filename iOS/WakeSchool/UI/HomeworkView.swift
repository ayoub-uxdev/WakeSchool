import SwiftUI
import QuickLook

/// Devoirs : en retard, à venir, terminés. L'état « terminé » est persisté par le store.
struct HomeworkView: View {
    @EnvironmentObject private var store: SchoolDataStore
    @State private var selectedHomework: Homework?

    var body: some View {
        NavigationStack {
            let now = Date()
            let sections = HomeworkOverviewService.sections(from: store.snapshot.homework, now: now)

            ScrollView {
                VStack(spacing: 22) {
                    if sections.isEmpty {
                        EmptyStateCard(symbol: "checkmark.seal.fill",
                                       title: "Aucun devoir",
                                       message: "Tout est à jour. Tire vers le bas pour synchroniser.")
                    } else {
                        progressCard(sections)
                        section("En retard", icon: "exclamationmark.triangle.fill", tint: .red,
                                items: sections.overdue, now: now)
                        section("À venir", icon: "calendar", tint: WakeTheme.accent,
                                items: sections.upcoming, now: now)
                        section("Terminés", icon: "checkmark.circle.fill", tint: .green,
                                items: sections.done, now: now)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .animation(.snappy, value: sections)
            }
            .refreshable { await store.refresh() }
            .wakeScreenBackground()
            .navigationTitle("Devoirs")
            .sheet(item: $selectedHomework) { homework in
                HomeworkDetailView(
                    homework: homework,
                    now: Date(),
                    onToggle: { done in
                        store.setHomework(homework.id, done: done)
                        selectedHomework?.isDone = done
                    }
                )
            }
        }
    }

    private func progressCard(_ sections: HomeworkSections) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(sections.done.count) sur \(sections.total) terminés")
                    .font(.headline)
                Spacer()
                Text("\(Int((sections.completion * 100).rounded())) %")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(WakeTheme.accent)
            }
            ProgressView(value: sections.completion)
                .tint(WakeTheme.accent)
        }
        .wakeCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, tint: Color,
                         items: [Homework], now: Date) -> some View {
        if !items.isEmpty {
            let groups = HomeworkOverviewService.groupedByDueDate(items)
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                VStack(spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(DateLabels.relativeDay(group.date, now: now).uppercased()) — \(DateLabels.dayTitle(group.date).uppercased())")
                                        .font(.caption.weight(.bold))
                                        .tracking(0.6)
                                    Text("\(group.items.count) \(group.items.count == 1 ? "devoir prévu" : "devoirs prévus")")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WakeTheme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                            ForEach(group.items) { item in
                                HomeworkRow(homework: item, now: now) { done in
                                    store.setHomework(item.id, done: done)
                                } onOpen: {
                                    selectedHomework = item
                                }
                                if item.id != group.items.last?.id {
                                    Divider().overlay(Color.white.opacity(0.1))
                                }
                            }
                        }
                        .padding(.bottom, 8)
                        if group.id != groups.last?.id {
                            Divider().overlay(Color.white.opacity(0.18))
                        }
                    }
                }
                .wakeCard()
            }
        }
    }

    private struct HomeworkDetailView: View {
            let homework: Homework
            let now: Date
            let onToggle: (Bool) -> Void
            @EnvironmentObject private var store: SchoolDataStore
            @Environment(\.dismiss) private var dismiss
            @State private var isDone: Bool
            @State private var downloadingAttachmentID: String?
            @State private var attachmentError: String?
            @State private var previewURL: URL?

            init(homework: Homework, now: Date, onToggle: @escaping (Bool) -> Void) {
                self.homework = homework
                self.now = now
                self.onToggle = onToggle
                _isDone = State(initialValue: homework.isDone)
            }

            var body: some View {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            SubjectLabel(subject: homework.subject)
                            Text(homework.title)
                                .font(.title2.bold())
                            Label(
                                "À rendre le \(DateLabels.dayTitle(homework.dueDate)) · \(DateLabels.time(homework.dueDate))",
                                systemImage: "calendar"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))

                            if homework.priority != .unspecified {
                                WakeBadge(
                                    text: homework.priority.displayLabel,
                                    systemImage: prioritySymbol,
                                    tint: priorityTint
                                )
                            }

                            if homework.details.isEmpty {
                                Text("Aucune description fournie.")
                                    .foregroundStyle(.white.opacity(0.65))
                            } else {
                                Text(homework.details)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if !homework.attachments.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Documents associés")
                                        .font(.headline)
                                    ForEach(homework.attachments) { attachment in
                                        attachmentRow(attachment)
                                    }
                                    if let attachmentError {
                                        Text(attachmentError)
                                            .font(.footnote)
                                            .foregroundStyle(.red)
                                            .accessibilityAddTraits(.isStaticText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button {
                                isDone.toggle()
                                onToggle(isDone)
                            } label: {
                                Label(
                                    isDone ? "Marquer comme non terminé" : "Marquer comme terminé",
                                    systemImage: isDone ? "arrow.uturn.backward.circle" : "checkmark.circle"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(isDone ? .gray : .green)
                        }
                        .padding(20)
                    }
                    .wakeScreenBackground()
                    .navigationTitle("Détail du devoir")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { dismiss() }
                        }
                    }
                }
                .quickLookPreview($previewURL)
            }

            private var prioritySymbol: String {
                switch homework.priority {
                case .low: return "arrow.down.circle"
                case .normal: return "minus.circle"
                case .high: return "flame.fill"
                case .unspecified: return "questionmark.circle"
                }
            }

            private var priorityTint: Color {
                switch homework.priority {
                case .low: return .gray
                case .normal: return .blue
                case .high: return .red
                case .unspecified: return .gray
                }
            }

            @ViewBuilder
            private func attachmentRow(_ attachment: HomeworkAttachment) -> some View {
            switch attachment.kind {
            case .link:
                if let rawURL = attachment.linkURL,
                   let url = URL(string: rawURL),
                   ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Link(destination: url) {
                        Label(attachment.name, systemImage: "link")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Label("\(attachment.name) · Lien indisponible", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            case .file:
                Button {
                    openAttachment(attachment)
                } label: {
                    HStack {
                        Label(attachment.name, systemImage: "doc")
                        Spacer()
                        if downloadingAttachmentID == attachment.id {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.doc")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(downloadingAttachmentID != nil)
            case .unsupported:
                Label("\(attachment.name) · Format non pris en charge", systemImage: "doc.questionmark")
                    .foregroundStyle(.secondary)
            }
        }

            private func openAttachment(_ attachment: HomeworkAttachment) {
            downloadingAttachmentID = attachment.id
            attachmentError = nil
            Task {
                defer { downloadingAttachmentID = nil }
                do {
                    let data = try await store.downloadHomeworkAttachment(attachment)
                    let filename = URL(fileURLWithPath: attachment.name).lastPathComponent
                    let fileExtension = URL(fileURLWithPath: filename).pathExtension
                    var destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                    if !fileExtension.isEmpty {
                        destination.appendPathExtension(fileExtension)
                    }
                    try data.write(to: destination, options: .atomic)
                    previewURL = destination
                } catch {
                    attachmentError = error.localizedDescription
                }
            }
        }
    }
}
