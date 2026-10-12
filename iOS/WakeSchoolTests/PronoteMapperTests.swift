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
                                "Matiere": ["V": ["N": "subject-1", "L": "Sciences"]]
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
        XCTAssertEqual(grades[0].value, 15.5)
        XCTAssertEqual(grades[0].outOf, 20)
        XCTAssertEqual(grades[0].coefficient, 2)
        XCTAssertEqual(grades[0].subject.name, "Histoire")
        XCTAssertEqual(grades[0].title, "Évaluation")
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
}
