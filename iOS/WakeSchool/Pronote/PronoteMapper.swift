import Foundation
import CryptoKit

struct PronoteProfile: Codable, Equatable {
    var displayName: String
    var className: String?
    var schoolName: String?
}

enum PronoteMapperError: Error, LocalizedError {
    case invalidResponse(String)
    var errorDescription: String? {
        switch self { case .invalidResponse(let message): return "Données PRONOTE impossibles à lire : \(message)" }
    }
}

enum PronoteMapper {
    static func profile(from response: Any) -> PronoteProfile {
        let root = PronoteJSON.unwrap(response)
        let info = PronoteJSON.recursivelyFindDictionary(root, keys: ["libelleUtil", "nom", "classe", "ressource"]) ?? (root as? [String: Any] ?? [:])
        let displayName = PronoteJSON.string(info["libelleUtil"]) ?? PronoteJSON.string(info["nom"]) ?? "Élève"
        let className = PronoteJSON.string(info["classe"]) ?? PronoteJSON.string(info["classeLibelle"])
        let schoolName = PronoteJSON.string(info["etablissement"]) ?? PronoteJSON.string(info["nomEtab"])
        return PronoteProfile(displayName: displayName, className: className, schoolName: schoolName)
    }

    static func resource(from response: Any) -> [String: Any]? {
        if let dictionary = response as? [String: Any] {
            if let resource = PronoteJSON.nestedDictionary(dictionary, keys: ["ressource", "Ressource"]) { return resource }
            if let dataSec = dictionary["dataSec"] { return resource(from: dataSec) }
            if let data = dictionary["data"] { return resource(from: data) }
            if let donnees = dictionary["donnees"] { return resource(from: donnees) }
            for value in dictionary.values { if let result = resource(from: value) { return result } }
        } else if let array = response as? [Any] {
            for value in array { if let result = resource(from: value) { return result } }
        }
        return nil
    }

    static func periods(from response: Any) -> [[String: Any]] {
        let root = PronoteJSON.unwrap(response)
        guard let dictionary = root as? [String: Any] else { return [] }
        let keys = ["listePeriodes", "periodes", "ListePeriodes", "Periodes"]
        for key in keys {
            if let array = dictionary[key] as? [[String: Any]] { return array }
        }
        if let found = PronoteJSON.recursivelyFindDictionary(root, keys: Set(keys)) {
            for key in keys { if let array = found[key] as? [[String: Any]] { return array } }
        }
        return []
    }

    static func schoolYearStart(from response: Any, fallback: Date = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 9, day: 1))!) -> Date {
        let keys = ["dateDebutAnnee", "DateDebutAnnee", "debutAnnee", "dateDebut"]
        if let found = findValue(root: response, keys: keys), let date = PronoteJSON.date(found) { return date }
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let september = Calendar.current.date(from: DateComponents(year: year, month: 9, day: 1))!
        return now < september ? Calendar.current.date(byAdding: .year, value: -1, to: september)! : september
    }

    static func timetable(from response: Any) -> [TimetableEntry] {
        let root = PronoteJSON.unwrap(response)
        let candidates = collectDictionaries(root)
        let lessons = candidates.filter { dictionary in
            let hasStart = findValue(in: dictionary, keys: ["dateDebut", "DateDebut", "debut", "heureDebut"]) != nil
            let hasEnd = findValue(in: dictionary, keys: ["dateFin", "DateFin", "fin", "heureFin"]) != nil
            let hasSubject = findValue(in: dictionary, keys: ["matiere", "Matiere", "subject"]) != nil
            return hasStart && hasEnd && hasSubject
        }

        var result: [TimetableEntry] = []
        var seen = Set<UUID>()
        for lesson in lessons {
            guard let start = dateTime(from: lesson, dateKeys: ["dateDebut", "DateDebut", "debut"], timeKeys: ["heureDebut"]),
                  let end = dateTime(from: lesson, dateKeys: ["dateFin", "DateFin", "fin"], timeKeys: ["heureFin"]) else { continue }
            let subjectValue = findValue(in: lesson, keys: ["matiere", "Matiere", "subject"])
            let subjectName = extractName(subjectValue) ?? "Matière"
            let subjectID = stableID(prefix: "subject", value: extractID(subjectValue) ?? subjectName)
            let subject = Subject(id: subjectID, name: subjectName)

            let teacherValue = findValue(in: lesson, keys: ["professeur", "Professeur", "prof", "professeurs", "enseignant"])
            let teacherName = extractName(teacherValue)
            let teacher: Teacher? = teacherName.map { Teacher(id: stableID(prefix: "teacher", value: extractID(teacherValue) ?? $0), name: $0) }

            let roomValue = findValue(in: lesson, keys: ["salle", "Salle", "salles", "room"])
            let room = extractName(roomValue)
            let cancelled = PronoteJSON.bool(findValue(in: lesson, keys: ["annule", "annulee", "estAnnule", "estAnnulee", "cancelled"])) ?? false
            let modified = PronoteJSON.bool(findValue(in: lesson, keys: ["modifie", "modifiee", "estModifie", "modified"])) ?? false
            let note = PronoteJSON.string(findValue(in: lesson, keys: ["motif", "commentaire", "modification", "changeNote"]))
            let rawID = extractID(lesson) ?? "\(subjectName)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(room ?? "")"
            let id = stableID(prefix: "lesson", value: rawID)
            guard seen.insert(id).inserted else { continue }
            result.append(TimetableEntry(id: id, subject: subject, teacher: teacher, room: room, start: start, end: end, isCancelled: cancelled, isModified: modified, changeNote: note))
        }
        return result.sorted { $0.start < $1.start }
    }

    static func homework(from response: Any) -> [Homework] {
        let root = PronoteJSON.unwrap(response)
        let candidates = collectDictionaries(root)
        let items = candidates.filter { dictionary in
            let hasDescription = findValue(in: dictionary, keys: ["description", "Description", "contenu", "texte", "travail"]) != nil
            let hasDate = findValue(in: dictionary, keys: ["date", "datePour", "dateRendu", "dateLimite", "Date"]) != nil
            let hasSubject = findValue(in: dictionary, keys: ["matiere", "Matiere", "subject"]) != nil
            return hasDescription && hasDate && hasSubject
        }

        var result: [Homework] = []
        var seen = Set<UUID>()
        for item in items {
            guard let due = PronoteJSON.date(findValue(in: item, keys: ["datePour", "dateRendu", "dateLimite", "date", "Date"])) else { continue }
            let subjectValue = findValue(in: item, keys: ["matiere", "Matiere", "subject"])
            let subjectName = extractName(subjectValue) ?? "Matière"
            let subject = Subject(id: stableID(prefix: "subject", value: extractID(subjectValue) ?? subjectName), name: subjectName)
            let title = PronoteJSON.string(findValue(in: item, keys: ["titre", "title", "nom"])) ?? "Devoir"
            let details = PronoteJSON.string(findValue(in: item, keys: ["description", "Description", "contenu", "texte", "travail"])) ?? ""
            let done = PronoteJSON.bool(findValue(in: item, keys: ["fait", "estFait", "done"])) ?? false
            let priority: HomeworkPriority = (PronoteJSON.bool(findValue(in: item, keys: ["urgent", "prioritaire"])) == true) ? .high : .normal
            let rawID = extractID(item) ?? "\(subjectName)|\(title)|\(due.timeIntervalSince1970)|\(details)"
            let id = stableID(prefix: "homework", value: rawID)
            guard seen.insert(id).inserted else { continue }
            result.append(Homework(id: id, subject: subject, title: title, details: details, dueDate: due, isDone: done, priority: priority))
        }
        return result.sorted { $0.dueDate < $1.dueDate }
    }

    static func grades(from response: Any) -> [Grade] {
        let root = PronoteJSON.unwrap(response)
        let candidates = collectDictionaries(root)
        let items = candidates.filter { dictionary in
            findValue(in: dictionary, keys: ["note", "Note", "valeur", "grade"]) != nil &&
            findValue(in: dictionary, keys: ["matiere", "Matiere", "subject"]) != nil
        }

        var result: [Grade] = []
        var seen = Set<UUID>()
        for item in items {
            guard let value = PronoteJSON.number(findValue(in: item, keys: ["note", "Note", "valeur", "grade"])) else { continue }
            let outOf = PronoteJSON.number(findValue(in: item, keys: ["noteSur", "sur", "bareme", "outOf"])) ?? 20
            let coefficient = PronoteJSON.number(findValue(in: item, keys: ["coef", "coefficient", "Coeff"])) ?? 1
            let date = PronoteJSON.date(findValue(in: item, keys: ["date", "Date"])) ?? Date()
            let subjectValue = findValue(in: item, keys: ["matiere", "Matiere", "subject"])
            let subjectName = extractName(subjectValue) ?? "Matière"
            let subject = Subject(id: stableID(prefix: "subject", value: extractID(subjectValue) ?? subjectName), name: subjectName)
            let title = PronoteJSON.string(findValue(in: item, keys: ["devoir", "titre", "title", "nom"]))
            let rawID = extractID(item) ?? "\(subjectName)|\(value)|\(outOf)|\(date.timeIntervalSince1970)|\(title ?? "")"
            let id = stableID(prefix: "grade", value: rawID)
            guard seen.insert(id).inserted else { continue }
            result.append(Grade(id: id, subject: subject, value: value, outOf: outOf, coefficient: coefficient, date: date, title: title))
        }
        return result.sorted { $0.date > $1.date }
    }

    private static func collectDictionaries(_ value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                result.append(dictionary)
                for child in dictionary.values { walk(child) }
            } else if let array = value as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(value)
        return result
    }

    private static func findValue(root: Any, keys: [String]) -> Any? {
        if let dictionary = root as? [String: Any] { return findValue(in: dictionary, keys: keys) }
        return nil
    }

    private static func findValue(in dictionary: [String: Any], keys: [String]) -> Any? {
        for key in keys { if let value = dictionary[key] { return value } }
        for value in dictionary.values {
            if let nested = value as? [String: Any], let result = findValue(in: nested, keys: keys) { return result }
        }
        return nil
    }

    private static func extractID(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let dictionary = value as? [String: Any] else { return nil }
        for key in ["N", "id", "ID", "identifiant", "code"] {
            if let result = PronoteJSON.string(dictionary[key]) { return result }
        }
        return nil
    }

    private static func extractName(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let dictionary = value as? [String: Any] else { return nil }
        for key in ["L", "libelle", "nom", "name", "label", "titre"] {
            if let result = PronoteJSON.string(dictionary[key]) { return result }
        }
        if let array = value as? [[String: Any]], let first = array.first { return extractName(first) }
        return nil
    }

    private static func dateTime(from dictionary: [String: Any], dateKeys: [String], timeKeys: [String]) -> Date? {
        for key in dateKeys { if let date = PronoteJSON.date(dictionary[key]) { return date } }
        if let dateString = PronoteJSON.string(findValue(in: dictionary, keys: ["date", "Date"])),
           let timeString = PronoteJSON.string(findValue(in: dictionary, keys: timeKeys)) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: "\(dateString) \(timeString)") { return date }
            }
        }
        return nil
    }

    private static func stableID(prefix: String, value: String) -> UUID {
        let data = Data("\(prefix):\(value)".utf8)
        let digest = Array(Insecure.MD5.hash(data: data))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
