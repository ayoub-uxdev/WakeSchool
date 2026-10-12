import XCTest
@testable import WakeSchool

final class PronoteSessionClientTests: XCTestCase {
    func testHomeworkAttachmentUsesAuthenticatedSessionURL() async throws {
        let transport = SessionRequestFakeTransport()
        let session = PronoteAuthenticationResult(
            sessionID: "synthetic-session",
            spaceID: 3,
            rootURL: URL(string: "https://example.test/pronote/")!,
            version: [2026, 2, 7],
            requestNumber: 3,
            sessionKey: Data(repeating: 0x11, count: 16),
            sessionIV: Data(repeating: 0x22, count: 16),
            requestsAreEncrypted: false,
            requestsAreCompressed: false,
            userName: nil,
            mobileToken: nil,
            initialParameters: nil
        )
        let attachment = HomeworkAttachment(
            protocolID: "synthetic-document",
            name: "fiche de travail.pdf",
            kind: .file,
            linkURL: nil
        )

        let data = try await PronoteSessionClient(
            transport: transport,
            session: session
        ).downloadHomeworkAttachment(attachment)

        XCTAssertEqual(data, Data("synthetic-file-content".utf8))
        let url = try XCTUnwrap(transport.downloadURL)
        XCTAssertEqual(url.host, "example.test")
        XCTAssertTrue(url.path.contains("/FichiersExternes/"))
        XCTAssertTrue(url.path.hasSuffix("/fiche de travail.pdf"))
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "Session" })?
                .value,
            "synthetic-session"
        )
    }

    func testDataRequestsUsePronoteStudentAndPeriodPayloads() async throws {
        let transport = SessionRequestFakeTransport()
        let session = PronoteAuthenticationResult(
            sessionID: "123",
            spaceID: 3,
            rootURL: URL(string: "https://example.test/pronote/")!,
            version: [2026, 2, 7],
            requestNumber: 3,
            sessionKey: Data(repeating: 0x11, count: 16),
            sessionIV: Data(repeating: 0x22, count: 16),
            requestsAreEncrypted: false,
            requestsAreCompressed: false,
            userName: nil,
            mobileToken: nil,
            initialParameters: nil
        )
        let client = PronoteSessionClient(transport: transport, session: session)
        let resource: [String: Any] = ["N": "synthetic-student", "G": 4]
        let period: [String: Any] = ["N": "synthetic-period", "L": "Période synthétique"]

        _ = try await client.timetable(weekNumber: 7, resource: resource)
        _ = try await client.homework(
            resource: resource,
            weekRange: 7...13
        )
        _ = try await client.grades(period: period, resource: resource)

        XCTAssertEqual(transport.requests.count, 3)
        assertRequest(
            transport.requests[0],
            function: "PageEmploiDuTemps",
            tab: 16,
            resource: resource,
            expectedData: { data in
                XCTAssertEqual(data["numeroSemaine"] as? Int, 7)
                XCTAssertEqual(
                    (data["ressource"] as? [String: Any])?["N"] as? String,
                    "synthetic-student"
                )
            }
        )
        assertRequest(
            transport.requests[1],
            function: "PageCahierDeTexte",
            tab: 88,
            resource: resource,
            expectedData: { data in
                let domain = data["domaine"] as? [String: Any]
                XCTAssertEqual(domain?["_T"] as? Int, 8)
                XCTAssertEqual(domain?["V"] as? String, "[7..13]")
                XCTAssertNil(data["ressource"])
            }
        )
        assertRequest(
            transport.requests[2],
            function: "DernieresNotes",
            tab: 198,
            resource: resource,
            expectedData: { data in
                let periodData = data["Periode"] as? [String: Any]
                XCTAssertNil(periodData?["G"])
                XCTAssertEqual(periodData?["N"] as? String, "synthetic-period")
                XCTAssertEqual(periodData?["L"] as? String, "Période synthétique")
            }
        )
    }

    private func assertRequest(
        _ body: [String: Any],
        function: String,
        tab: Int,
        resource: [String: Any],
        expectedData: ([String: Any]) -> Void
    ) {
        XCTAssertEqual(body["id"] as? String, function)
        let data = body["dataSec"] as? [String: Any]
        let payloadData = data?["data"] as? [String: Any] ?? [:]
        expectedData(payloadData)

        let signature = data?["Signature"] as? [String: Any]
        XCTAssertEqual(signature?["onglet"] as? Int, tab)
        let member = signature?["membre"] as? [String: Any]
        XCTAssertEqual(member?["N"] as? String, resource["N"] as? String)
        XCTAssertEqual(member?["G"] as? Int, 4)
    }
}

private final class SessionRequestFakeTransport: PronoteHTTPTransporting {
    private(set) var requests: [[String: Any]] = []
    private(set) var downloadURL: URL?

    func bootstrap(
        serverURL: String,
        accountKind: PronoteAccountKind
    ) async throws -> PronoteSessionParameters {
        throw PronoteTransportError.invalidServerURL
    }

    func post(
        to url: URL,
        body: Data,
        additionalHeaders: [String: String]
    ) async throws -> Data {
        guard let request = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw PronoteSessionError.invalidResponse
        }
        requests.append(request)
        return try JSONSerialization.data(withJSONObject: ["dataSec": [:]])
    }

    func download(from url: URL) async throws -> Data {
        downloadURL = url
        return Data("synthetic-file-content".utf8)
    }
}
