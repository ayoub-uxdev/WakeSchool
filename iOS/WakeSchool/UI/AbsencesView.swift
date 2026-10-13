import SwiftUI

/// Écran « Absences et retards » : liste des évènements de vie scolaire issus de
/// PRONOTE (ou de la démonstration). Lecture seule — aucune donnée inventée.
///
/// Les absences/retards sont synchronisés indépendamment du cache scolaire :
/// une erreur dédiée (`attendanceError`) est affichée ici sans jamais masquer
/// les évènements déjà enregistrés localement.
struct AbsencesView: View {
    @EnvironmentObject private var store: SchoolDataStore

    @State private var filter: AttendanceKind?

    var body: some View {
        // Poussé depuis MoreView : le NavigationStack est fourni par le parent.
        content
            .wakeScreenBackground()
            .navigationTitle("Absences et retards")
            .toolbar { filterToolbar }
            .task { if store.attendance.isEmpty { await store.refreshAttendance() } }
            .refreshable { await store.refreshAttendance() }
    }

    // MARK: - Contenu

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard

                if let error = store.attendanceError {
                    errorCard(error)
                }

                let events = filteredEvents
                if events.isEmpty {
                    EmptyStateCard(
                        symbol: "checkmark.seal.fill",
                        title: "Rien à signaler",
                        message: store.attendance.isEmpty
                            ? "Aucune absence ni retard enregistré pour le moment."
                            : "Aucun évènement pour ce filtre."
                    )
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 14) {
                        ForEach(events) { event in
                            AttendanceRow(event: event)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 20)
        }
    }

    private var filteredEvents: [AttendanceEvent] {
        guard let filter else { return store.attendance }
        return store.attendance.filter { $0.kind == filter }
    }

    // MARK: - Filtre

    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    filter = nil
                } label: {
                    Label("Tout", systemImage: filter == nil ? "checkmark" : "line.3.horizontal.decrease")
                }
                ForEach(AttendanceKind.allCases, id: \.self) { kind in
                    Button {
                        filter = kind
                    } label: {
                        Label(kind.displayName + "s",
                              systemImage: filter == kind ? "checkmark" : kind.systemImage)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }

    // MARK: - Synthèse

    private var summaryCard: some View {
        let absences = store.attendance.filter { $0.kind == .absence }
        let delays = store.attendance.filter { $0.kind == .delay }
        let unjustified = store.attendance.filter { !$0.isJustified }.count

        return HStack(spacing: 12) {
            StatTile(symbol: "person.fill.xmark",
                     value: "\(absences.count)",
                     title: "Absences",
                     tint: .orange)
            StatTile(symbol: "clock.fill",
                     value: "\(delays.count)",
                     title: "Retards",
                     tint: .yellow)
            StatTile(symbol: "exclamationmark.triangle.fill",
                     value: "\(unjustified)",
                     title: "À justifier",
                     tint: unjustified > 0 ? .red : .green)
        }
        .padding(.horizontal, 20)
    }

    private func errorCard(_ message: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Absences indisponibles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .wakeCard(padding: 16)
        .padding(.horizontal, 20)
    }
}

// MARK: - Ligne d'évènement

private struct AttendanceRow: View {
    let event: AttendanceEvent

    private var tint: Color {
        event.kind == .absence ? Color.orange : Color.yellow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: event.kind.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tint.opacity(0.18)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.kind.displayName)
                        .font(.headline)
                    Text(DateLabels.capitalizedFirst(DateLabels.dayTitle(event.start)))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 14) {
                meta(symbol: "clock", text: timeRange)
                if let duration = event.durationMinutes {
                    meta(symbol: "timer", text: "\(duration) min")
                }
                if let subject = event.subjectName {
                    meta(symbol: "book.closed", text: subject)
                }
            }

            if let justification = event.justification, !justification.isEmpty {
                metaRow(symbol: "text.bubble", label: "Justification", value: justification)
            }
            if !event.reasons.isEmpty {
                metaRow(symbol: "tag", label: "Motif(s)", value: event.reasons.joined(separator: ", "))
            }
        }
        .wakeCard(padding: 16)
        .accessibilityElement(children: .contain)
    }

    private var statusBadge: some View {
        WakeBadge(
            text: event.isJustified ? "Justifié" : "Non justifié",
            systemImage: event.isJustified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
            tint: event.isJustified ? .green : .red
        )
    }

    private var timeRange: String {
        let start = DateLabels.time(event.start)
        guard let end = event.end else { return "à \(start)" }
        return "\(start) → \(DateLabels.time(end))"
    }

    private func meta(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
    }

    private func metaRow(symbol: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text(label + " :")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    // La vue est poussée depuis MoreView : le preview simule ce contexte.
    NavigationStack {
        AbsencesView()
    }
    .environmentObject(
        SchoolDataStore(environment: AppEnvironment.inMemory())
    )
}

