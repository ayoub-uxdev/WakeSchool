import Foundation

enum PronoteAuthenticationError: Error, Equatable, LocalizedError {
    case invalidCredentials
    case invalidResponse
    case missingChallenge
    case invalidChallenge
    case invalidChallengeResult
    case missingAuthenticationKey
    case invalidAuthenticationKey
    case invalidResponseOrder
    case unsupportedDataSec

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Les identifiants PRONOTE sont invalides."
        case .invalidResponse:
            return "La réponse PRONOTE est invalide."
        case .missingChallenge:
            return "PRONOTE n'a pas fourni de challenge."
        case .invalidChallenge:
            return "Le challenge PRONOTE est invalide."
        case .invalidChallengeResult:
            return "Impossible de résoudre le challenge PRONOTE."
        case .missingAuthenticationKey:
            return "PRONOTE n'a pas fourni de clé d'authentification."
        case .invalidAuthenticationKey:
            return "La clé d'authentification PRONOTE est invalide."
        case .invalidResponseOrder:
            return "Le numéro d'ordre de la réponse PRONOTE est invalide."
        case .unsupportedDataSec:
            return "Le format dataSec PRONOTE n'est pas pris en charge."
        }
    }
}

struct PronoteAuthenticationResult {
    let serverURL: String
    let sessionID: String
    let spaceID: Int
    let requestNumber: Int
    let userName: String?
    let mobileToken: String?
    let authenticationKey: Data
    let sessionIV: Data
}

struct PronoteAuthenticationClient {
    private let transport: PronoteHTTPTransporting

    init(transport: PronoteHTTPTransporting) {
        self.transport = transport
    }

    func authenticate(
        session: PronoteInitialSession,
        username: String,
        password: String,
        spaceID: Int
    ) async throws -> PronoteAuthenticationResult {

        guard !username.isEmpty, !password.isEmpty else {
            throw PronoteAuthenticationError.invalidCredentials
        }

        let defaultKey = PronoteCrypto.aesKey(fromSeed: nil)

        // PRONOTE utilise le même IV communiqué lors de
        // FonctionParametres pour la suite de l'authentification.
        let sessionIV = session.sessionIV

        // ---------------------------------------------------------
        // 1. IDENTIFICATION
        // ---------------------------------------------------------

        let identificationData: [String: Any] = [
            "genreConnexion": 0,
            "genreEspace": spaceID,
            "identifiant": username,
            "pourENT": false,
            "enConnexionAuto": false,
            "demandeConnexionAuto": false,
            "demandeConnexionAppliMobile": false,
            "demandeConnexionAppliMobileJeton": false,
            "enConnexionAppliMobile": false,
            "uuidAppliMobile": "",
            "loginTokenSAV": ""
        ]

        let identificationWrapper: [String: Any] = [
            "data": identificationData
        ]

        let identificationRequestNumber = try encryptedOrder(
            3,
            key: defaultKey,
            iv: sessionIV
        )

        let identificationDataSec = try PronoteCodec.encodeRequestDataSec(
            identificationWrapper,
            compressed: true,
            encrypted: true,
            key: defaultKey,
            iv: sessionIV
        )

        let identificationBody: [String: Any] = [
            "session": Int(session.sessionID) ?? 0,
            "no": identificationRequestNumber,
            "id": "Identification",
            "dataSec": identificationDataSec
        ]

        let identificationResponse = try await send(
            body: identificationBody,
            serverURL: sessionServerURL(from: session),
            spaceID: session.spaceID,
            sessionID: session.sessionID,
            requestNumber: identificationRequestNumber
        )

        let identificationDecoded = try decodeResponse(
            identificationResponse,
            compressed: true,
            encrypted: true,
            key: defaultKey,
            iv: sessionIV
        )

        guard let identification = identificationDecoded as? [String: Any] else {
            throw PronoteAuthenticationError.invalidResponse
        }

        guard let challenge = stringValue(
            named: "challenge",
            in: identification
        ) else {
            throw PronoteAuthenticationError.missingChallenge
        }

        let randomString = stringValue(
            named: "alea",
            in: identification
        ) ?? ""

        let modeCompMdp = intValue(
            named: "modeCompMdp",
            in: identification
        ) ?? 0

        let modeCompLog = intValue(
            named: "modeCompLog",
            in: identification
        ) ?? 0

        let effectiveUsername = modeCompLog == 1
            ? username.lowercased()
            : username

        let effectivePassword = modeCompMdp == 1
            ? password.lowercased()
            : password

        // ---------------------------------------------------------
        // 2. CALCUL DU MTP
        // ---------------------------------------------------------

        let shaInput = Data(
            (randomString + effectivePassword).utf8
        )

        let sha256 = PronoteCrypto.sha256(shaInput)

        let mtp = PronoteCrypto.hexString(
            from: sha256,
            uppercase: true
        )

        // clé = MD5(username + mtp)
        let challengeKey = PronoteCrypto.md5(
            Data((effectiveUsername + mtp).utf8)
        )

        // ---------------------------------------------------------
        // 3. DÉCHIFFREMENT DU CHALLENGE
        // ---------------------------------------------------------

        guard let challengeData = try? PronoteCrypto.data(
            fromHex: challenge
        ) else {
            throw PronoteAuthenticationError.invalidChallenge
        }

        let decryptedChallenge: Data

        do {
            decryptedChallenge = try PronoteCrypto.aesCBCDecrypt(
                challengeData,
                key: challengeKey,
                iv: sessionIV
            )
        } catch {
            throw PronoteAuthenticationError.invalidChallenge
        }

        guard let challengeText = String(
            data: decryptedChallenge,
            encoding: .utf8
        ) else {
            throw PronoteAuthenticationError.invalidChallenge
        }

        // PRONOTE conserve un caractère sur deux.
        let solvedText = String(
            challengeText.enumerated()
                .compactMap { index, character in
                    index.isMultiple(of: 2) ? character : nil
                }
        )

        guard !solvedText.isEmpty else {
            throw PronoteAuthenticationError.invalidChallengeResult
        }

        // ---------------------------------------------------------
        // 4. RECHIFFREMENT DU CHALLENGE
        // ---------------------------------------------------------

        let solvedChallengeData = try PronoteCrypto.aesCBCEncrypt(
            Data(solvedText.utf8),
            key: challengeKey,
            iv: sessionIV
        )

        let solvedChallenge = PronoteCrypto.hexString(
            from: solvedChallengeData,
            uppercase: true
        )

        // ---------------------------------------------------------
        // 5. AUTHENTIFICATION
        // ---------------------------------------------------------

        let authenticationData: [String: Any] = [
            "connexion": 0,
            "challenge": solvedChallenge,
            "espace": spaceID
        ]

        let authenticationWrapper: [String: Any] = [
            "data": authenticationData
        ]

        let authenticationRequestNumber = try encryptedOrder(
            5,
            key: defaultKey,
            iv: sessionIV
        )

        let authenticationDataSec = try PronoteCodec.encodeRequestDataSec(
            authenticationWrapper,
            compressed: true,
            encrypted: true,
            key: defaultKey,
            iv: sessionIV
        )

        let authenticationBody: [String: Any] = [
            "session": Int(session.sessionID) ?? 0,
            "no": authenticationRequestNumber,
            "id": "Authentification",
            "dataSec": authenticationDataSec
        ]

        let authenticationResponse = try await send(
            body: authenticationBody,
            serverURL: sessionServerURL(from: session),
            spaceID: session.spaceID,
            sessionID: session.sessionID,
            requestNumber: authenticationRequestNumber
        )

        let authenticationDecoded = try decodeResponse(
            authenticationResponse,
            compressed: true,
            encrypted: true,
            key: defaultKey,
            iv: sessionIV
        )

        guard let authentication = authenticationDecoded as? [String: Any] else {
            throw PronoteAuthenticationError.invalidResponse
        }

        // ---------------------------------------------------------
        // 6. RÉCUPÉRATION DE "cle"
        // ---------------------------------------------------------

        guard let encryptedKeyString = stringValue(
            named: "cle",
            in: authentication
        ) else {
            throw PronoteAuthenticationError.missingAuthenticationKey
        }

        guard let encryptedKey = try? PronoteCrypto.data(
            fromHex: encryptedKeyString
        ) else {
            throw PronoteAuthenticationError.invalidAuthenticationKey
        }

        let decryptedKey: Data

        do {
            decryptedKey = try PronoteCrypto.aesCBCDecrypt(
                encryptedKey,
                key: challengeKey,
                iv: sessionIV
            )
        } catch {
            throw PronoteAuthenticationError.invalidAuthenticationKey
        }

        guard let keyString = String(
            data: decryptedKey,
            encoding: .utf8
        ) else {
            throw PronoteAuthenticationError.invalidAuthenticationKey
        }

        let keyBytes = keyString
            .split(separator: ",")
            .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }

        guard !keyBytes.isEmpty else {
            throw PronoteAuthenticationError.invalidAuthenticationKey
        }

        // Nouvelle clé AES = MD5(bytes de "cle")
        let authenticationKey = PronoteCrypto.md5(
            Data(keyBytes)
        )

        let userName = stringValue(
            named: "libelleUtil",
            in: authentication
        )

        let mobileToken = stringValue(
            named: "jetonConnexionAppliMobile",
            in: authentication
        )

        return PronoteAuthenticationResult(
            serverURL: session.serverURL,
            sessionID: session.sessionID,
            spaceID: spaceID,
            requestNumber: 7,
            userName: userName,
            mobileToken: mobileToken,
            authenticationKey: authenticationKey,
            sessionIV: session.sessionIV
        )
    }
    // MARK: - Helpers

    private func send(
        body: [String: Any],
        serverURL: String,
        spaceID: Int,
        sessionID: String,
        requestNumber: String
    ) async throws -> [String: Any] {

        let bodyData = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        let endpoint = try PronoteFunctionParametersClient.appelFonctionURL(
            serverURL: serverURL,
            spaceID: spaceID,
            sessionID: sessionID,
            requestNumber: requestNumber
        )

        let responseData = try await transport.post(
            to: endpoint,
            body: bodyData,
            additionalHeaders: [:]
        )

        guard let response = try JSONSerialization.jsonObject(
            with: responseData
        ) as? [String: Any] else {
            throw PronoteAuthenticationError.invalidResponse
        }

        return response
    }

    private func decodeResponse(
        _ response: [String: Any],
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> Any {

        guard let dataSec = response["dataSec"] else {
            throw PronoteAuthenticationError.invalidResponse
        }

        guard let hex = dataSec as? String else {
            throw PronoteAuthenticationError.unsupportedDataSec
        }

        return try PronoteCodec.decodeResponseDataSec(
            hex,
            compressed: compressed,
            encrypted: encrypted,
            key: key,
            iv: iv
        )
    }

    private func encryptedOrder(
        _ number: Int,
        key: Data,
        iv: Data
    ) throws -> String {

        let encrypted = try PronoteCrypto.aesCBCEncrypt(
            Data(String(number).utf8),
            key: key,
            iv: iv
        )

        return PronoteCrypto.hexString(
            from: encrypted,
            uppercase: true
        )
    }

    private func sessionServerURL(
        from session: PronoteInitialSession
    ) -> String {
        session.serverURL
    }

    private func stringValue(
        named name: String,
        in dictionary: [String: Any]
    ) -> String? {
        dictionary[name] as? String
    }

    private func intValue(
        named name: String,
        in dictionary: [String: Any]
    ) -> Int? {
        if let value = dictionary[name] as? Int {
            return value
        }

        if let value = dictionary[name] as? NSNumber {
            return value.intValue
        }

        return nil
    }
}