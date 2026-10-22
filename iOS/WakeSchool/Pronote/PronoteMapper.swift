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

    // MARK: - Absences et retards

    /// Convertit une réponse « PagePresence » PRONOTE en évènements de vie scolaire.
    ///
    /// Contrat confirmé via pronotepy (`Period.absences` / `Period.delays`) :
    /// une liste mixte `listeAbsences.V` contenant des items identifiés par `G`
    /// (13 = absence, 14 = retard). Toute autre valeur de `G` est ignorée.
    ///
    /// Lève `PronoteMapperError.invalidResponse` si `listeAbsences` est absente ou
    /// mal formée : une réponse invalide ne doit JAMAIS être interprétée comme une
    /// liste vide valide (sinon `syncAttendance` effacerait les données locales).
    static func attendance(from response: Any) throws -> [AttendanceEvent] {
        guard let items = protocolItems(from: response, keys: ["listeAbsences", "ListeAbsences"]) else {
            throw PronoteMapperError.invalidResponse("listeAbsences absente ou mal formée")
        }

        var result: [AttendanceEvent] = []
        for item in items {
            switch attendanceKind(item) {
            case .absence:
                if let event = absence(item) { result.append(event) }
            case .delay:
                if let event = delay(item) { result.append(event) }
            case nil:
                continue // Autre type d'évènement PRONOTE (punition…) : ignoré.
            }
        }

        var seen = Set<UUID>()
        return result
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.start > $1.start }
    }

    /// Nature de l'item selon son code `G` : 13 = absence, 14 = retard.
    /// Renvoie nil pour toute autre valeur (punition G=41, etc.) : item ignoré.
    private static func attendanceKind(_ item: [String: Any]) -> AttendanceKind? {
        switch PronoteJSON.number(item["G"]) {
        case 13: return .absence
        case 14: return .delay
        default: return nil
        }
    }

    private static func absence(_ item: [String: Any]) -> AttendanceEvent? {
        // dateDebut/dateFin typées "V" (dd/MM/yyyy HH:mm:ss) — cf. pronotepy Absence.
        guard let start = PronoteJSON.date(item["dateDebut"]) else { return nil }
        let end = PronoteJSON.date(item["dateFin"])

        let rawID = extractID(item["N"]) ?? "absence|\(start.timeIntervalSince1970)|\(end?.timeIntervalSince1970 ?? 0)"
        let id = stableID(prefix: "attendance", value: rawID)
        // Durée : NbrHeures (« 2 ») ou calculée depuis dateDebut/dateFin. Aucune invention.
        let duration = minutesDuration(from: item) ?? end.map { Int($0.timeIntervalSince(start) / 60) }

        return AttendanceEvent(
            id: id,
            kind: .absence,
            start: start,
            end: end,
            durationMinutes: duration,
            isJustified: PronoteJSON.bool(item["justifie"]) ?? false,
            justification: nil,
            reasons: reasons(from: item),
            subjectName: extractName(findValue(in: item, keys: ["matiere", "Matiere"]))
        )
    }

    private static func delay(_ item: [String: Any]) -> AttendanceEvent? {
        guard let start = PronoteJSON.date(item["date"]) else { return nil }

        let rawID = extractID(item["N"]) ?? "retard|\(start.timeIntervalSince1970)"
        let id = stableID(prefix: "attendance", value: rawID)
        // Durée en minutes : champ `duree` (entier, confirmé par pronotepy Delay).
        let duration = PronoteJSON.number(item["duree"]).map { Int($0.rounded()) }

        return AttendanceEvent(
            id: id,
            kind: .delay,
            start: start,
            end: nil,
            durationMinutes: duration,
            isJustified: PronoteJSON.bool(item["justifie"]) ?? false,
            justification: PronoteJSON.string(item["justification"]),
            reasons: reasons(from: item),
            subjectName: extractName(findValue(in: item, keys: ["matiere", "Matiere"]))
        )
    }

    /// Durée d'une absence en minutes : `NbrHeures` (« 2 », « 1,5 ») quand fourni.
    private static func minutesDuration(from item: [String: Any]) -> Int? {
        guard let raw = PronoteJSON.string(item["NbrHeures"]) else { return nil }
        return parseHourDuration(raw)
    }

    private static func parseHourDuration(_ raw: String) -> Int? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        if let value = PronoteJSON.number(cleaned) {
            // Valeur décimale interprétée en heures (ex. « 1,5 » => 90 min).
            return Int((value * 60).rounded())
        }
        guard let hourRange = cleaned.range(of: #"^(\d+)h"#, options: .regularExpression) else { return nil }
        guard let hours = Int(cleaned[hourRange].replacingOccurrences(of: "h", with: "")) else { return nil }
        let minutePart = cleaned[hourRange.upperBound...].prefix { $0.isNumber }
        return hours * 60 + (Int(minutePart) ?? 0)
    }

    /// Motifs : chaîne simple, ou liste de libellés/dictionnaires PRONOTE.
    private static func reasons(from item: [String: Any]) -> [String] {
        let value = findValue(in: item, keys: ["motifs", "listeMotifs", "Motifs", "reasons"])
        if let list = value as? [[String: Any]] {
            return list.compactMap { extractName($0) ?? PronoteJSON.string($0["L"]) }
        }
        if let list = value as? [String] {
            return list
        }
        if let wrapped = value as? [String: Any], let list = wrapped["V"] as? [[String: Any]] {
            return list.compactMap { extractName($0) ?? PronoteJSON.string($0["L"]) }
        }
        if let single = PronoteJSON.string(value), !single.isEmpty {
            return [single]
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

    static func homework(from response: Any, accountScope: String? = nil) -> [Homework] {
        if let items = protocolItems(from: response, keys: ["ListeTravauxAFaire"]) {
            return items.compactMap { protocolHomework(from: $0, accountScope: accountScope) }.sorted { $0.dueDate < $1.dueDate }
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
            
            // Extraire l'identifiant natif PRONOTE si présent
            let pronoteID = extractID(item)
            
            // Générer un UUID stable cohérent avec le chemin protocole
            let id = makeStableHomeworkID(
                pronoteID: pronoteID,
                subjectID: subject.id,
                dueDate: due,
                title: title,
                accountScope: accountScope
            )
            guard seen.insert(id).inserted else { continue }
            result.append(Homework(
                id: id,
                subject: subject,
                title: title,
                details: details,
                dueDate: due,
                isDone: done,
                priority: priority,
                attachments: protocolAttachments(from: item),
                pronoteID: pronoteID
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
                guard let grade = protocolGrade(from: item) else {
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
            // Statut non numérique (ABS…) : conservé tel quel, jamais converti en 0.
            let value = PronoteJSON.number(findValue(in: item, keys: ["note", "Note", "valeur", "grade"]))
            let status = gradeValueStatus(findValue(in: item, keys: ["note", "Note", "valeur", "grade"]))
            guard value != nil || status != nil else {
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
            let rawID = extractID(item) ?? "\(subjectName)|\(value?.description ?? status?.rawValue ?? "?")|\(outOf)|\(date.timeIntervalSince1970)|\(title ?? "")"
            let id = stableID(prefix: "grade", value: rawID)
            guard seen.insert(id).inserted else {
                rejected[PronoteGradeRejection.duplicate.rawValue, default: 0] += 1
                continue
            }
            let grade: Grade
            if let value = value {
                grade = Grade(id: id, subject: subject, value: value, outOf: outOf, coefficient: coefficient, date: date, title: title)
            } else {
                grade = Grade(id: id, subject: subject, status: status ?? .absent, outOf: outOf, coefficient: coefficient, date: date, title: title)
            }
            result.append(grade)
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

    /// Contrôles (DS) à venir extraits de la réponse EMPLOI DU TEMPS.
    ///
    /// Contrat PRONOTE confirmé via pronotepy (`Lesson.test`) : un devoir
    /// surveillé est un item de `ListeCours` dont le sous-objet
    /// `cahierDeTextes.V.estDevoir` vaut vrai. Le titre est la description
    /// du cahier de textes si fournie — aucune donnée inventée.
    static func exams(from response: Any) -> [Exam] {
        if let lessons = protocolItems(from: response, keys: ["ListeCours"]) {
            return examsFromLessons(lessons)
        }

        // Réponse non conforme au protocole : même heuristique de secours que
        // l'emploi du temps — sinon les DS disparaissent TOTALEMENT alors que
        // les cours restent affichés via leur propre fallback.
        let root = PronoteJSON.unwrap(response)
        let candidates = collectDictionaries(root)
        let lessons = candidates.filter { dictionary in
            nestedValue(dictionary, keys: ["cahierDeTextes", "estDevoir"]) != nil
        }
        guard !lessons.isEmpty else { return [] }
        return examsFromLessons(lessons)
    }

    private static func examsFromLessons(_ lessons: [[String: Any]]) -> [Exam] {
        var result: [Exam] = []
        var seen = Set<UUID>()
        for lesson in lessons {
            guard PronoteJSON.bool(nestedValue(lesson, keys: ["cahierDeTextes", "estDevoir"])) == true,
                  let date = PronoteJSON.date(lesson["DateDuCours"]) else {
                continue
            }
            let contents = (lesson["ListeContenus"] as? [String: Any])?["V"] as? [[String: Any]] ?? []
            let subjectContent = contents.first { PronoteJSON.number($0["G"]) == 16 }
            let subjectName = extractName(subjectContent) ?? "Matière"
            let subject = Subject(id: stableID(prefix: "subject", value: extractID(subjectContent) ?? subjectName), name: subjectName)

            let description = examDescription(lesson)
            let title = description.map { HomeworkDescriptionFormatter.plainText(from: $0) }
                .flatMap { $0.isEmpty ? nil : $0 } ?? "Devoir surveillé"

            let rawID = extractID(lesson) ?? "\(subjectName)|\(date.timeIntervalSince1970)|exam"
            let id = stableID(prefix: "exam", value: rawID)
            guard seen.insert(id).inserted else { continue }
            result.append(Exam(id: id, subject: subject, date: date, title: title))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Lit `keys` successivement dans un dictionnaire imbriqué en gérant
    /// les enveloppes PRONOTE typées ({"_T": n, "V": …}).
    private static func nestedValue(_ dictionary: [String: Any], keys: [String]) -> Any? {
        var current: Any = dictionary
        for key in keys {
            guard let dict = current as? [String: Any],
                  let value = dict[key] else { return nil }
            // Enveloppe typée : {"_T": n, "V": …} → descendre dans "V".
            if let wrapped = value as? [String: Any], let inner = wrapped["V"] {
                current = inner
            } else {
                current = value
            }
        }
        return current
    }

    /// Description d'un DS : `descriptif.V` est soit une chaîne (ou enveloppe),
    /// soit une LISTE d'items de contenu PRONOTE (chaque item porte un `L`).
    private static func examDescription(_ lesson: [String: Any]) -> String? {
        if let text = PronoteJSON.string(nestedValue(lesson, keys: ["cahierDeTextes", "descriptif"])) {
            return text
        }
        guard let contents = nestedValue(lesson, keys: ["cahierDeTextes", "descriptif"]) as? [[String: Any]] else {
            return nil
        }
        let labels = contents.compactMap { extractName($0) }
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
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

        // Contrat PRONOTE (confirmé via pronotepy Lesson) : seul `estAnnule` est un
        // drapeau fiable ; `Statut` (texte libre) et `memo` décrivent le changement.
        // Aucun champ de lien initial↔remplacement n'est présent dans la réponse :
        // WakeSchool n'invente donc JAMAIS de rapprochement entre deux cours.
        let cancelled = PronoteJSON.bool(lesson["estAnnule"]) ?? false
        let statusText = PronoteJSON.string(lesson["Statut"])
        let memoText = PronoteJSON.string(lesson["memo"])
        // Un cours non annulé dont le Statut décrit un changement (professeur ou
        // matière remplacé) est marqué « modifié » pour être visible dans l'UI.
        let modified = !cancelled && modificationStatusText(statusText) != nil

        return TimetableEntry(
            id: id,
            subject: subject,
            teacher: teacher,
            room: rooms.isEmpty ? nil : rooms.joined(separator: ", "),
            start: start,
            end: end,
            isCancelled: cancelled,
            isModified: modified,
            changeNote: [statusText, memoText].compactMap { $0 }.joined(separator: " — ").isEmpty
                ? nil
                : [statusText, memoText].compactMap { $0 }.joined(separator: " — ")
        )
    }

    /// Détecte, dans le texte libre `Statut` de PRONOTE, un changement de cours
    /// (professeur remplacé, matière remplacée…). Aucune déduction au-delà du texte :
    /// si le texte ne décrit pas un remplacement, la fonction renvoie nil.
    private static func modificationStatusText(_ status: String?) -> String? {
        guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines),
              !status.isEmpty else {
            return nil
        }
        let lowered = status.lowercased()
        let markers = ["remplac", "professeur remplacé", "prof remplacé", "modifié", "modifie", "chang"]
        return markers.contains { lowered.contains($0) } ? status : nil
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
        from item: [String: Any],
        accountScope: String? = nil
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
        
        // Extraire l'identifiant natif PRONOTE (champ "N")
        let pronoteID = extractID(item)
        
        // Générer un UUID stable : basé sur pronoteID si dispo, sinon clé métier stable
        let id = makeStableHomeworkID(
            pronoteID: pronoteID,
            subjectID: subject.id,
            dueDate: due,
            title: title,
            accountScope: accountScope
        )
        
        return Homework(
            id: id,
            subject: subject,
            title: title,
            details: HomeworkDescriptionFormatter.plainText(from: details),
            dueDate: due,
            isDone: PronoteJSON.bool(item["TAFFait"]) ?? false,
            priority: .unspecified,
            attachments: protocolAttachments(from: item),
            pronoteID: pronoteID
        )
    }

    /// Génère un UUID déterministe pour un devoir.
    /// - Si `pronoteID` est fourni : UUID v5 (namespace DNS) dérivé de "homework:pronote:<accountScope>:<pronoteID>".
    /// - Sinon : UUID v5 dérivé de la clé métier stable "homework:business:<subjectID>:<jour>:<titleNormalisé>".
    /// L'`accountScope` (optionnel) permet d'isoler les identifiants PRONOTE entre plusieurs comptes/établissements.
    /// Cela garantit que le même devoir produit toujours le même UUID,
    /// indépendamment des variations de description HTML ou de formatage.
    private static func makeStableHomeworkID(
        pronoteID: String?,
        subjectID: UUID,
        dueDate: Date,
        title: String,
        accountScope: String? = nil
    ) -> UUID {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: dueDate)
        let dayInterval = day.timeIntervalSince1970
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        let seed: String
        if let pronoteID = pronoteID, !pronoteID.isEmpty {
            if let accountScope = accountScope, !accountScope.isEmpty {
                seed = "homework:pronote:\(accountScope):\(pronoteID)"
            } else {
                seed = "homework:pronote:\(pronoteID)"
            }
        } else {
            seed = "homework:business:\(subjectID.uuidString):\(Int(dayInterval)):\(normalizedTitle)"
        }
        
        // UUID v5 (SHA-1 namespace DNS) — déterministe, stable, sans collision pratique
        let namespace = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")! // DNS namespace
        var hasher = Insecure.SHA1()
        hasher.update(data: namespace.uuidString.data(using: .ascii)!)
        hasher.update(data: seed.data(using: .utf8)!)
        let digest = hasher.finalize()
        var uuidBytes = Array(digest.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x50 // version 5
        uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80 // variant RFC 4122
        return UUID(uuid: (uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                           uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                           uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                           uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]))
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

    /// Statut non numérique d'une note PRONOTE (« ABS », « Disp », « NA »…).
    /// Une note numérique est prioritaire ; seul un texte non convertible en nombre,
    /// reconnu comme statut connu, est conservé comme évaluation non numérique.
    private static func gradeValueStatus(_ noteValue: Any?) -> GradeValueStatus? {
        guard let text = PronoteJSON.string(noteValue) else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "abs", "absent": return .absent
        case "disp", "dispensé", "dispense": return .dispensed
        case "na", "n.a", "non évalué", "non evalue": return .notAssessed
        default: return nil
        }
    }

    private static func protocolGrade(
        from item: [String: Any]
    ) -> Grade? {
        guard let date = PronoteJSON.date(item["date"]),
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

        // Statut non numérique (ABS…) : conservé tel quel, jamais converti en 0.
        if let status = gradeValueStatus(item["note"]) {
            let rawID = extractID(item) ?? "\(subjectName)|\(status.rawValue)|\(outOf)|\(date.timeIntervalSince1970)|\(title ?? "")"
            return Grade(
                id: stableID(prefix: "grade", value: rawID),
                subject: subject,
                status: status,
                outOf: outOf,
                coefficient: coefficient,
                date: date,
                title: title
            )
        }

        guard let value = PronoteJSON.number(item["note"]) else {
            return nil
        }
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
        // Un statut non numérique (ABS…) n'est pas un rejet : il est mappé.
        guard PronoteJSON.number(item["note"]) != nil || gradeValueStatus(item["note"]) != nil else {
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
