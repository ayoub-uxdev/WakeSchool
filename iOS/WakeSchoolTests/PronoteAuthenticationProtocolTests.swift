import XCTest
@testable import WakeSchool

final class PronoteAuthenticationProtocolTests: XCTestCase {
    func testCurrentAndHistoricalVersionChallengesAreEncryptedAsUTF8() async throws {
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
        let authKey = PronoteCrypto.aesKey(
            fromSeed: Data((username + passwordHash).utf8)
        )
        let sessionKeyCipher = try PronoteCrypto.aesCBCEncrypt(
            try PronoteCrypto.data(fromByteList: "1,2,3,4"),
            key: authKey,
            iv: sessionIV
        )
        let expectedSessionKey = PronoteCrypto.aesKey(
            fromSeed: try PronoteCrypto.data(fromByteList: "1,2,3,4")
        )
        let cases: [([Int], String)] = [
            ([2026, 2, 7], "00112233445566778899AABBCCDDEEFF"),
            ([2024, 2, 5], "Zq3Rk1Lm0pX8aB")
        ]

        for (version, challenge) in cases {
            let transport = AuthenticationFakeTransport(responses: [
                try response(
                    challenge: challenge,
                    alea: alea,
                    modeCompLog: 0,
                    modeCompMdp: 0
                ),
                try response(cle: PronoteCrypto.hexString(from: sessionKeyCipher))
            ])
            let (session, initial) = makeSession(
                version: version,
                temporaryIV: temporaryIV,
                sessionIV: sessionIV
            )

            let result = try await PronoteAuthenticator(transport: transport).authenticate(
                credentials: PronoteCredentials(
                    serverURL: "https://example.test/pronote/",
                    username: username,
                    password: password
                ),
                session: session,
                initial: initial
            )

            let expectedChallenge = try PronoteCrypto.aesCBCEncrypt(
                Data(challenge.utf8),
                key: authKey,
                iv: sessionIV
            )
            let authentication = try XCTUnwrap(
                requestData(transport.requestBodies[1])
            )
            XCTAssertEqual(result.sessionKey, expectedSessionKey)
            XCTAssertEqual(
                authentication["challenge"] as? String,
                PronoteCrypto.hexString(from: expectedChallenge)
            )
            XCTAssertEqual(transport.requestBodies.count, 2)
        }
    }

    func testEmptyChallengeFailsBeforeSendingAuthentication() async throws {
        let temporaryIV = Data(repeating: 0x12, count: 16)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let transport = AuthenticationFakeTransport(responses: [
            try response(challenge: "")
        ])
        let (session, initial) = makeSession(
            version: [2026, 2, 7],
            temporaryIV: temporaryIV,
            sessionIV: sessionIV
        )

        do {
            _ = try await PronoteAuthenticator(transport: transport).authenticate(
                credentials: PronoteCredentials(
                    serverURL: "https://example.test/pronote/",
                    username: "student",
                    password: "password"
                ),
                session: session,
                initial: initial
            )
            XCTFail("Expected an empty challenge to be rejected")
        } catch let error as PronoteAuthenticationError {
            XCTAssertEqual(error, .challengeFormatInvalid)
        }
        XCTAssertEqual(transport.requestBodies.count, 1)
    }

    func testMissingChallengeFailsBeforeSendingAuthentication() async throws {
        let temporaryIV = Data(repeating: 0x13, count: 16)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let transport = AuthenticationFakeTransport(responses: [
            try response()
        ])
        let (session, initial) = makeSession(
            version: [2026, 2, 7],
            temporaryIV: temporaryIV,
            sessionIV: sessionIV
        )

        do {
            _ = try await PronoteAuthenticator(transport: transport).authenticate(
                credentials: PronoteCredentials(
                    serverURL: "https://example.test/pronote/",
                    username: "student",
                    password: "password"
                ),
                session: session,
                initial: initial
            )
            XCTFail("Expected a missing challenge to be rejected")
        } catch let error as PronoteAuthenticationError {
            XCTAssertEqual(error, .missingField("challenge"))
        }
        XCTAssertEqual(transport.requestBodies.count, 1)
    }

    func testPronoteAuthenticationRejectionIsNotReportedAsMissingSessionKey() async throws {
        let temporaryIV = Data(repeating: 0x32, count: 16)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let challenge = "valid-plain-challenge"
        let password = "correct-format-password"
        let username = "student"
        let transport = AuthenticationFakeTransport(responses: [
            try response(challenge: challenge),
            try response(accessCode: 1)
        ])
        let (session, initial) = makeSession(
            version: [2026, 2, 7],
            temporaryIV: temporaryIV,
            sessionIV: sessionIV
        )

        do {
            _ = try await PronoteAuthenticator(transport: transport).authenticate(
                credentials: PronoteCredentials(
                    serverURL: "https://example.test/pronote/",
                    username: username,
                    password: password
                ),
                session: session,
                initial: initial
            )
            XCTFail("Expected PRONOTE's authentication rejection")
        } catch let error as PronoteAuthenticationError {
            XCTAssertEqual(error, .authenticationRejected(1))
        }
        XCTAssertEqual(transport.requestBodies.count, 2)
    }

    func testENTLoginUsesENTKeyDerivationAndPreservesPasswordCase() async throws {
        let username = "ent-student"
        let password = "ENT-Password"
        let alea = "ent-alea"
        let challenge = "ent-plain-challenge"
        let temporaryIV = Data(repeating: 0x41, count: 16)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let keys = PronoteCrypto.deriveLoginKeys(
            username: username,
            password: password,
            alea: alea,
            ivTemp: temporaryIV,
            isENT: true
        )
        let expectedChallenge = try PronoteCrypto.aesCBCEncrypt(
            Data(challenge.utf8),
            key: keys.authKey,
            iv: sessionIV
        )
        let cleCipher = try PronoteCrypto.aesCBCEncrypt(
            try PronoteCrypto.data(fromByteList: "1,2,3,4"),
            key: keys.authKey,
            iv: sessionIV
        )
        let transport = AuthenticationFakeTransport(responses: [
            try response(
                challenge: challenge,
                alea: alea,
                modeCompLog: 1,
                modeCompMdp: 1
            ),
            try response(cle: PronoteCrypto.hexString(from: cleCipher))
        ])
        let (session, initial) = makeSession(
            version: [2026, 2, 7],
            temporaryIV: temporaryIV,
            sessionIV: sessionIV
        )

        _ = try await PronoteAuthenticator(transport: transport).authenticate(
            credentials: PronoteCredentials(
                serverURL: "https://example.test/pronote/",
                username: username,
                password: password
            ),
            session: session,
            initial: initial,
            options: PronoteLoginOptions(useENT: true)
        )

        let identification = try XCTUnwrap(
            requestData(transport.requestBodies[0])
        )
        let authentication = try XCTUnwrap(
            requestData(transport.requestBodies[1])
        )
        XCTAssertEqual(identification["pourENT"] as? Bool, true)
        XCTAssertEqual(
            authentication["challenge"] as? String,
            PronoteCrypto.hexString(from: expectedChallenge)
        )
    }

    func testStoredMobileTokenReconnectionUsesTokenKeyAndProof() async throws {
        let mobileToken = "a-previously-issued-mobile-token"
        let username = "student"
        let temporaryIV = Data(repeating: 0x21, count: 16)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let tokenKey = PronoteCrypto.aesKey(fromSeed: Data(mobileToken.utf8))
        let challenge = "plain-mobile-challenge"
        let challengeCipher = try PronoteCrypto.aesCBCEncrypt(
            Data(challenge.utf8),
            key: tokenKey,
            iv: sessionIV
        )
        let cleCipher = try PronoteCrypto.aesCBCEncrypt(
            try PronoteCrypto.data(fromByteList: "9,8,7,6"),
            key: tokenKey,
            iv: sessionIV
        )
        let transport = AuthenticationFakeTransport(responses: [
            try response(challenge: challenge),
            try response(cle: PronoteCrypto.hexString(from: cleCipher))
        ])
        let (session, initial) = makeSession(
            version: [2026, 2, 7],
            temporaryIV: temporaryIV,
            sessionIV: sessionIV
        )

        let result = try await PronoteAuthenticator(transport: transport).authenticate(
            credentials: PronoteCredentials(
                serverURL: "https://example.test/pronote/",
                username: username,
                password: mobileToken,
                usesMobileToken: true,
                mobileUUID: "stable-device-id"
            ),
            session: session,
            initial: initial,
            options: PronoteLoginOptions(
                mobileUUID: "stable-device-id",
                clientIdentifier: "stable-device-id",
                mobileToken: mobileToken
            )
        )

        let identification = try XCTUnwrap(
            requestData(transport.requestBodies[0])
        )
        let authentication = try XCTUnwrap(
            requestData(transport.requestBodies[1])
        )
        let proofHex = try XCTUnwrap(identification["loginTokenSAV"] as? String)
        let proofPlain = try PronoteCrypto.aesCBCDecrypt(
            PronoteCrypto.data(fromHex: proofHex),
            key: tokenKey,
            iv: sessionIV
        )

        XCTAssertEqual(identification["enConnexionAppliMobile"] as? Bool, true)
        XCTAssertEqual(identification["demandeConnexionAppliMobileJeton"] as? Bool, false)
        XCTAssertEqual(identification["uuidAppliMobile"] as? String, "stable-device-id")
        XCTAssertNotEqual(proofHex, mobileToken)
        XCTAssertTrue((2...10).contains(proofPlain.count))
        XCTAssertEqual(proofPlain.reduce(0) { ($0 + Int($1)) % 255 }, 0)
        XCTAssertEqual(authentication["loginTokenSAV"] as? String, proofHex)
        XCTAssertEqual(authentication["enConnexionAppliMobile"] as? Bool, true)
        XCTAssertEqual(
            authentication["challenge"] as? String,
            PronoteCrypto.hexString(from: challengeCipher)
        )
        XCTAssertEqual(result.requestNumber, initial.requestNumber + 4)
        XCTAssertEqual(transport.requestBodies.count, 2)
    }

    func testQRCodeInitialLoginDoesNotUseStoredTokenReconnectionFlags() async throws {
        let vector = try XCTUnwrap(
            PronoteCryptoFixtures.logins.first { $0.name == "standard" }
        )
        let temporaryIV = try PronoteCrypto.data(fromHex: vector.ivTempHex)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let keys = PronoteCrypto.deriveLoginKeys(
            username: vector.username,
            password: vector.password,
            alea: vector.alea,
            ivTemp: temporaryIV,
            isENT: false
        )
        let expectedChallenge = try PronoteCrypto.aesCBCEncrypt(
            Data(vector.challenge.utf8),
            key: keys.authKey,
            iv: sessionIV
        )
        let cleCipher = try PronoteCrypto.aesCBCEncrypt(
            try PronoteCrypto.data(fromByteList: vector.cle),
            key: keys.authKey,
            iv: sessionIV
        )
        let transport = AuthenticationFakeTransport(responses: [
            try response(challenge: vector.challenge, alea: vector.alea),
            try response(cle: PronoteCrypto.hexString(from: cleCipher))
        ])
        let (session, initial) = makeSession(
            version: [2026, 2, 7],
            temporaryIV: temporaryIV,
            sessionIV: sessionIV
        )

        _ = try await PronoteAuthenticator(transport: transport).authenticate(
            credentials: PronoteCredentials(
                serverURL: "https://example.test/pronote/",
                username: vector.username,
                password: vector.password,
                usesMobileToken: true,
                mobileUUID: "stable-device-id"
            ),
            session: session,
            initial: initial,
            options: PronoteLoginOptions(
                mobileUUID: "stable-device-id",
                clientIdentifier: "stable-device-id",
                requestFirstMobileAuthentication: true,
                qrLogin: true
            )
        )

        let identification = try XCTUnwrap(
            requestData(transport.requestBodies[0])
        )
        let authentication = try XCTUnwrap(
            requestData(transport.requestBodies[1])
        )
        XCTAssertEqual(identification["demandeConnexionAppliMobile"] as? Bool, true)
        XCTAssertEqual(identification["demandeConnexionAppliMobileJeton"] as? Bool, true)
        XCTAssertEqual(identification["enConnexionAppliMobile"] as? Bool, false)
        XCTAssertEqual(
            authentication["challenge"] as? String,
            PronoteCrypto.hexString(from: expectedChallenge)
        )
        XCTAssertEqual(transport.requestBodies.count, 2)
    }

    private func makeSession(
        version: [Int],
        temporaryIV: Data,
        sessionIV: Data
    ) -> (PronoteSessionParameters, PronoteInitialSession) {
        let session = PronoteSessionParameters(
            rootURL: URL(string: "https://example.test/pronote/")!,
            sessionID: "42",
            spaceID: 3,
            skipRequestEncryption: true,
            skipRequestCompression: true,
            version: version
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
        return (session, initial)
    }

    private func response(
        challenge: String? = nil,
        alea: String? = nil,
        modeCompLog: Int? = nil,
        modeCompMdp: Int? = nil,
        cle: String? = nil,
        accessCode: Int? = nil
    ) throws -> Data {
        var data: [String: Any] = [:]
        if let challenge { data["challenge"] = challenge }
        if let alea { data["alea"] = alea }
        if let modeCompLog { data["modeCompLog"] = modeCompLog }
        if let modeCompMdp { data["modeCompMdp"] = modeCompMdp }
        if let cle { data["cle"] = cle }
        if let accessCode { data["Acces"] = accessCode }
        return try JSONSerialization.data(
            withJSONObject: ["dataSec": ["data": data]]
        )
    }

    private func requestData(_ requestBody: Data) -> [String: Any]? {
        guard let body = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any],
              let dataSec = body["dataSec"] as? [String: Any]
                ?? body["donneesSec"] as? [String: Any],
              let data = dataSec["data"] as? [String: Any]
                ?? dataSec["donnees"] as? [String: Any] else {
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
