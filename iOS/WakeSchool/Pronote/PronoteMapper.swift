import Foundation
import CryptoKit

struct PronoteProfile: Codable, Equatable {
    var displayName: String
    var className: String?
    var schoolName: String?
}

struct PronoteGradeMappingResult {
    let grades: [Grade]
    let rejectedCounts: [String: Int]
}

enum PronoteGradeRejection: String {
    case missingOrInvalidValue = "valeur absente ou invalide"
    case missingOrInvalidDate = "date absente ou invalide"
    case missingSubject = "matière absente"
    case duplicate = "doublon"
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
        let root = PronoteJSON.unwrap(response)
        if let dictionary = root as? [String: Any] {
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

    static func studentResource(
        from response: Any,
        accountKind: PronoteAccountKind
    ) -> [String: Any]? {
        let accountResource = resource(from: response)
        guard accountKind == .parent else {
            return accountResource
        }
        return (accountResource?["listeRessources"] as? [[String: Any]])?.first
    }

    static func periods(from response: Any) -> [[String: Any]] {
        let root = PronoteJSON.unwrap(response)
        guard let dictionary = root as? [String: Any] else { return [] }
        let keys = ["listePeriodes", "periodes", "ListePeriodes", "Periodes"]
        for key in keys {
            if let array = dictionary[key] as? [[String: Any]] { return array }
            if let wrapped = dictionary[key] as? [String: Any],
               let array = wrapped["V"] as? [[String: Any]] {
                return array
            }
        }
        if let found = PronoteJSON.recursivelyFindDictionary(root, keys: keys) {
            for key in keys {
                if let array = found[key] as? [[String: Any]] { return array }
                if let wrapped = found[key] as? [String: Any],
                   let array = wrapped["V"] as? [[String: Any]] {
                    return array
                }
            }
        }
        return []
    }

    static func schoolYearStart(from response: Any) -> Date? {
        let root = PronoteJSON.unwrap(response)
        guard let general = PronoteJSON.recursivelyFindDictionary(
            root,
            keys: ["PremierLundi"]
        ) else {
            return nil
        }
        return PronoteJSON.date(general["PremierLundi"])
    }

    static func timetable(
        from response: Any,
        schoolDayEndTimes: [[String: Any]] = []
    ) -> [TimetableEntry] {
        if let lessons = protocolItems(from: response, keys: ["ListeCours"]) {
            return lessons.compactMap {
                protocolTimetableEntry($0, schoolDayEndTimes: schoolDayEndTimes)
            }.sorted { $0.start < $1.start }
        }

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
        if let items = protocolItems(from: response, keys: ["ListeTravauxAFaire"]) {
            return items.compactMap(protocolHomework).sorted { $0.dueDate < $1.dueDate }
        }

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
            let rawDetails = PronoteJSON.string(findValue(in: item, keys: ["description", "Description", "contenu", "texte", "travail"])) ?? ""
            let details = HomeworkDescriptionFormatter.plainText(from: rawDetails)
            let done = PronoteJSON.bool(findValue(in: item, keys: ["fait", "estFait", "done"])) ?? false
            let priority = HomeworkPriority.unspecified
            let rawID = extractID(item) ?? "\(subjectName)|\(title)|\(due.timeIntervalSince1970)|\(details)"
            let id = stableID(prefix: "homework", value: rawID)
            guard seen.insert(id).inserted else { continue }
            result.append(Homework(
                id: id,
                subject: subject,
                title: title,
                details: details,
                dueDate: due,
                isDone: done,
                priority: priority,
                attachments: protocolAttachments(from: item)
            ))
        }
        return result.sorted { $0.dueDate < $1.dueDate }
    }

    static func grades(from response: Any) -> [Grade] {
        gradeMapping(from: response).grades
    }

    static func gradeMapping(from response: Any) -> PronoteGradeMappingResult {
        if let items = protocolItems(from: response, keys: ["listeDevoirs"]) {
            var grades: [Grade] = []
            var rejected: [String: Int] = [:]
            var seen = Set<UUID>()

            for item in items {
                guard let grade = protocolGrade(item) else {
                    let reason = protocolGradeRejection(for: item)
                    rejected[reason.rawValue, default: 0] += 1
                    continue
                }
                guard seen.insert(grade.id).inserted else {
                    rejected[PronoteGradeRejection.duplicate.rawValue, default: 0] += 1
                    continue
                }
                grades.append(grade)
            }

            return PronoteGradeMappingResult(
                grades: grades.sorted { $0.date > $1.date },
                rejectedCounts: rejected
            )
        }

        let root = PronoteJSON.unwrap(response)
        let candidates = collectDictionaries(root)
        let items = candidates.filter { dictionary in
            findValue(in: dictionary, keys: ["note", "Note", "valeur", "grade"]) != nil &&
            findValue(in: dictionary, keys: ["matiere", "Matiere", "subject"]) != nil
        }

        var result: [Grade] = []
        var rejected: [String: Int] = [:]
        var seen = Set<UUID>()
        for item in items {
            guard let value = PronoteJSON.number(findValue(in: item, keys: ["note", "Note", "valeur", "grade"])) else {
                rejected[PronoteGradeRejection.missingOrInvalidValue.rawValue, default: 0] += 1
                continue
            }
            let outOf = PronoteJSON.number(findValue(in: item, keys: ["noteSur", "sur", "bareme", "outOf"])) ?? 20
            let coefficient = PronoteJSON.number(findValue(in: item, keys: ["coef", "coefficient", "Coeff"])) ?? 1
            guard let date = PronoteJSON.date(findValue(in: item, keys: ["date", "Date"])) else {
                rejected[PronoteGradeRejection.missingOrInvalidDate.rawValue, default: 0] += 1
                continue
            }
            let subjectValue = findValue(in: item, keys: ["matiere", "Matiere", "subject"])
            guard subjectValue != nil else {
                rejected[PronoteGradeRejection.missingSubject.rawValue, default: 0] += 1
                continue
            }
            let subjectName = extractName(subjectValue) ?? "Matière"
            let subject = Subject(id: stableID(prefix: "subject", value: extractID(subjectValue) ?? subjectName), name: subjectName)
            let title = PronoteJSON.string(findValue(in: item, keys: ["devoir", "titre", "title", "nom"]))
            let rawID = extractID(item) ?? "\(subjectName)|\(value)|\(outOf)|\(date.timeIntervalSince1970)|\(title ?? "")"
            let id = stableID(prefix: "grade", value: rawID)
            guard seen.insert(id).inserted else {
                rejected[PronoteGradeRejection.duplicate.rawValue, default: 0] += 1
                continue
            }
            result.append(Grade(id: id, subject: subject, value: value, outOf: outOf, coefficient: coefficient, date: date, title: title))
        }
        return PronoteGradeMappingResult(
            grades: result.sorted { $0.date > $1.date },
            rejectedCounts: rejected
        )
    }

    static func rawTimetableCount(from response: Any) -> Int {
        protocolItems(from: response, keys: ["ListeCours"])?.count
            ?? timetable(from: response).count
    }

    static func rawHomeworkCount(from response: Any) -> Int {
        protocolItems(from: response, keys: ["ListeTravauxAFaire"])?.count
            ?? homework(from: response).count
    }

    static func rawGradesCount(from response: Any) -> Int {
        protocolItems(from: response, keys: ["listeDevoirs"])?.count
            ?? grades(from: response).count
    }

    private static func protocolItems(
        from response: Any,
        keys: [String]
    ) -> [[String: Any]]? {
        let root = PronoteJSON.unwrap(response)
        guard let container = PronoteJSON.recursivelyFindDictionary(root, keys: keys) else {
            return nil
        }
        for key in keys {
            if let items = container[key] as? [[String: Any]] {
                return items
            }
            if let wrapped = container[key] as? [String: Any],
               let items = wrapped["V"] as? [[String: Any]] {
                return items
            }
        }
        return []
    }

    private static func protocolTimetableEntry(
        _ lesson: [String: Any],
        schoolDayEndTimes: [[String: Any]]
    ) -> TimetableEntry? {
        guard let start = PronoteJSON.date(lesson["DateDuCours"]) else {
            return nil
        }
        guard let end = PronoteJSON.date(lesson["DateDuCoursFin"])
                ?? protocolLessonEnd(from: lesson, start: start, endTimes: schoolDayEndTimes) else {
            return nil
        }

        let contents = (lesson["ListeContenus"] as? [String: Any])?["V"] as? [[String: Any]] ?? []
        let subjectContent = contents.first { PronoteJSON.number($0["G"]) == 16 }
        let subjectName = extractName(subjectContent) ?? "Matière"
        let subjectID = stableID(prefix: "subject", value: extractID(subjectContent) ?? subjectName)
        let subject = Subject(id: subjectID, name: subjectName)

        let teachers = contents
            .filter { PronoteJSON.number($0["G"]) == 3 }
            .compactMap { extractName($0) }
        let rooms = contents
            .filter { PronoteJSON.number($0["G"]) == 17 }
            .compactMap { extractName($0) }

        let rawID = extractID(lesson) ?? "\(subjectName)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)"
        let id = stableID(prefix: "lesson", value: rawID)
        let teacherName = teachers.joined(separator: ", ")
        let teacher: Teacher? = teacherName.isEmpty
            ? nil
            : Teacher(id: stableID(prefix: "teacher", value: teacherName), name: teacherName)
        return TimetableEntry(
            id: id,
            subject: subject,
            teacher: teacher,
            room: rooms.isEmpty ? nil : rooms.joined(separator: ", "),
            start: start,
            end: end,
            isCancelled: PronoteJSON.bool(lesson["estAnnule"]) ?? false,
            isModified: false,
            changeNote: PronoteJSON.string(lesson["memo"])
        )
    }

    private static func protocolLessonEnd(
        from lesson: [String: Any],
        start: Date,
        endTimes: [[String: Any]]
    ) -> Date? {
        guard endTimes.count > 1,
              let place = PronoteJSON.number(lesson["place"]),
              let duration = PronoteJSON.number(lesson["duree"]) else {
            return nil
        }
        var endIndex = Int(place) % (endTimes.count - 1) + Int(duration) - 1
        if endIndex > endTimes.count {
            endIndex %= endTimes.count - 1
        }
        guard let timeText = endTimes.first(where: {
            Int(PronoteJSON.number($0["G"]) ?? -1) == endIndex
        }).flatMap({ PronoteJSON.string($0["L"]) }) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "HH'h'mm"
        guard let parsedTime = formatter.date(from: timeText) else {
            return nil
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: parsedTime)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: start
        )
    }

    private static func protocolHomework(
        from item: [String: Any]
    ) -> Homework? {
        guard let due = PronoteJSON.date(item["PourLe"]),
              let subjectValue = (item["Matiere"] as? [String: Any])?["V"] ?? item["Matiere"] else {
            return nil
        }
        let subjectName = extractName(subjectValue) ?? "Matière"
        let subject = Subject(
            id: stableID(prefix: "subject", value: extractID(subjectValue) ?? subjectName),
            name: subjectName
        )
        let details = PronoteJSON.string(item["descriptif"]) ?? ""
        let title = PronoteJSON.string(item["titre"]) ?? subjectName
        let rawID = extractID(item) ?? "\(subjectName)|\(title)|\(due.timeIntervalSince1970)|\(details)"
        return Homework(
            id: stableID(prefix: "homework", value: rawID),
            subject: subject,
            title: title,
            details: HomeworkDescriptionFormatter.plainText(from: details),
            dueDate: due,
            isDone: PronoteJSON.bool(item["TAFFait"]) ?? false,
            priority: .unspecified,
            attachments: protocolAttachments(from: item)
        )
    }

    private static func protocolAttachments(
        from homework: [String: Any]
    ) -> [HomeworkAttachment] {
        guard let wrapped = homework["ListePieceJointe"] as? [String: Any],
              let values = wrapped["V"] as? [[String: Any]] else {
            return []
        }

        return values.compactMap { item in
            guard let protocolID = PronoteJSON.string(item["N"]),
                  let name = PronoteJSON.string(item["L"]) else {
                return nil
            }
            let rawType = PronoteJSON.number(item["G"])
            let kind = rawType.flatMap { HomeworkAttachment.Kind(rawValue: Int($0)) } ?? .unsupported
            let linkURL = kind == .link
                ? (PronoteJSON.string(item["url"]) ?? name)
                : nil
            return HomeworkAttachment(
                protocolID: protocolID,
                name: name,
                kind: kind,
                linkURL: linkURL
            )
        }
    }

    private static func protocolGrade(
        from item: [String: Any]
    ) -> Grade? {
        guard let value = PronoteJSON.number(item["note"]),
              let date = PronoteJSON.date(item["date"]),
              let subjectValue = (item["service"] as? [String: Any])?["V"] ?? item["service"] else {
            return nil
        }

        let outOf = PronoteJSON.number(item["bareme"]) ?? 20
        let coefficient = PronoteJSON.number(item["coefficient"]) ?? 1
        let subjectName = extractName(subjectValue) ?? "Matière"
        let subject = Subject(
            id: stableID(prefix: "subject", value: extractID(subjectValue) ?? subjectName),
            name: subjectName
        )
        let title = PronoteJSON.string(item["commentaire"])
        let rawID = extractID(item) ?? "\(subjectName)|\(value)|\(outOf)|\(date.timeIntervalSince1970)|\(title ?? "")"
        return Grade(
            id: stableID(prefix: "grade", value: rawID),
            subject: subject,
            value: value,
            outOf: outOf,
            coefficient: coefficient,
            date: date,
            title: title
        )
    }

    private static func protocolGradeRejection(
        for item: [String: Any]
    ) -> PronoteGradeRejection {
        guard PronoteJSON.number(item["note"]) != nil else {
            return .missingOrInvalidValue
        }
        guard PronoteJSON.date(item["date"]) != nil else {
            return .missingOrInvalidDate
        }
        guard let subject = (item["service"] as? [String: Any])?["V"] ?? item["service"],
              extractName(subject) != nil else {
            return .missingSubject
        }
        return .missingOrInvalidValue
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
