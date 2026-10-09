import XCTest
@testable import WakeSchool

final class PronoteAuthenticationENTFallbackTests: XCTestCase {
    func testQRRetriesIdentificationUsingENTChallengeDerivation() async throws {
        let vector = try XCTUnwrap(
            PronoteCryptoFixtures.logins.first { $0.name == "ENT" }
        )
        let temporaryIV = try PronoteCrypto.data(fromHex: vector.ivTempHex)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let transport = AuthenticationFakeTransport(responses: [
            try response(challenge: "00000000000000000000000000000000"),
            try response(
                challenge: vector.challengeCipherHex,
                alea: vector.alea,
                modeCompLog: 1
            ),
            try response(cle: vector.cleCipherHex)
        ])
        let authenticator = PronoteAuthenticator(transport: transport)
        let credentials = PronoteCredentials(
            serverURL: "https://example.test/pronote/",
            username: "qr-user",
            password: vector.password,
            accountKind: .student,
            usesMobileToken: true
        )
        let session = PronoteSessionParameters(
            rootURL: URL(string: "https://example.test/pronote/")!,
            sessionID: "42",
            spaceID: 3,
            skipRequestEncryption: true,
            skipRequestCompression: true,
            version: [2026, 2, 7]
        )
        let initial = PronoteInitialSession(
            sessionID: "42",
            spaceID: 3,
            requestNumber: 3,
            temporaryIV: temporaryIV,
            sessionIV: sessionIV,
            requestsAreEncrypted: false,
            requestsAreCompressed: false
        )

        let result = try await authenticator.authenticate(
            credentials: credentials,
            session: session,
            initial: initial,
            options: PronoteLoginOptions(qrLogin: true)
        )

        XCTAssertEqual(transport.requestBodies.count, 3)
        XCTAssertEqual(identificationENTFlag(transport.requestBodies[0]), false)
        XCTAssertEqual(identificationENTFlag(transport.requestBodies[1]), true)
        XCTAssertEqual(
            PronoteCrypto.hexString(from: result.sessionKey),
            vector.finalKeyHex
        )
        XCTAssertEqual(result.requestNumber, initial.requestNumber + 6)
    }

    private func response(
        challenge: String? = nil,
        alea: String? = nil,
        modeCompLog: Int? = nil,
        cle: String? = nil
    ) throws -> Data {
        var data: [String: Any] = [:]
        if let challenge { data["challenge"] = challenge }
        if let alea { data["alea"] = alea }
        if let modeCompLog { data["modeCompLog"] = modeCompLog }
        if let cle { data["cle"] = cle }
        return try JSONSerialization.data(
            withJSONObject: ["dataSec": ["data": data]]
        )
    }

    private func identificationENTFlag(_ requestBody: Data) -> Bool? {
        guard let body = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any],
              let dataSec = body["dataSec"] as? [String: Any],
              let data = dataSec["data"] as? [String: Any] else {
            return nil
        }
        return data["pourENT"] as? Bool
    }
}

private final class AuthenticationFakeTransport: PronoteHTTPTransporting {
    private let responses: [Data]
    private(set) var requestBodies: [Data] = []

    init(responses: [Data]) {
        self.responses = responses
    }

    func bootstrap(
        serverURL: String,
        accountKind: PronoteAccountKind
    ) async throws -> PronoteSessionParameters {
        throw PronoteAuthenticationError.unsupportedLogin
    }

    func post(
        to url: URL,
        body: Data,
        additionalHeaders: [String: String]
    ) async throws -> Data {
        requestBodies.append(body)
        guard requestBodies.count <= responses.count else {
            throw PronoteAuthenticationError.invalidResponse
        }
        return responses[requestBodies.count - 1]
    }
}
