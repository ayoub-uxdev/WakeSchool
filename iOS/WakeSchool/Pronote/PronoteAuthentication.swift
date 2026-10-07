import Foundation

enum PronoteAuthenticationError: Error, Equatable, LocalizedError {
    case invalidCredentials
    case invalidSession
    case invalidResponse
    case invalidResponseOrder
    case missingChallenge
    case missingAlea
    case missingPasswordMode
    case invalidChallenge
    case invalidAuthenticationKey
    case missingAuthenticationKey
    case invalidMobileToken
    case invalidServerURL
    case invalidDataSec

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Les identifiants PRONOTE sont invalides."
        case .invalidSession:
            return "La session PRONOTE est invalide."
        case .invalidResponse:
            return "La réponse PRONOTE est invalide."
        case .invalidResponseOrder:
            return "Le numéro d'ordre de la réponse PRONOTE est invalide."
        case .missingChallenge:
            return "PRONOTE n'a pas fourni le challenge d'authentification."
        case .missingAlea:
            return "PRONOTE n'a pas fourni l'aléa d'authentification."
        case .missingPasswordMode:
            return "PRONOTE n'a pas fourni le mode de calcul du mot de passe."
        case .invalidChallenge:
            return "Le challenge PRONOTE est invalide."
        case .invalidAuthenticationKey:
            return "La clé d'authentification PRONOTE est invalide."
        case .missingAuthenticationKey:
            return "PRONOTE n'a pas fourni la clé d'authentification."
        case .invalidMobileToken:
            return "Le jeton mobile PRONOTE est invalide."
        case .invalidServerURL:
            return "L'URL du serveur PRONOTE est invalide."
        case .invalidDataSec:
            return "Le dataSec PRONOTE n'est pas au format attendu."
        }
    }
}

struct PronoteAuthenticationResult {
    let serverURL: String
    let sessionID: String
    let spaceID: Int
    let requestNumber: Int
    let userName: String
    let mobileToken: String?
    let authenticationKey: Data
    let sessionIV: Data
}

struct PronoteAuthentication {

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

        guard !session.sessionID.isEmpty else {
            throw PronoteAuthenticationError.invalidSession
        }

        guard
            let serverURL = URL(string: session.serverURL),
            serverURL.scheme != nil,
            serverURL.host != nil
        else {
            throw PronoteAuthenticationError.invalidServerURL
        }

        let defaultKey = PronoteCrypto.aesKey(fromSeed: nil)
        let sessionIV = session.sessionIV

        // Pour l'instant, PronoteInitialSession ne conserve pas
        // les flags sCrA / sCoA récupérés au bootstrap.
        let compressed = true
        let encrypted = true

        // =========================================================
        // 1. IDENTIFICATION
        // =========================================================

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

        let identificationNumber = try encryptedOrder(
            3,
            key: defaultKey,
            iv: sessionIV
        )

        let identificationDataSec = try PronoteCodec.encodeRequestDataSec(
            identificationWrapper,
            compressed: compressed,
            encrypted: encrypted,
            key: defaultKey,
            iv: sessionIV
        )

        let identificationDataSecString = try dataSecString(
            identificationDataSec
        )

        let identificationResponse = try await send(
            function: "Identification",
            requestNumber: identificationNumber,
            dataSec: identificationDataSecString,
            session: session
        )

        let identificationDecoded = try decodeResponse(
            identificationResponse,
            compressed: compressed,
            encrypted: encrypted,
            key: defaultKey,
            iv: sessionIV
        )

        guard let identificationObject = identificationDecoded as? [String: Any] else {
            throw PronoteAuthenticationError.invalidResponse
        }

        let identificationDataObject =
            (identificationObject["data"] as? [String: Any])
            ?? identificationObject

        guard
            let challenge = stringValue(
                named: "challenge",
                in: identificationDataObject
            )
        else {
            throw PronoteAuthenticationError.missingChallenge
        }

        guard
            let alea = stringValue(
                named: "alea",
                in: identificationDataObject
            )
        else {
            throw PronoteAuthenticationError.missingAlea
        }

        guard
            let modeCompMdp = intValue(
                named: "modeCompMdp",
                in: identificationDataObject
            )
        else {
            throw PronoteAuthenticationError.missingPasswordMode
        }

        // =========================================================
        // 2. CALCUL DU MOT DE PASSE
        // =========================================================

        let effectivePassword: String

        switch modeCompMdp {
        case 0:
            effectivePassword = password

        default:
            let passwordSeed = "\(alea)\(password)"

            let passwordHash = PronoteCrypto.sha256(
                Data(passwordSeed.utf8)
            )

            effectivePassword = PronoteCrypto.hexString(
                from: passwordHash,
                uppercase: true
            )
        }

        // =========================================================
        // 3. CLÉ DU CHALLENGE
        // =========================================================

        let mtpSeed = "\(alea)\(effectivePassword)"

        let mtpHash = PronoteCrypto.sha256(
            Data(mtpSeed.utf8)
        )

        let mtp = PronoteCrypto.hexString(
            from: mtpHash,
            uppercase: true
        )

        let challengeKey = PronoteCrypto.md5(
            Data("\(username)\(mtp)".utf8)
        )

        // =========================================================
        // 4. DÉCHIFFREMENT DU CHALLENGE
        // =========================================================

        guard let challengeData = try? PronoteCrypto.data(
            fromHex: challenge
        ) else {
            throw PronoteAuthenticationError.invalidChallenge
        }

        let decryptedChallenge = try PronoteCrypto.aesCBCDecrypt(
            challengeData,
            key: challengeKey,
            iv: sessionIV
        )

        guard
            let challengeString = String(
                data: decryptedChallenge,
                encoding: .utf8
            )
        else {
            throw PronoteAuthenticationError.invalidChallenge
        }

        let solvedChallenge = String(
            challengeString.enumerated().compactMap { index, character in
                index.isMultiple(of: 2) ? character : nil
            }
        )

        guard !solvedChallenge.isEmpty else {
            throw PronoteAuthenticationError.invalidChallenge
        }

        let encryptedSolvedChallenge = try PronoteCrypto.aesCBCEncrypt(
            Data(solvedChallenge.utf8),
            key: challengeKey,
            iv: sessionIV
        )

        let solvedChallengeHex = PronoteCrypto.hexString(
            from: encryptedSolvedChallenge,
            uppercase: true
        )

        // =========================================================
        // 5. AUTHENTIFICATION
        // =========================================================

        let authenticationData: [String: Any] = [
            "connexion": 0,
            "challenge": solvedChallengeHex,
            "espace": spaceID
        ]

        let authenticationWrapper: [String: Any] = [
            "data": authenticationData
        ]

        let authenticationNumber = try encryptedOrder(
            5,
            key: defaultKey,
            iv: sessionIV
        )

        let authenticationDataSec = try PronoteCodec.encodeRequestDataSec(
            authenticationWrapper,
            compressed: compressed,
            encrypted: encrypted,
            key: defaultKey,
            iv: sessionIV
        )

        let authenticationDataSecString = try dataSecString(
            authenticationDataSec
        )

        let authenticationResponse = try await send(
            function: "Authentification",
            requestNumber: authenticationNumber,
            dataSec: authenticationDataSecString,
            session: session
        )

        let authenticationDecoded = try decodeResponse(
            authenticationResponse,
            compressed: compressed,
            encrypted: encrypted,
            key: defaultKey,
            iv: sessionIV
        )

        guard let authenticationObject = authenticationDecoded as? [String: Any] else {
            throw PronoteAuthenticationError.invalidResponse
        }

        let authenticationDataObject =
            (authenticationObject["data"] as? [String: Any])
            ?? authenticationObject

        // =========================================================
        // 6. JETON MOBILE
        // =========================================================

        let mobileToken =
            stringValue(
                named: "jetonConnexionAppliMobile",
                in: authenticationDataObject
            )
            ?? stringValue(
                named: "mobileToken",
                in: authenticationDataObject
            )

        // =========================================================
        // 7. CLÉ D'AUTHENTIFICATION
        // =========================================================

        guard
            let cle = stringValue(
                named: "cle",
                in: authenticationDataObject
            )
        else {
            throw PronoteAuthenticationError.missingAuthenticationKey
        }

        let cleData: Data

        do {
            cleData = try PronoteCrypto.data(fromHex: cle)
        } catch {
            throw PronoteAuthenticationError.invalidAuthenticationKey
        }

        let decryptedKey = try PronoteCrypto.aesCBCDecrypt(
            cleData,
            key: challengeKey,
            iv: sessionIV
        )

        guard !decryptedKey.isEmpty else {
            throw PronoteAuthenticationError.invalidAuthenticationKey
        }

        let authenticationKey = PronoteCrypto.md5(
            decryptedKey
        )

        return PronoteAuthenticationResult(
            serverURL: session.serverURL,
            sessionID: session.sessionID,
            spaceID: spaceID,
            requestNumber: 7,
            userName: username,
            mobileToken: mobileToken,
            authenticationKey: authenticationKey,
            sessionIV: session.sessionIV
        )
    }

    // =============================================================
    // HTTP
    // =============================================================

    private func send(
        function: String,
        requestNumber: String,
        dataSec: String,
        session: PronoteInitialSession
    ) async throws -> Data {

        guard let numericSessionID = Int(session.sessionID) else {
            throw PronoteAuthenticationError.invalidSession
        }

        let body: [String: Any] = [
            "session": numericSessionID,
            "no": requestNumber,
            "id": function,
            "dataSec": dataSec
        ]

        let bodyData = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        let endpoint = try PronoteFunctionParametersClient.appelFonctionURL(
            serverURL: session.serverURL,
            spaceID: session.spaceID,
            sessionID: session.sessionID,
            requestNumber: requestNumber
        )

        return try await transport.post(
            to: endpoint,
            body: bodyData,
            additionalHeaders: [:]
        )
    }

    // =============================================================
    // RESPONSE
    // =============================================================

    private func decodeResponse(
        _ responseData: Data,
        compressed: Bool,
        encrypted: Bool,
        key: Data,
        iv: Data
    ) throws -> Any {

        guard
            let response = try JSONSerialization.jsonObject(
                with: responseData,
                options: []
            ) as? [String: Any]
        else {
            throw PronoteAuthenticationError.invalidResponse
        }

        guard let responseOrder = response["no"] as? String else {
            throw PronoteAuthenticationError.invalidResponseOrder
        }

        let decodedOrder = try PronoteCrypto.data(
            fromHex: responseOrder
        )

        let plainOrder = try PronoteCrypto.aesCBCDecrypt(
            decodedOrder,
            key: key,
            iv: iv
        )

        guard String(data: plainOrder, encoding: .utf8) != nil else {
            throw PronoteAuthenticationError.invalidResponseOrder
        }

        guard let responseDataSec = response["dataSec"] else {
            throw PronoteAuthenticationError.invalidResponse
        }

        guard let responseHex = responseDataSec as? String else {
            throw PronoteAuthenticationError.invalidResponse
        }

        return try PronoteCodec.decodeResponseDataSec(
            responseHex,
            compressed: compressed,
            encrypted: encrypted,
            key: key,
            iv: iv
        )
    }

    // =============================================================
    // DATASEC
    // =============================================================

    private func dataSecString(
        _ dataSec: PronoteDataSec
    ) throws -> String {

        switch dataSec {
        case .encodedHex(let value):
            return value

        case .jsonObject:
            throw PronoteAuthenticationError.invalidDataSec
        }
    }

    // =============================================================
    // CRYPTO
    // =============================================================

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

    // =============================================================
    // HELPERS
    // =============================================================

    private func stringValue(
        named name: String,
        in dictionary: [String: Any]
    ) -> String? {

        if let value = dictionary[name] as? String {
            return value
        }

        return nil
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