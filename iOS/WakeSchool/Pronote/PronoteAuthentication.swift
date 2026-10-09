import Foundation

struct PronoteLoginOptions {
    var useENT: Bool = false
    var mobileUUID: String? = nil
    var clientIdentifier: String? = nil
    var mobileToken: String? = nil
    var requestFirstMobileAuthentication: Bool = false
    var qrLogin: Bool = false
}

struct PronoteAuthenticationResult {
    let sessionID: String
    let spaceID: Int
    let rootURL: URL
    let version: [Int]
    let requestNumber: Int
    let sessionKey: Data
    let sessionIV: Data
    let requestsAreEncrypted: Bool
    let requestsAreCompressed: Bool
    let userName: String?
    let mobileToken: String?
    let initialParameters: Any?
}

enum PronoteAuthenticationError: Error, LocalizedError, Equatable {
    case invalidResponse
    case missingField(String)
    case challengeFormatInvalid
    case authenticationRejected(Int)
    case missingSessionKey
    case unsupportedLogin

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Réponse d'authentification PRONOTE invalide."
        case .missingField(let field):
            return "Champ PRONOTE manquant : \(field)."
        case .challengeFormatInvalid:
            return "PRONOTE a renvoyé un challenge vide ou invalide."
        case .authenticationRejected(let code):
            if code == 1 {
                return "PRONOTE a refusé l'identifiant ou le mot de passe (code 1)."
            }
            return "PRONOTE a refusé l'authentification (code \(code))."
        case .missingSessionKey:
            return "PRONOTE n'a pas fourni de clé de session."
        case .unsupportedLogin:
            return "Ce mode de connexion PRONOTE n'est pas disponible."
        }
    }
}

struct PronoteAuthenticator {
    let transport: PronoteHTTPTransporting

    func authenticate(
        credentials: PronoteCredentials,
        session: PronoteSessionParameters,
        initial: PronoteInitialSession,
        options: PronoteLoginOptions = .init()
    ) async throws -> PronoteAuthenticationResult {
        let username = credentials.username
        let password = credentials.password
        let defaultKey = PronoteCrypto.md5(Data())

        let isQRLogin = options.qrLogin
        let isTokenLogin = options.mobileToken != nil
        let mobileTokenProof: String
        if let mobileToken = options.mobileToken {
            mobileTokenProof = try PronoteCrypto.encryptedMobileTokenProof(
                token: mobileToken,
                iv: initial.sessionIV
            )
        } else {
            mobileTokenProof = ""
        }
        let mobileUUID = options.mobileUUID ?? credentials.mobileUUID ?? ""
        let apiProperties = PronoteAPIProperties.forVersion(session.version)

        let identification: [String: Any] = [
            "genreConnexion": 0,
            "genreEspace": session.spaceID,
            "identifiant": username,
            "pourENT": options.useENT,
            "enConnexionAuto": false,
            "demandeConnexionAuto": false,
            "demandeConnexionAppliMobile": options.requestFirstMobileAuthentication,
            "demandeConnexionAppliMobileJeton": isQRLogin,
            "enConnexionAppliMobile": isTokenLogin,
            "uuidAppliMobile": mobileUUID,
            "loginTokenSAV": mobileTokenProof
        ]

        let identificationResponse = try await post(
            function: "Identification",
            data: [apiProperties.data: identification],
            session: session,
            requestNumber: initial.requestNumber,
            key: defaultKey,
            iv: initial.sessionIV,
            compressed: initial.requestsAreCompressed,
            encrypted: initial.requestsAreEncrypted
        )

        let identificationData = try Self.dataDictionary(
            from: identificationResponse,
            version: session.version
        )
        let challenge = try Self.string(identificationData["challenge"], field: "challenge")
        guard !challenge.isEmpty else {
            throw PronoteAuthenticationError.challengeFormatInvalid
        }
        let alea = (identificationData["alea"] as? String) ?? ""
        let modeCompMdp = Self.int(identificationData["modeCompMdp"]) > 0
        let modeCompLog = Self.int(identificationData["modeCompLog"]) > 0

        let normalizedUsername = modeCompLog ? username.lowercased() : username
        var normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if modeCompMdp {
            normalizedPassword = normalizedPassword.lowercased()
        }

        let authKey: Data
        if let mobileToken = options.mobileToken {
            authKey = PronoteCrypto.aesKey(fromSeed: Data(mobileToken.utf8))
        } else {
            authKey = PronoteCrypto.deriveLoginKeys(
                username: normalizedUsername,
                password: normalizedPassword,
                alea: alea,
                ivTemp: initial.temporaryIV,
                isENT: options.useENT
            ).authKey
        }

        // PRONOTE returns a plaintext UTF-8 challenge; AES-CBC/hex is applied only to the answer.
        let solvedChallenge = try PronoteCrypto.aesCBCEncrypt(
            Data(challenge.utf8),
            key: authKey,
            iv: initial.sessionIV
        )

        var authData: [String: Any] = [
            "connexion": 0,
            "challenge": PronoteCrypto.hexString(from: solvedChallenge, uppercase: false),
            "espace": session.spaceID
        ]
        if isTokenLogin {
            authData["pourENT"] = options.useENT
            authData["identifiant"] = username
            authData["enConnexionAppliMobile"] = true
            authData["demandeConnexionAppliMobile"] = false
            authData["demandeConnexionAppliMobileJeton"] = false
            authData["uuidAppliMobile"] = mobileUUID
            authData["loginTokenSAV"] = mobileTokenProof
        }

        let authResponse = try await post(
            function: "Authentification",
            data: [apiProperties.data: authData],
            session: session,
            requestNumber: initial.requestNumber + 2,
            key: defaultKey,
            iv: initial.sessionIV,
            compressed: initial.requestsAreCompressed,
            encrypted: initial.requestsAreEncrypted
        )

        let authenticatedData = try Self.dataDictionary(
            from: authResponse,
            version: session.version
        )
        let accessCode = Self.int(authenticatedData["Acces"])
        if accessCode != 0 {
            throw PronoteAuthenticationError.authenticationRejected(accessCode)
        }
        guard let cle = authenticatedData["cle"] as? String else {
            throw PronoteAuthenticationError.missingSessionKey
        }

        let sessionKey = try PronoteCrypto.deriveSessionKey(
            cleCipherHex: cle,
            authKey: authKey,
            iv: initial.sessionIV
        )

        let userName = authenticatedData["libelleUtil"] as? String
        let token = authenticatedData["jetonConnexionAppliMobile"] as? String

        return PronoteAuthenticationResult(
            sessionID: session.sessionID,
            spaceID: session.spaceID,
            rootURL: session.rootURL,
            version: session.version,
            requestNumber: initial.requestNumber + 4,
            sessionKey: sessionKey,
            sessionIV: initial.sessionIV,
            requestsAreEncrypted: initial.requestsAreEncrypted,
            requestsAreCompressed: initial.requestsAreCompressed,
            userName: userName,
            mobileToken: token,
            initialParameters: nil
        )
    }

    private func post(
        function: String,
        data: [String: Any],
        session: PronoteSessionParameters,
        requestNumber: Int,
        key: Data,
        iv: Data,
        compressed: Bool,
        encrypted: Bool
    ) async throws -> [String: Any] {
        let encryptedOrder = try PronoteCrypto.aesCBCEncrypt(
            Data(String(requestNumber).utf8),
            key: key,
            iv: iv
        )
        let order = PronoteCodec.hex(encryptedOrder)

        let dataSec = try PronoteCodec.encodeDataSec(
            data,
            compressed: compressed,
            encrypted: encrypted,
            key: key,
            iv: iv
        )

        let properties = PronoteAPIProperties.forVersion(session.version)
        let body: [String: Any] = [
            "session": Int(session.sessionID) ?? 0,
            properties.orderNumber: order,
            properties.requestID: function,
            properties.secureData: Self.dataSecJSON(dataSec)
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        let endpoint = PronoteHTTPTransport.appelfonctionURL(
            rootURL: session.rootURL,
            spaceID: session.spaceID,
            sessionID: session.sessionID,
            order: order
        )

        let responseData = try await transport.post(
            to: endpoint,
            body: bodyData,
            additionalHeaders: [:]
        )

        guard var response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw PronoteAuthenticationError.invalidResponse
        }

        if let responseNo = response["no"] as? String ?? response["numeroOrdre"] as? String {
            let plain = try PronoteCrypto.aesCBCDecrypt(
                try PronoteCrypto.data(fromHex: responseNo),
                key: key,
                iv: iv
            )
            _ = Int(String(data: plain, encoding: .utf8) ?? "")
        }

        let secureDataKey = properties.secureData
        if let responseDataSec = response[secureDataKey] as? String {
            response[secureDataKey] = try PronoteCodec.decodeDataSec(
                responseDataSec,
                compressed: compressed,
                encrypted: encrypted,
                key: key,
                iv: iv
            )
        } else if secureDataKey != "dataSec",
                  let responseDataSec = response["dataSec"] as? String {
            response["dataSec"] = try PronoteCodec.decodeDataSec(
                responseDataSec,
                compressed: compressed,
                encrypted: encrypted,
                key: key,
                iv: iv
            )
        }

        return response
    }

    private static func dataSecJSON(_ value: PronoteDataSec) -> Any {
        switch value {
        case .jsonObject(let object):
            return object
        case .encodedHex(let hex):
            return hex
        }
    }

    private static func dataDictionary(
        from response: [String: Any],
        version: [Int]
    ) throws -> [String: Any] {
        let properties = PronoteAPIProperties.forVersion(version)

        if let dataSec = response[properties.secureData] as? [String: Any] {
            if let data = dataSec[properties.data] as? [String: Any] { return data }
            if let data = dataSec["data"] as? [String: Any] { return data }
            if let donnees = dataSec["donnees"] as? [String: Any] { return donnees }
            return dataSec
        }

        if let dataSec = response["dataSec"] as? [String: Any]
            ?? response["donneesSec"] as? [String: Any] {
            if let data = dataSec["data"] as? [String: Any] { return data }
            if let donnees = dataSec["donnees"] as? [String: Any] { return donnees }
            return dataSec
        }

        throw PronoteAuthenticationError.invalidResponse
    }

    private static func string(_ value: Any?, field: String) throws -> String {
        guard let value = value as? String else {
            throw PronoteAuthenticationError.missingField(field)
        }
        return value
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }
}
