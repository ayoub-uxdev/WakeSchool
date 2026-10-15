import Foundation

/// Un évènement affiché dans le Centre de notifications WakeSchool.
struct NotificationItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case wakeProposed      // réveil proposé
        case wakeConfirmed     // réveil confirmé/programmé
        case timetableChange   // changement pertinent d'emploi du temps
        case newExam           // nouveau contrôle détecté
        case newGrade          // nouvelle note détectée
        case rule              // issue d'une règle personnalisée
    }

    let id: UUID
    let kind: Kind
    let title: String
    let message: String
    let date: Date
    var isRead: Bool

    init(id: UUID = UUID(), kind: Kind, title: String, message: String, date: Date, isRead: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.date = date
        self.isRead = isRead
    }
}

/// Persistance locale de l'historique du Centre de notifications (UserDefaults).
/// L'historique est volontairement borné (plus ancien supprimé).
final class NotificationCenterStore: ObservableObject {
    static let maxItems = 100
    private static let key = "notifications.history"

    @Published private(set) var items: [NotificationItem] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([NotificationItem].self, from: data) {
            items = decoded
        }
    }

    /// True s'il existe au moins un élément non lu.
    var hasUnread: Bool { items.contains { !$0.isRead } }

    var unreadCount: Int { items.filter { !$0.isRead }.count }

    /// Ajoute un évènement si et seulement si son contenu n'est pas déjà
    /// présent (même titre+message dans les éléments existants) : une ancienne
    /// information n'est jamais re-présentée comme nouvelle à chaque synchronisation.
    func addIfNew(kind: NotificationItem.Kind, title: String, message: String, date: Date = Date()) {
        let exists = items.contains { $0.title == title && $0.message == message }
        guard !exists else { return }
        var item = NotificationItem(kind: kind, title: title, message: message, date: date)
        var updated = [item] + items
        if updated.count > Self.maxItems {
            updated.removeLast(updated.count - Self.maxItems)
        }
        items = updated
        persist()
    }

    func markAllRead() {
        items = items.map { item in
            var copy = item
            copy.isRead = true
            return copy
        }
        persist()
    }

    func markRead(_ id: UUID) {
        items = items.map { item in
            var copy = item
            if copy.id == id { copy.isRead = true }
            return copy
        }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// Détection des nouveautés PRONOTE entre deux synchronisations :
/// compare le snapshot précédent au nouveau via des clés STABLES (ids),
/// et ne signale que ce qui n'était pas déjà connu.
enum ChangeDetectionService {

    /// Résultat d'une comparaison de snapshots.
    struct Changes: Equatable {
        var newGradeCount = 0
        var newExamCount = 0
        /// Notes réellement nouvelles (jamais vues avant).
        var newGrades: [Grade] = []
        /// Contrôles réellement nouveaux.
        var newExams: [Exam] = []

        var isEmpty: Bool { newGrades.isEmpty && newExams.isEmpty }
    }

    /// Notes nouvelles = ids présents dans `newSnapshot` mais pas dans `knownIDs`.
    /// Une note déjà connue (même id stable, y compris ABS) n'est jamais re-signalée.
    static func detect(previousKnownGradeIDs: Set<UUID>,
                       previousKnownExamIDs: Set<UUID>,
                       newSnapshot: SchoolSnapshot) -> Changes {
        var changes = Changes()
        for grade in newSnapshot.grades {
            guard !previousKnownGradeIDs.contains(grade.id) else { continue }
            changes.newGrades.append(grade)
        }
        for exam in newSnapshot.exams {
            guard !previousKnownExamIDs.contains(exam.id) else { continue }
            changes.newExams.append(exam)
        }
        changes.newGradeCount = changes.newGrades.count
        changes.newExamCount = changes.newExams.count
        return changes
    }

    /// Identifiants des notes d'un snapshot (ABS incluses : elles ont un id stable).
    static func gradeIDs(in snapshot: SchoolSnapshot) -> Set<UUID> {
        Set(snapshot.grades.map(\.id))
    }

    /// Identifiants des contrôles d'un snapshot.
    static func examIDs(in snapshot: SchoolSnapshot) -> Set<UUID> {
        Set(snapshot.exams.map(\.id))
    }
}
