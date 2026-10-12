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
            Data("1,2,3,4".utf8),
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
        } catch let error as PronoteLoginDiagnosticError {
            XCTAssertEqual(error.stage, .identification)
            XCTAssertEqual(
                error.message,
                PronoteAuthenticationError.challengeFormatInvalid.localizedDescription
            )
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
        } catch let error as PronoteLoginDiagnosticError {
            XCTAssertEqual(error.stage, .identification)
            XCTAssertEqual(
                error.message,
                PronoteAuthenticationError.missingField("challenge").localizedDescription
            )
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
        } catch let error as PronoteLoginDiagnosticError {
            XCTAssertEqual(error.stage, .authentication)
            XCTAssertTrue(error.message.contains("code 1"))
        }
        XCTAssertEqual(transport.requestBodies.count, 2)
    }

    func testAutomaticReconnectionReportsAuthenticationStageAndCode() async throws {
        let temporaryIV = Data(repeating: 0x33, count: 16)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let token = "stored-mobile-token"
        let transport = AuthenticationFakeTransport(responses: [
            try response(challenge: "valid-challenge"),
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
                    username: "student",
                    password: token,
                    usesMobileToken: true,
                    mobileUUID: "stable-device-id"
                ),
                session: session,
                initial: initial,
                options: PronoteLoginOptions(
                    mobileUUID: "stable-device-id",
                    clientIdentifier: "stable-device-id",
                    mobileToken: token,
                    automaticReconnection: true
                )
            )
            XCTFail("Expected the automatic token reconnection to be rejected")
        } catch let error as PronoteLoginDiagnosticError {
            XCTAssertEqual(error.stage, .automaticReconnection)
            XCTAssertEqual(error.operation, .authentication)
            XCTAssertTrue(error.localizedDescription.contains("code 1"))
            XCTAssertTrue(error.localizedDescription.contains("jetonPrésent=true"))
            XCTAssertTrue(error.localizedDescription.contains("UUIDPrésent=true"))
            XCTAssertTrue(error.localizedDescription.contains("reconnexionAutomatique=true"))
            XCTAssertFalse(error.localizedDescription.contains(token))
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
            Data("1,2,3,4".utf8),
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

    func testStoredMobileTokenReconnectionUsesStandardPasswordDerivation() async throws {
        let mobileToken = "mobile-token"
        let username = "student"
        let alea = "token-login-alea"
        let temporaryIV = Data((0...15).map { UInt8($0) })
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let tokenKey = PronoteCrypto.deriveLoginKeys(
            username: username,
            password: mobileToken,
            alea: alea,
            ivTemp: temporaryIV,
            isENT: false
        ).authKey
        let challenge = "mobile challenge"
        let cleCipher = try PronoteCrypto.aesCBCEncrypt(
            Data("9,8,7,6".utf8),
            key: tokenKey,
            iv: sessionIV
        )
        let transport = AuthenticationFakeTransport(responses: [
            try response(challenge: challenge, alea: alea),
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
                mobileToken: mobileToken,
                automaticReconnection: true
            )
        )

        let identification = try XCTUnwrap(
            requestData(transport.requestBodies[0])
        )
        let authentication = try XCTUnwrap(
            requestData(transport.requestBodies[1])
        )
        let expectedChallenge = try PronoteCrypto.aesCBCEncrypt(
            Data(challenge.utf8),
            key: tokenKey,
            iv: sessionIV
        )
        XCTAssertEqual(identification["enConnexionAppliMobile"] as? Bool, true)
        XCTAssertEqual(identification["demandeConnexionAppliMobile"] as? Bool, false)
        XCTAssertEqual(identification["demandeConnexionAppliMobileJeton"] as? Bool, false)
        XCTAssertEqual(identification["uuidAppliMobile"] as? String, "stable-device-id")
        XCTAssertEqual(identification["loginTokenSAV"] as? String, "")
        XCTAssertEqual(identification["enConnexionAuto"] as? Bool, false)
        XCTAssertEqual(identification["demandeConnexionAuto"] as? Bool, false)
        XCTAssertNil(authentication["loginTokenSAV"])
        XCTAssertNil(authentication["enConnexionAppliMobile"])
        XCTAssertEqual(
            authentication["challenge"] as? String,
            PronoteCrypto.hexString(from: expectedChallenge)
        )
        XCTAssertEqual(identification["identifiant"] as? String, username)
        XCTAssertEqual(identification["pourENT"] as? Bool, false)
        XCTAssertEqual(result.requestNumber, initial.requestNumber + 4)
        XCTAssertEqual(transport.requestBodies.count, 2)
    }

    func testAutomaticTokenOptionsPreserveCredentialUUIDAndTokenMode() {
        let credentials = PronoteCredentials(
            serverURL: "https://example.test/pronote/",
            username: "student",
            password: "synthetic-mobile-token",
            usesMobileToken: true,
            mobileUUID: "stable-device-id"
        )

        let options = PronoteLoginOptions.automaticReconnection(for: credentials)

        XCTAssertFalse(options.useENT)
        XCTAssertEqual(options.mobileUUID, "stable-device-id")
        XCTAssertEqual(options.clientIdentifier, "stable-device-id")
        XCTAssertEqual(options.mobileToken, "synthetic-mobile-token")
        XCTAssertFalse(options.requestFirstMobileAuthentication)
        XCTAssertFalse(options.qrLogin)
        XCTAssertTrue(options.automaticReconnection)
    }

    func testEmptyStoredTokenFailsWithNonSensitiveDiagnostic() async throws {
        let temporaryIV = Data(repeating: 0x55, count: 16)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let transport = AuthenticationFakeTransport(responses: [])
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
                    password: "",
                    usesMobileToken: true,
                    mobileUUID: "stable-device-id"
                ),
                session: session,
                initial: initial,
                options: PronoteLoginOptions(
                    mobileUUID: "stable-device-id",
                    clientIdentifier: "stable-device-id",
                    mobileToken: "",
                    automaticReconnection: true
                )
            )
            XCTFail("An empty stored mobile token must not fall back to password mode")
        } catch let error as PronoteLoginDiagnosticError {
            XCTAssertEqual(error.stage, .automaticReconnection)
            XCTAssertEqual(error.operation, .identification)
            XCTAssertTrue(error.localizedDescription.contains("jetonPrésent=false"))
            XCTAssertTrue(error.localizedDescription.contains("UUIDPrésent=true"))
        }
        XCTAssertTrue(transport.requestBodies.isEmpty)
    }

    func testENTMobileTokenLoginAuthenticatesBeforeReturningCredentials() async throws {
        let transport = ENTMobileTokenFakeTransport()
        let result = try await LivePronoteClient.loginWithENTMobileToken(
            serverURL: "https://example.test/pronote/",
            username: "ent-student",
            mobileToken: "ent-mobile-token",
            accountKind: .student,
            mobileUUID: "stable-device-id",
            transport: transport
        )

        let identification = try XCTUnwrap(
            requestData(transport.requestBodies[1])
        )
        let authentication = try XCTUnwrap(
            requestData(transport.requestBodies[2])
        )

        XCTAssertEqual(result.credentials.usesMobileToken, true)
        XCTAssertEqual(result.credentials.password, "refreshed-mobile-token")
        XCTAssertEqual(identification["identifiant"] as? String, "ent-student")
        XCTAssertEqual(identification["pourENT"] as? Bool, false)
        XCTAssertEqual(identification["enConnexionAppliMobile"] as? Bool, true)
        XCTAssertEqual(identification["demandeConnexionAppliMobile"] as? Bool, false)
        XCTAssertEqual(identification["uuidAppliMobile"] as? String, "stable-device-id")
        XCTAssertEqual(identification["loginTokenSAV"] as? String, "")
        XCTAssertNil(authentication["enConnexionAppliMobile"])
        XCTAssertNil(authentication["uuidAppliMobile"])
        XCTAssertEqual(
            authentication["challenge"] as? String,
            transport.expectedChallenge
        )
        XCTAssertEqual(transport.requestBodies.count, 4)
    }

    func testENTMobileTokenAuthenticationRejectionReturnsNoCredentials() async throws {
        let transport = ENTMobileTokenFakeTransport(authenticationAccessCode: 1)

        do {
            _ = try await LivePronoteClient.loginWithENTMobileToken(
                serverURL: "https://example.test/pronote/",
                username: "ent-student",
                mobileToken: "ent-mobile-token",
                accountKind: .student,
                mobileUUID: "stable-device-id",
                transport: transport
            )
            XCTFail("A rejected mobile token must not yield credentials to persist")
        } catch let error as PronoteLoginDiagnosticError {
            XCTAssertEqual(error.stage, .mobileTokenRecovery)
            XCTAssertEqual(error.operation, .authentication)
            XCTAssertTrue(error.message.contains("code 1"))
        }
        XCTAssertEqual(transport.requestBodies.count, 3)
    }

    func testENTLoginDoesNotReturnTemporaryTokenWhenServerOmitsRefreshedToken() async throws {
        let transport = ENTMobileTokenFakeTransport(
            returnedMobileToken: nil,
            tokenUsedForLogin: "temporary-ent-token"
        )

        do {
            _ = try await LivePronoteClient.loginWithENTMobileToken(
                serverURL: "https://example.test/pronote/",
                username: "ent-student",
                mobileToken: "temporary-ent-token",
                accountKind: .student,
                mobileUUID: "stable-device-id",
                transport: transport
            )
            XCTFail("The temporary ENT token must not be persisted as a reconnect token")
        } catch let error as PronoteLoginDiagnosticError {
            XCTAssertEqual(error.stage, .mobileTokenRecovery)
            XCTAssertTrue(error.localizedDescription.contains("n'a pas fourni de jeton mobile"))
            XCTAssertFalse(error.localizedDescription.contains("temporary-ent-token"))
        }
    }

    func testAutomaticReconnectionPersistsOnlyANonemptyRotatedToken() async throws {
        let store = InMemorySecretStore()
        let credentialStore = CredentialsStore(store: store)
        let credentials = PronoteCredentials(
            serverURL: "https://example.test/pronote/",
            username: "ent-student",
            password: "ent-mobile-token",
            usesMobileToken: true,
            mobileUUID: "stable-device-id"
        )
        try credentialStore.save(credentials)
        let transport = ENTMobileTokenFakeTransport()
        let client = LivePronoteClient(
            credentials: credentials,
            options: .automaticReconnection(for: credentials),
            transport: transport,
            onCredentialsUpdated: { updated in
                try credentialStore.save(updated)
            }
        )

        _ = try await client.profile()

        let savedCredentials = try XCTUnwrap(credentialStore.load())
        XCTAssertEqual(savedCredentials.password, "refreshed-mobile-token")
        XCTAssertTrue(savedCredentials.usesMobileToken)
        XCTAssertEqual(savedCredentials.mobileUUID, "stable-device-id")

        let identification = try XCTUnwrap(
            requestData(transport.requestBodies[1])
        )
        XCTAssertEqual(identification["enConnexionAppliMobile"] as? Bool, true)
        XCTAssertEqual(identification["demandeConnexionAppliMobile"] as? Bool, false)
        XCTAssertEqual(identification["uuidAppliMobile"] as? String, "stable-device-id")
        XCTAssertEqual(identification["enConnexionAuto"] as? Bool, false)
        XCTAssertEqual(identification["demandeConnexionAuto"] as? Bool, false)
        XCTAssertEqual(identification["loginTokenSAV"] as? String, "")
    }

    func testAutomaticReconnectionKeepsStoredTokenWhenRefreshIsMissingOrEmpty() async throws {
        let returnedTokens: [String?] = [nil, ""]
        for returnedToken in returnedTokens {
            let store = InMemorySecretStore()
            let credentialStore = CredentialsStore(store: store)
            let credentials = PronoteCredentials(
                serverURL: "https://example.test/pronote/",
                username: "ent-student",
                password: "ent-mobile-token",
                usesMobileToken: true,
                mobileUUID: "stable-device-id"
            )
            try credentialStore.save(credentials)
            let client = LivePronoteClient(
                credentials: credentials,
                options: .automaticReconnection(for: credentials),
                transport: ENTMobileTokenFakeTransport(
                    returnedMobileToken: returnedToken
                ),
                onCredentialsUpdated: { updated in
                    try credentialStore.save(updated)
                }
            )

            _ = try await client.profile()

            let savedCredentials = try XCTUnwrap(credentialStore.load())
            XCTAssertEqual(savedCredentials.password, "ent-mobile-token")
            XCTAssertTrue(savedCredentials.usesMobileToken)
            XCTAssertEqual(savedCredentials.mobileUUID, "stable-device-id")
        }
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
            Data(vector.cle.utf8),
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

private final class ENTMobileTokenFakeTransport: PronoteHTTPTransporting {
    private let authenticationAccessCode: Int
    private let returnedMobileToken: String?
    private let tokenUsedForLogin: String
    private var temporaryIV: Data?
    private(set) var requestBodies: [Data] = []
    private(set) var expectedChallenge = ""

    init(
        authenticationAccessCode: Int = 0,
        returnedMobileToken: String? = "refreshed-mobile-token",
        tokenUsedForLogin: String = "ent-mobile-token"
    ) {
        self.authenticationAccessCode = authenticationAccessCode
        self.returnedMobileToken = returnedMobileToken
        self.tokenUsedForLogin = tokenUsedForLogin
    }

    func bootstrap(
        serverURL: String,
        accountKind: PronoteAccountKind
    ) async throws -> PronoteSessionParameters {
        PronoteSessionParameters(
            rootURL: URL(string: "https://example.test/pronote/")!,
            sessionID: "42",
            spaceID: 3,
            skipRequestEncryption: true,
            skipRequestCompression: true,
            version: [2026, 2, 7]
        )
    }

    func post(
        to url: URL,
        body: Data,
        additionalHeaders: [String: String]
    ) async throws -> Data {
        requestBodies.append(body)
        guard let request = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let function = request["id"] as? String else {
            throw PronoteAuthenticationError.invalidResponse
        }

        switch function {
        case "FonctionParametres":
            guard let requestData = Self.dataDictionary(in: request),
                  let uuid = requestData["Uuid"] as? String,
                  let bytes = Data(base64Encoded: uuid) else {
                throw PronoteAuthenticationError.invalidResponse
            }
            temporaryIV = bytes
            let encryptedOrder = try PronoteCrypto.aesCBCEncrypt(
                Data("2".utf8),
                key: PronoteCrypto.md5(Data()),
                iv: PronoteCrypto.md5(bytes)
            )
            return try Self.json([
                "no": PronoteCrypto.hexString(from: encryptedOrder),
                "dataSec": [:]
            ])

        case "Identification":
            guard temporaryIV != nil else {
                throw PronoteAuthenticationError.invalidResponse
            }
            return try Self.json([
                "dataSec": [
                    "data": [
                        "challenge": "ent-mobile-challenge",
                        "alea": "test-alea",
                        "modeCompLog": 0,
                        "modeCompMdp": 0
                    ]
                ]
            ])

        case "Authentification":
            guard let temporaryIV else {
                throw PronoteAuthenticationError.invalidResponse
            }
            let sessionIV = PronoteCrypto.md5(temporaryIV)
            let tokenKey = PronoteCrypto.deriveLoginKeys(
                username: "ent-student",
                password: tokenUsedForLogin,
                alea: "test-alea",
                ivTemp: temporaryIV,
                isENT: false
            ).authKey
            let encryptedChallenge = try PronoteCrypto.aesCBCEncrypt(
                Data("ent-mobile-challenge".utf8),
                key: tokenKey,
                iv: sessionIV
            )
            expectedChallenge = PronoteCrypto.hexString(from: encryptedChallenge)
            var data: [String: Any] = ["Acces": authenticationAccessCode]
            if authenticationAccessCode == 0 {
                data["cle"] = PronoteCrypto.hexString(
                    from: try PronoteCrypto.aesCBCEncrypt(
                        Data("1,2,3,4".utf8),
                        key: tokenKey,
                        iv: sessionIV
                    )
                )
                if let returnedMobileToken {
                    data["jetonConnexionAppliMobile"] = returnedMobileToken
                }
            }
            return try Self.json(["dataSec": ["data": data]])

        case "ParametresUtilisateur":
            return try Self.json([
                "dataSec": [
                    "data": [
                        "ressource": ["libelleUtil": "Test user"],
                        "listePeriodes": []
                    ]
                ]
            ])

        default:
            throw PronoteAuthenticationError.invalidResponse
        }
    }

    private static func dataDictionary(in request: [String: Any]) -> [String: Any]? {
        guard let dataSec = request["dataSec"] as? [String: Any] else { return nil }
        return dataSec["data"] as? [String: Any]
            ?? dataSec["donnees"] as? [String: Any]
    }

    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
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
