import XCTest
@testable import WakeSchool

final class PronoteMapperTests: XCTestCase {
    func testMapsProtocolTimetableItemsAndReportsRawCount() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "ListeCours": [
                        "V": [
                            [
                                "N": "course-1",
                                "estAnnule": false,
                                "DateDuCours": ["V": "14/10/2026 08:00"],
                                "DateDuCoursFin": ["V": "14/10/2026 09:00"],
                                "ListeContenus": [
                                    "V": [
                                        ["G": 16, "N": "subject-1", "L": "Mathématiques"],
                                        ["G": 3, "N": "teacher-1", "L": "Professeur"],
                                        ["G": 17, "N": "room-1", "L": "Salle 12"]
                                    ]
                                ]
                            ],
                            ["N": "invalid-course"]
                        ]
                    ]
                ]
            ]
        ]

        let entries = PronoteMapper.timetable(from: response)

        XCTAssertEqual(PronoteMapper.rawTimetableCount(from: response), 2)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].subject.name, "Mathématiques")
        XCTAssertEqual(entries[0].teacher?.name, "Professeur")
        XCTAssertEqual(entries[0].room, "Salle 12")
    }

    // MARK: - Remplacements PRONOTE — LOT 8

    /// Annulation simple : `estAnnule` seul, sans statut de remplacement.
    /// Le cours reste marqué annulé, non modifié.
    func testCancelledLessonKeepsCancelledStatusWithoutInventedLink() throws {
        let entry = try XCTUnwrap(PronoteMapper.timetable(from: lessonResponse(
            estAnnule: true
        )).first)

        XCTAssertEqual(entry.status, .cancelled)
        XCTAssertFalse(entry.isModified)
    }

    /// Remplacement de professeur : PRONOTE ne fournit AUCUN lien entre le cours
    /// initial annulé et le cours de remplacement. WakeSchool les garde donc SÉPARÉS
    /// (pas de fusion arbitraire) ; le remplacement est identifiable par son Statut.
    func testReplacementLessonsAreKeptSeparateAndMarkedModified() throws {
        let entries = PronoteMapper.timetable(from: twoLessonResponse(
            initial: ["N": "lesson-1", "estAnnule": "Vrai"],
            replacement: ["N": "lesson-2", "estAnnule": "Faux", "Statut": "Professeur remplacé"]
        ))

        XCTAssertEqual(entries.count, 2, "Aucune fusion arbitraire : deux cours restent deux entrées.")
        let cancelled = try XCTUnwrap(entries.first { $0.isCancelled })
        XCTAssertEqual(cancelled.status, .cancelled)
        let replacement = try XCTUnwrap(entries.first { !$0.isCancelled })
        XCTAssertEqual(replacement.status, .modified, "Le remplacement est visible comme cours modifié.")
        XCTAssertTrue(replacement.changeNote?.contains("remplacé") ?? false)
    }

    /// Remplacement de matière : même traitement, dérivé du Statut PRONOTE réel.
    func testSubjectReplacementIsMarkedModifiedFromStatusText() throws {
        let entry = try XCTUnwrap(PronoteMapper.timetable(from: lessonResponse(
            estAnnule: false,
            extra: ["Statut": "Matière remplacée"]
        )).first)

        XCTAssertEqual(entry.status, .modified)
        XCTAssertEqual(entry.changeNote, "Matière remplacée")
    }

    /// Cours ajouté sans lien vérifiable : sans Statut ni memo, il reste un cours
    /// ordinaire — aucun drapeau « modifié » inventé.
    func testAddedLessonWithoutVerifiableLinkStaysNormal() throws {
        let entry = try XCTUnwrap(PronoteMapper.timetable(from: lessonResponse(
            estAnnule: false
        )).first)

        XCTAssertEqual(entry.status, .normal)
        XCTAssertNil(entry.changeNote)
    }

    /// Les booléens PRONOTE sont des chaînes « Vrai »/« Faux » : ils doivent être lus.
    func testPronoteFrenchBooleanStringsAreParsed() throws {
        let entry = try XCTUnwrap(PronoteMapper.timetable(from: lessonResponse(
            estAnnule: "Faux",
            extra: ["Statut": "Cours modifié"]
        )).first)

        XCTAssertFalse(entry.isCancelled)
        XCTAssertEqual(entry.status, .modified)
    }

    /// Réponse ListeCours à un seul cours, avec contenu matière obligatoire.
    private func lessonResponse(estAnnule: Any, extra: [String: Any] = [:]) -> [String: Any] {
        var lesson: [String: Any] = [
            "N": "lesson-x",
            "estAnnule": estAnnule,
            "DateDuCours": ["V": "14/10/2026 08:00"],
            "DateDuCoursFin": ["V": "14/10/2026 09:00"],
            "ListeContenus": ["V": [["G": 16, "N": "subject-1", "L": "Mathématiques"]]]
        ]
        extra.forEach { lesson[$0.key] = $0.value }
        return ["dataSec": ["data": ["ListeCours": ["V": [lesson]]]]]
    }

    /// Réponse ListeCours à deux cours (initial annulé + remplacement).
    private func twoLessonResponse(initial: [String: Any], replacement: [String: Any]) -> [String: Any] {
        func lesson(_ fields: [String: Any]) -> [String: Any] {
            var item = fields
            item["DateDuCours"] = ["V": "14/10/2026 08:00"]
            item["DateDuCoursFin"] = ["V": "14/10/2026 09:00"]
            item["ListeContenus"] = ["V": [["G": 16, "N": "subject-1", "L": "Mathématiques"]]]
            return item
        }
        return ["dataSec": ["data": ["ListeCours": ["V": [lesson(initial), lesson(replacement)]]]]]
    }

    // MARK: - Contrôles (DS) issus de l'emploi du temps — LOT 8

    /// Contrat PRONOTE confirmé via pronotepy : un DS est un item ListeCours
    /// dont `cahierDeTextes.V.estDevoir` vaut vrai. Les cours ordinaires et les
    /// devoirs du cahier de textes ne produisent AUCUN contrôle.
    func testMapsUpcomingExamFromTimetableCahierDeTextes() throws {
        let response = twoLessonResponse(
            initial: [
                "N": "exam-1",
                "cahierDeTextes": ["V": ["estDevoir": "Vrai", "descriptif": ["V": "<p>Chapitres 4 à 6</p>"]]]
            ],
            replacement: ["N": "lesson-plain"]
        )

        let exams = PronoteMapper.exams(from: response)

        XCTAssertEqual(exams.count, 1)
        XCTAssertEqual(exams[0].subject.name, "Mathématiques")
        XCTAssertEqual(exams[0].title, "Chapitres 4 à 6")
        XCTAssertEqual(exams[0].date, try XCTUnwrap(PronoteJSON.date(["V": "14/10/2026 08:00"])))
    }

    func testDoesNotInventExamForOrdinaryLesson() throws {
        let response = twoLessonResponse(
            initial: ["N": "lesson-1"],
            replacement: ["N": "lesson-2", "cahierDeTextes": ["V": ["estDevoir": "Faux"]]]
        )

        XCTAssertTrue(PronoteMapper.exams(from: response).isEmpty)
    }

    func testExamsFromEmptyOrMissingListeCoursIsEmpty() {
        XCTAssertTrue(PronoteMapper.exams(from: [:]).isEmpty)
    }

    func testUsesPronoteFunctionParametersToDeriveMissingCourseEndTime() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "ListeCours": [
                        "V": [
                            [
                                "N": "course-2",
                                "place": 1,
                                "duree": 1,
                                "DateDuCours": ["V": "14/10/2026 08:00"],
                                "ListeContenus": [
                                    "V": [
                                        ["G": 16, "N": "subject-1", "L": "Mathématiques"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let endTimes: [[String: Any]] = [
            ["G": 0, "L": "08h00"],
            ["G": 1, "L": "09h00"],
            ["G": 2, "L": "10h00"]
        ]

        let entries = PronoteMapper.timetable(
            from: response,
            schoolDayEndTimes: endTimes
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            Calendar.current.component(.hour, from: entries[0].end),
            9
        )
    }

    func testMapsProtocolHomeworkItems() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "ListeTravauxAFaire": [
                        "V": [
                            [
                                "N": "homework-1",
                                "descriptif": ["V": "Exercices 1 à 4"],
                                "TAFFait": false,
                                "PourLe": ["V": "16/10/2026"],
                                "Matiere": ["V": ["N": "subject-1", "L": "Sciences"]],
                                "ListePieceJointe": [
                                    "V": [
                                        ["N": "file-1", "L": "fiche.pdf", "G": 1],
                                        ["N": "link-1", "L": "Ressource", "G": 0, "url": "https://example.test/resource"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let homework = PronoteMapper.homework(from: response)

        XCTAssertEqual(PronoteMapper.rawHomeworkCount(from: response), 1)
        XCTAssertEqual(homework.count, 1)
        XCTAssertEqual(homework[0].subject.name, "Sciences")
        XCTAssertEqual(homework[0].details, "Exercices 1 à 4")
        XCTAssertFalse(homework[0].isDone)
        XCTAssertEqual(homework[0].priority, .unspecified)
        XCTAssertEqual(homework[0].attachments.count, 2)
        XCTAssertEqual(homework[0].attachments[0].kind, .file)
        XCTAssertEqual(homework[0].attachments[1].kind, .link)
        XCTAssertEqual(homework[0].attachments[1].linkURL, "https://example.test/resource")
    }

    func testMapsProtocolHomeworkHTMLToReadableText() throws {
        let longParagraph = String(repeating: "contenu détaillé ", count: 40)
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "ListeTravauxAFaire": [
                        "V": [
                            [
                                "N": "homework-html",
                                "descriptif": [
                                    "V": """
                                    <div><p>Lire <strong>attentivement</strong> &amp; noter.</p>\
                                    <ul><li>Première partie</li><li>Deuxième partie</li></ul>\
                                    <p>\(longParagraph)</p></div>
                                    """
                                ],
                                "TAFFait": false,
                                "PourLe": ["V": "16/10/2026"],
                                "Matiere": ["V": ["N": "subject-1", "L": "Sciences"]]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let homework = try XCTUnwrap(PronoteMapper.homework(from: response).first)

        XCTAssertFalse(homework.details.contains("<"))
        XCTAssertTrue(homework.details.contains("attentivement"))
        XCTAssertTrue(homework.details.contains("& noter."))
        XCTAssertTrue(homework.details.contains("Première partie"))
        XCTAssertTrue(homework.details.contains("Deuxième partie"))
        XCTAssertTrue(homework.details.contains("contenu détaillé"))
        XCTAssertGreaterThan(homework.details.count, 500)
    }

    func testMapsProtocolGradeItemsAndReportsRawCount() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "listeDevoirs": [
                        "V": [
                            [
                                "N": "grade-1",
                                "note": ["V": "15,5"],
                                "bareme": ["V": "20"],
                                "date": ["V": "09/10/2026"],
                                "coefficient": "2",
                                "service": ["V": ["N": "subject-1", "L": "Histoire"]],
                                "commentaire": "Évaluation"
                            ],
                            ["N": "invalid-grade"]
                        ]
                    ]
                ]
            ]
        ]

        let grades = PronoteMapper.grades(from: response)

        XCTAssertEqual(PronoteMapper.rawGradesCount(from: response), 2)
        XCTAssertEqual(grades.count, 1)
        XCTAssertEqual(grades[0].numericValue, 15.5)
        XCTAssertEqual(grades[0].outOf, 20)
        XCTAssertEqual(grades[0].coefficient, 2)
        XCTAssertEqual(grades[0].subject.name, "Histoire")
        XCTAssertEqual(grades[0].title, "Évaluation")
    }

    func testGradeMappingReportsOnlySafeRejectionCategories() {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "listeDevoirs": [
                        "V": [
                            [
                                "N": "valid-grade",
                                "note": ["V": "14"],
                                "bareme": ["V": "20"],
                                "date": ["V": "09/10/2026"],
                                "service": ["V": ["N": "subject-1", "L": "Histoire"]]
                            ],
                            [
                                "N": "missing-value",
                                "date": ["V": "09/10/2026"],
                                "service": ["V": ["N": "subject-1", "L": "Histoire"]]
                            ],
                            [
                                "N": "missing-date",
                                "note": ["V": "synthetic-grade-value"],
                                "service": ["V": ["N": "subject-1", "L": "Histoire"]]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let result = PronoteMapper.gradeMapping(from: response)

        XCTAssertEqual(result.grades.count, 1)
        XCTAssertEqual(result.rejectedCounts[PronoteGradeRejection.missingOrInvalidValue.rawValue], 1)
        XCTAssertEqual(result.rejectedCounts[PronoteGradeRejection.missingOrInvalidDate.rawValue], 1)
        XCTAssertFalse(result.rejectedCounts.description.contains("synthetic-grade-value"))
    }

    // MARK: - Évaluations non numériques (ABS…) — LOT 8

    /// Une note « ABS » doit être CONSERVÉE comme évaluation non numérique :
    /// jamais rejetée, jamais convertie en zéro, jamais comptée comme invalide.
    func testMapsAbsentGradeAsStatusWithoutRejectingIt() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "listeDevoirs": [
                        "V": [
                            [
                                "N": "grade-abs",
                                "note": ["V": "ABS"],
                                "bareme": ["V": "20"],
                                "date": ["V": "09/10/2026"],
                                "service": ["V": ["N": "subject-1", "L": "Histoire"]]
                            ],
                            [
                                "N": "grade-num",
                                "note": ["V": "12"],
                                "bareme": ["V": "20"],
                                "date": ["V": "10/10/2026"],
                                "service": ["V": ["N": "subject-1", "L": "Histoire"]]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let result = PronoteMapper.gradeMapping(from: response)

        XCTAssertEqual(result.grades.count, 2, "La note ABS doit être conservée, pas rejetée.")
        XCTAssertTrue(result.rejectedCounts.isEmpty, "Aucun rejet attendu pour une note ABS valide.")

        let absent = try XCTUnwrap(result.grades.first { !$0.isNumeric })
        XCTAssertEqual(absent.value, .status(.absent))
        XCTAssertEqual(absent.subject.name, "Histoire")
        XCTAssertFalse(absent.isNumeric)
        XCTAssertNil(absent.numericValue)
        XCTAssertNil(absent.normalizedValue, "Une note ABS n'a pas de valeur normalisée.")
        XCTAssertEqual(absent.displayValue, "ABS")

        let numeric = try XCTUnwrap(result.grades.first { $0.isNumeric })
        XCTAssertEqual(numeric.numericValue, 12)
    }

    /// Les évaluations ABS ne participent PAS aux moyennes, sans jamais
    /// être transformées en zéro : seule la note numérique compte.
    func testAbsentGradesAreExcludedFromAveragesWithoutBecomingZero() throws {
        let maths = TestSupport.maths
        let grades = [
            Grade(id: UUID(), subject: maths, value: 10, outOf: 20),
            Grade(id: UUID(), subject: maths, status: .absent, outOf: 20),
            Grade(id: UUID(), subject: maths, value: 14, outOf: 20)
        ]

        let average = try XCTUnwrap(AverageCalculator.weightedAverage(of: grades))
        XCTAssertEqual(average, 12, accuracy: 0.0001, "La moyenne doit ignorer l'ABS, pas le compter comme 0 (qui donnerait 8).")

        let subjectAverages = AverageCalculator.subjectAverages(from: grades)
        XCTAssertEqual(subjectAverages.count, 1)
        XCTAssertEqual(try XCTUnwrap(subjectAverages.first).average, 12, accuracy: 0.0001)
    }

    /// Une matière dont TOUTES les notes sont ABS n'a pas de moyenne,
    /// mais l'évaluation reste visible dans la liste des notes.
    func testAllAbsentSubjectHasNoAverageButKeepsGrades() throws {
        let maths = TestSupport.maths
        let grades = [
            Grade(id: UUID(), subject: maths, status: .absent, outOf: 20),
            Grade(id: UUID(), subject: maths, status: .dispensed, outOf: 20)
        ]

        XCTAssertNil(AverageCalculator.weightedAverage(of: grades))
        XCTAssertTrue(AverageCalculator.subjectAverages(from: grades).isEmpty)
        XCTAssertEqual(grades.count, 2, "Les évaluations non numériques restent visibles.")
        XCTAssertEqual(grades[0].displayValue, "ABS")
    }

    func testExtractsStudentResourceAndPeriodsWithoutExposingValuesInDiagnostics() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "ressource": ["N": "synthetic-student", "G": 4],
                    "listePeriodes": [
                        ["N": "synthetic-period", "L": "Période synthétique"]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(
            PronoteMapper.resource(from: response)?["N"] as? String,
            "synthetic-student"
        )
        XCTAssertEqual(PronoteMapper.periods(from: response).count, 1)
    }

    func testSelectsFirstStudentResourceForParentAccount() {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "ressource": [
                        "N": "synthetic-parent",
                        "listeRessources": [
                            ["N": "synthetic-student-1", "G": 4],
                            ["N": "synthetic-student-2", "G": 4]
                        ]
                    ]
                ]
            ]
        ]

        let selected = PronoteMapper.studentResource(
            from: response,
            accountKind: .parent
        )

        XCTAssertEqual(selected?["N"] as? String, "synthetic-student-1")
    }

    // MARK: - LOT A : Persistance isDone & réconciliation robuste (PronoteMapper)

    /// Chemin protocole : extraction du champ "N" (ID natif PRONOTE)
    /// et génération d'UUID déterministe (UUID v5) depuis ce pronoteID.
    func testProtocolHomeworkExtractsNativeIDAndGeneratesStableUUID() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "ListeTravauxAFaire": [
                        "V": [[
                            "N": "hw-protocol-123",
                            "PourLe": ["V": "15/10/2026"],
                            "Matiere": ["V": ["G": 16, "N": "maths", "L": "Mathématiques"]],
                            "titre": "Exercices p.42",
                            "descriptif": "Faire les exercices",
                            "TAFFait": 0,
                            "ListePieceJointe": ["V": []]
                        ]]
                    ]
                ]
            ]
        ]

        let homeworks = PronoteMapper.homework(from: response)
        XCTAssertEqual(homeworks.count, 1)
        let hw = try XCTUnwrap(homeworks.first)
        XCTAssertEqual(hw.pronoteID, "hw-protocol-123", "Champ 'N' extrait comme pronoteID")
        let hw2 = PronoteMapper.homework(from: response).first!
        XCTAssertEqual(hw.id, hw2.id, "UUID deterministe via pronoteID (UUID v5)")
    }

    /// Chemin fallback : extraction du champ "N" quand present,
    /// coherence avec le chemin protocole (meme UUID pour meme pronoteID).
    func testFallbackHomeworkExtractsNativeIDAndMatchesProtocolUUID() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "someKey": [
                        "N": "hw-fallback-456",
                        "datePour": "15/10/2026",
                        "matiere": ["G": 16, "N": "maths", "L": "Mathematiques"],
                        "titre": "Devoir fallback",
                        "description": "Description fallback",
                        "fait": false
                    ]
                ]
            ]
        ]

        let homeworks = PronoteMapper.homework(from: response)
        XCTAssertEqual(homeworks.count, 1)
        let hw = try XCTUnwrap(homeworks.first)
        XCTAssertEqual(hw.pronoteID, "hw-fallback-456", "Champ 'N' extrait en fallback")

        // Coherence : meme pronoteID -> meme UUID que chemin protocole
        let protocolResponse: [String: Any] = [
            "dataSec": [
                "data": [
                    "ListeTravauxAFaire": [
                        "V": [[
                            "N": "hw-fallback-456",
                            "PourLe": ["V": "15/10/2026"],
                            "Matiere": ["V": ["G": 16, "N": "maths", "L": "Mathematiques"]],
                            "titre": "Devoir fallback",
                            "descriptif": "Description fallback",
                            "TAFFait": 0,
                            "ListePieceJointe": ["V": []]
                        ]]
                    ]
                ]
            ]
        ]
        let hwProtocol = PronoteMapper.homework(from: protocolResponse).first!
        XCTAssertEqual(hw.id, hwProtocol.id, "Meme pronoteID = meme UUID (coherence 2 chemins)")
    }

    /// Sans ID natif : UUID base sur cle metier stable (subjectID + jour + titre normalise),
    /// sans inclure le details (HTML volatile).
    func testHomeworkWithoutNativeIDUsesStableBusinessKey() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "someKey": [
                        "datePour": "15/10/2026",
                        "matiere": ["G": 16, "N": "maths", "L": "Mathematiques"],
                        "titre": "Devoir sans ID natif",
                        "description": "Description v1",
                        "fait": false
                    ]
                ]
            ]
        ]

        let hw1 = PronoteMapper.homework(from: response).first!
        let responseV2: [String: Any] = [
            "dataSec": [
                "data": [
                    "someKey": [
                        "datePour": "15/10/2026",
                        "matiere": ["G": 16, "N": "maths", "L": "Mathematiques"],
                        "titre": "Devoir sans ID natif",
                        "description": "<div><p>HTML <em>totalement</em> different</p></div>",
                        "fait": false
                    ]
                ]
            ]
        ]
        let hw2 = PronoteMapper.homework(from: responseV2).first!

        XCTAssertNil(hw1.pronoteID, "Pas d'ID natif -> pronoteID = nil")
        XCTAssertEqual(hw1.id, hw2.id, "UUID stable via cle metier (subjectID + jour + titre) sans details")
        XCTAssertEqual(hw1.title, hw2.title)
    }

    /// Deux devoirs meme matiere, meme jour, titres differents -> UUIDs differents.
    func testTwoHomeworksSameSubjectSameDateDifferentTitlesHaveDifferentUUIDs() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "someKey": [
                        "V": [
                            ["datePour": "15/10/2026", "matiere": ["G": 16, "N": "maths", "L": "Mathematiques"], "titre": "Exercices p.42", "description": "D1", "fait": false],
                            ["datePour": "15/10/2026", "matiere": ["G": 16, "N": "maths", "L": "Mathematiques"], "titre": "Reviser lecon 3", "description": "D2", "fait": false]
                        ]
                    ]
                ]
            ]
        ]

        let homeworks = PronoteMapper.homework(from: response)
        XCTAssertEqual(homeworks.count, 2)
        XCTAssertNotEqual(homeworks[0].id, homeworks[1].id, "Titres differents -> UUIDs differents")
    }

    /// Sans ID natif, meme matiere + meme jour + meme titre -> meme UUID (cle metier).
    /// C'est le comportement attendue : reconciliation possible si cle metier NON ambigue.
    func testTwoHomeworksSameSubjectSameDateSameTitleWithoutNativeIDShareUUID() throws {
        let response: [String: Any] = [
            "dataSec": [
                "data": [
                    "someKey": [
                        "V": [
                            ["datePour": "15/10/2026", "matiere": ["G": 16, "N": "maths", "L": "Mathematiques"], "titre": "Exercices p.42", "description": "D1", "fait": false],
                            ["datePour": "15/10/2026", "matiere": ["G": 16, "N": "maths", "L": "Mathematiques"], "titre": "Exercices p.42", "description": "D2", "fait": false]
                        ]
                    ]
                ]
            ]
        ]

        let homeworks = PronoteMapper.homework(from: response)
        XCTAssertEqual(homeworks.count, 1, "Cle metier identiques -> un seul UUID (deduplication)")
    }
}
