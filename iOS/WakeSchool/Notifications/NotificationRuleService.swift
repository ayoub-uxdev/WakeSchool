import Foundation

/// Types de règles de notification personnalisées (version simple, extensible).
enum NotificationRuleKind: String, Codable, CaseIterable, Identifiable {
    /// Avertir lorsqu'une nouvelle note apparaît (à chaque synchronisation).
    case newGrade
    /// Avertir lorsqu'un nouveau DS est détecté.
    case newExam
    /// Rappeler les devoirs à rendre demain, à une heure donnée.
    case homeworkDueTomorrow
    /// Notifier à heure fixe s'il y a eu une nouvelle note détectée (connue localement).
    case gradeDigestAtTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newGrade: return "Nouvelle note"
        case .newExam: return "Nouveau contrôle (DS)"
        case .homeworkDueTomorrow: return "Devoirs à rendre demain"
        case .gradeDigestAtTime: return "Résumé des nouvelles notes"
        }
    }

    var systemImage: String {
        switch self {
        case .newGrade: return "chart.bar.fill"
        case .newExam: return "checklist"
        case .homeworkDueTomorrow: return "book.closed.fill"
        case .gradeDigestAtTime: return "bell.fill"
        }
    }

    /// La règle nécessite-t-elle une heure d'envoi configurable ?
    var needsTime: Bool {
        switch self {
        case .newGrade, .newExam: return false
        case .homeworkDueTomorrow, .gradeDigestAtTime: return true
        }
    }
}

/// Une règle activable/désactivable et configurable.
struct NotificationRule: Identifiable, Codable, Equatable {
    var id: String
    var kind: NotificationRuleKind
    var isEnabled: Bool
    /// Heure d'envoi en minutes depuis minuit (pour les règles à heure).
    var timeMinutes: Int

    static func `default`(for kind: NotificationRuleKind) -> NotificationRule {
        NotificationRule(id: kind.rawValue, kind: kind, isEnabled: false, timeMinutes: 19 * 60)
    }

    static let defaults: [NotificationRule] = NotificationRuleKind.allCases.map { .default(for: $0) }
}

/// Règles persistées (UserDefaults).
final class NotificationRulesStore: ObservableObject {
    private static let key = "notifications.rules"
    @Published private(set) var rules: [NotificationRule]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([NotificationRule].self, from: data) {
            rules = decoded
        } else {
            rules = NotificationRule.defaults
        }
    }

    func rule(for kind: NotificationRuleKind) -> NotificationRule {
        rules.first { $0.kind == kind } ?? .default(for: kind)
    }

    func setEnabled(_ enabled: Bool, for kind: NotificationRuleKind) {
        update(kind) { $0.isEnabled = enabled }
    }

    func setTime(minutes: Int, for kind: NotificationRuleKind) {
        update(kind) { $0.timeMinutes = minutes }
    }

    private func update(_ kind: NotificationRuleKind, mutate: (inout NotificationRule) -> Void) {
        var updated = rules
        guard let index = updated.firstIndex(where: { $0.kind == kind }) else { return }
        mutate(&updated[index])
        rules = updated
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// Évaluation PURE des règles : construit les notifications à partir des
/// informations DÉJÀ connues de WakeSchool. Une règle à 19 h signifie une
/// notification planifiée à 19 h avec ce qui est connu — iOS ne peut pas
/// interroger PRONOTE à heure exacte en arrière-plan.
enum NotificationRuleService {

    /// Notifications déclenchées par les règles, à partir des changements détectés.
    /// Les identifiants sont stables (kind + id de l'objet PRONOTE) : pas de répétition.
    static func notifications(for rules: [NotificationRule],
                              changes: ChangeDetectionService.Changes,
                              calendar: Calendar = .current) -> [WakeNotification] {
        var result: [WakeNotification] = []

        if let rule = rules.first(where: { $0.kind == .newGrade }), rule.isEnabled {
            for grade in changes.newGrades {
                let subject = grade.subject.name
                let title = "Nouvelle note"
                let body = grade.isNumeric
                    ? "\(subject) : \(grade.displayValue)/\(Int(grade.outOf)) a été publiée."
                    : "\(subject) : une évaluation « \(grade.displayValue) » a été publiée."
                result.append(.rule("grade", grade.id.uuidString, title, body))
            }
        }

        if let rule = rules.first(where: { $0.kind == .newExam }), rule.isEnabled {
            for exam in changes.newExams {
                result.append(.rule("exam", exam.id.uuidString,
                                    "Nouveau contrôle",
                                    "\(exam.subject.name) : \(exam.title), le \(DateLabels.dayTitle(exam.date))."))
            }
        }

        return result
    }

    /// Prochaine date d'une règle à heure fixe (comme la confirmation 21 h).
    static func nextFireDate(minutes: Int, now: Date, calendar: Calendar) -> Date? {
        WakeConfirmationService.nextSendDate(minutesFromMidnight: minutes, now: now, calendar: calendar)
    }

    /// Message du rappel « devoirs à rendre demain » (planifié avec les infos connues).
    static func homeworkDueTomorrowMessage(homework: [Homework],
                                           now: Date,
                                           calendar: Calendar) -> (title: String, body: String)? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let due = homework.filter { !$0.isDone && calendar.isDate($0.dueDate, inSameDayAs: tomorrow) }
        guard !due.isEmpty else { return nil }
        let title = "Devoirs à rendre demain"
        let body = due.count == 1
            ? "1 devoir à rendre demain : \(due[0].subject.name)."
            : "\(due.count) devoirs à rendre demain : \(due.map { $0.subject.name }.joined(separator: ", "))."
        return (title, body)
    }
}
