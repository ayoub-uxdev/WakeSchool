import XCTest
@testable import WakeSchool

final class PronoteAuthenticationENTFallbackTests: XCTestCase {
    func testMobileTokenAuthenticationUsesTokenChallengeKeyAndEncryptedProof() async throws {
        let vector = try XCTUnwrap(
            PronoteCryptoFixtures.logins.first { $0.name == "standard" }
        )
        let temporaryIV = try PronoteCrypto.data(fromHex: vector.ivTempHex)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let mobileToken = vector.password
        let tokenKey = PronoteCrypto.aesKey(fromSeed: Data(mobileToken.utf8))
        let challengeCipher = try PronoteCrypto.aesCBCEncrypt(
            Data(vector.challenge.utf8),
            key: tokenKey,
            iv: sessionIV
        )
        let sessionKeyCipher = try PronoteCrypto.aesCBCEncrypt(
            try PronoteCrypto.data(fromByteList: vector.cle),
            key: tokenKey,
            iv: sessionIV
        )
        let transport = AuthenticationFakeTransport(responses: [
            try response(
                challenge: PronoteCrypto.hexString(from: challengeCipher)
            ),
            try response(cle: PronoteCrypto.hexString(from: sessionKeyCipher))
        ])
        let authenticator = PronoteAuthenticator(transport: transport)
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
            credentials: PronoteCredentials(
                serverURL: "https://example.test/pronote/",
                username: vector.username,
                password: vector.password,
                usesMobileToken: true,
                mobileUUID: "device-uuid"
            ),
            session: session,
            initial: initial,
            options: PronoteLoginOptions(
                mobileUUID: "device-uuid",
                clientIdentifier: "device-uuid",
                mobileToken: mobileToken
            )
        )

        let expectedSessionKey = try PronoteCrypto.deriveSessionKey(
            cleCipherHex: PronoteCrypto.hexString(from: sessionKeyCipher),
            authKey: tokenKey,
            iv: sessionIV
        )
        XCTAssertEqual(result.sessionKey, expectedSessionKey)

        let identification = try XCTUnwrap(identificationData(transport.requestBodies[0]))
        XCTAssertEqual(identification["enConnexionAppliMobile"] as? Bool, true)
        XCTAssertEqual(identification["demandeConnexionAppliMobileJeton"] as? Bool, false)
        XCTAssertEqual(identification["uuidAppliMobile"] as? String, "device-uuid")

        let proofHex = try XCTUnwrap(identification["loginTokenSAV"] as? String)
        XCTAssertNotEqual(proofHex, mobileToken)
        let proofPlain = try PronoteCrypto.aesCBCDecrypt(
            PronoteCrypto.data(fromHex: proofHex),
            key: tokenKey,
            iv: sessionIV
        )
        XCTAssertTrue((2...10).contains(proofPlain.count))
        XCTAssertEqual(proofPlain.reduce(0) { ($0 + Int($1)) % 255 }, 0)

        let authentication = try XCTUnwrap(authenticationData(transport.requestBodies[1]))
        XCTAssertEqual(authentication["enConnexionAppliMobile"] as? Bool, true)
        XCTAssertEqual(authentication["uuidAppliMobile"] as? String, "device-uuid")
        XCTAssertEqual(authentication["loginTokenSAV"] as? String, proofHex)
    }

    func testPasswordAuthenticationUsesUTF8UsernameAndTrimsPassword() async throws {
        let username = "élève"
        let password = " secret "
        let alea = "server-alea"
        let temporaryIV = try PronoteCrypto.data(
            fromHex: "a1b2c3d4e5f60718293a4b5c6d7e8f90"
        )
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let passwordHash = PronoteCrypto.hexString(
            from: PronoteCrypto.sha256(Data((alea + "secret").utf8)),
            uppercase: true
        )
        let key = PronoteCrypto.aesKey(
            fromSeed: Data((username + passwordHash).utf8)
        )
        let challenge = try PronoteCrypto.aesCBCEncrypt(
            Data("challenge-xyz".utf8),
            key: key,
            iv: sessionIV
        )
        let sessionKey = try PronoteCrypto.aesCBCEncrypt(
            try PronoteCrypto.data(fromByteList: "1,2,3,4"),
            key: key,
            iv: sessionIV
        )
        let transport = AuthenticationFakeTransport(responses: [
            try response(
                challenge: PronoteCrypto.hexString(from: challenge),
                alea: alea,
                modeCompLog: 0,
                modeCompMdp: 0
            ),
            try response(cle: PronoteCrypto.hexString(from: sessionKey))
        ])
        let authenticator = PronoteAuthenticator(transport: transport)
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
            credentials: PronoteCredentials(
                serverURL: "https://example.test/pronote/",
                username: username,
                password: password
            ),
            session: session,
            initial: initial
        )

        let expectedSessionKey = PronoteCrypto.aesKey(
            fromSeed: try PronoteCrypto.data(fromByteList: "1,2,3,4")
        )
        XCTAssertEqual(result.sessionKey, expectedSessionKey)
    }

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
        modeCompMdp: Int? = nil,
        cle: String? = nil
    ) throws -> Data {
        var data: [String: Any] = [:]
        if let challenge { data["challenge"] = challenge }
        if let alea { data["alea"] = alea }
        if let modeCompLog { data["modeCompLog"] = modeCompLog }
        if let modeCompMdp { data["modeCompMdp"] = modeCompMdp }
        if let cle { data["cle"] = cle }
        return try JSONSerialization.data(
            withJSONObject: ["dataSec": ["data": data]]
        )
    }

    private func identificationENTFlag(_ requestBody: Data) -> Bool? {
        identificationData(requestBody)?["pourENT"] as? Bool
    }

    private func identificationData(_ requestBody: Data) -> [String: Any]? {
        requestData(requestBody)
    }

    private func authenticationData(_ requestBody: Data) -> [String: Any]? {
        requestData(requestBody)
    }

    private func requestData(_ requestBody: Data) -> [String: Any]? {
        guard let body = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any],
              let dataSec = body["dataSec"] as? [String: Any],
              let data = dataSec["data"] as? [String: Any] else {
            return nil
        }
        return data
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
