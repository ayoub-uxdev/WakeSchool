import Foundation

struct PronoteLoginOptions {
    var useENT: Bool = false
    var mobileUUID: String? = nil
    var clientIdentifier: String? = nil
    var mobileToken: String? = nil
    var requestFirstMobileAuthentication: Bool = false
    var qrLogin: Bool = false
    var automaticReconnection: Bool = false

    static func automaticReconnection(
        for credentials: PronoteCredentials
    ) -> Self {
        Self(
            useENT: false,
            mobileUUID: credentials.mobileUUID,
            clientIdentifier: credentials.mobileUUID,
            mobileToken: credentials.usesMobileToken ? credentials.password : nil,
            requestFirstMobileAuthentication: false,
            qrLogin: false,
            automaticReconnection: true
        )
    }
}

enum PronoteLoginStage: Equatable {
    case entConnection
    case mobileTokenRecovery
    case identification
    case authentication
    case automaticReconnection

    var label: String {
        switch self {
        case .entConnection: return "Connexion ENT"
        case .mobileTokenRecovery: return "Récupération ou validation du jeton mobile"
        case .identification: return "Identification PRONOTE"
        case .authentication: return "Authentification PRONOTE"
        case .automaticReconnection: return "Reconnexion automatique"
        }
    }
}

struct PronoteLoginDiagnosticError: Error, LocalizedError, Equatable {
    let stage: PronoteLoginStage
    let operation: PronoteLoginStage?
    let message: String

    var errorDescription: String? {
        if let operation {
            return "\(stage.label) (\(operation.label)) : \(message)"
        }
        return "\(stage.label) : \(message)"
    }
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
    case emptyMobileToken
    case mobileTokenMismatch
    case missingMobileUUID
    case mobileUUIDMismatch
    case missingClientIdentifier
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
        case .emptyMobileToken:
            return "Le jeton mobile PRONOTE enregistré est vide."
        case .mobileTokenMismatch:
            return "Le jeton mobile sélectionné ne correspond pas au jeton des identifiants enregistrés."
        case .missingMobileUUID:
            return "L'identifiant stable de cette installation est absent."
        case .mobileUUIDMismatch:
            return "L'identifiant mobile sélectionné ne correspond pas à l'identifiant enregistré."
        case .missingClientIdentifier:
            return "L'identifiant client PRONOTE est absent."
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
        let mobileUUID = options.mobileUUID ?? credentials.mobileUUID ?? ""
        let diagnosticContext = Self.diagnosticContext(
            credentials: credentials,
            options: options,
            mobileUUID: mobileUUID
        )
        if let mobileToken = options.mobileToken {
            guard !mobileToken.isEmpty else {
                throw Self.diagnosticError(
                    PronoteAuthenticationError.emptyMobileToken,
                    stage: .identification,
                    options: options,
                    context: diagnosticContext
                )
            }
            guard mobileToken == credentials.password else {
                throw Self.diagnosticError(
                    PronoteAuthenticationError.mobileTokenMismatch,
                    stage: .identification,
                    options: options,
                    context: diagnosticContext
                )
            }
            guard !mobileUUID.isEmpty else {
                throw Self.diagnosticError(
                    PronoteAuthenticationError.missingMobileUUID,
                    stage: .identification,
                    options: options,
                    context: diagnosticContext
                )
            }
            if let storedMobileUUID = credentials.mobileUUID,
               storedMobileUUID != mobileUUID {
                throw Self.diagnosticError(
                    PronoteAuthenticationError.mobileUUIDMismatch,
                    stage: .identification,
                    options: options,
                    context: diagnosticContext
                )
            }
            guard options.clientIdentifier?.isEmpty == false else {
                throw Self.diagnosticError(
                    PronoteAuthenticationError.missingClientIdentifier,
                    stage: .identification,
                    options: options,
                    context: diagnosticContext
                )
            }
        }
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
            "loginTokenSAV": ""
        ]

        let identificationData = try await withDiagnostic(
            .identification,
            automaticReconnection: options.automaticReconnection,
            context: diagnosticContext
        ) {
            let response = try await post(
                function: "Identification",
                data: [apiProperties.data: identification],
                session: session,
                requestNumber: initial.requestNumber,
                key: defaultKey,
                iv: initial.sessionIV,
                compressed: initial.requestsAreCompressed,
                encrypted: initial.requestsAreEncrypted
            )
            let data = try Self.dataDictionary(from: response, version: session.version)
            let challenge = try Self.string(data["challenge"], field: "challenge")
            guard !challenge.isEmpty else {
                throw PronoteAuthenticationError.challengeFormatInvalid
            }
            return data
        }

        let challenge = try Self.string(identificationData["challenge"], field: "challenge")
        let alea = (identificationData["alea"] as? String) ?? ""
        let modeCompMdp = Self.int(identificationData["modeCompMdp"]) > 0
        let modeCompLog = Self.int(identificationData["modeCompLog"]) > 0

        let normalizedUsername: String
        if modeCompLog && !options.useENT {
            normalizedUsername = username
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            normalizedUsername = username
        }
        var normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if modeCompMdp && !options.useENT {
            normalizedPassword = normalizedPassword.lowercased()
        }

        let (sessionKey, userName, token) = try await withDiagnostic(
            .authentication,
            automaticReconnection: options.automaticReconnection,
            context: diagnosticContext
        ) {
            let authKey = PronoteCrypto.deriveLoginKeys(
                username: normalizedUsername,
                password: normalizedPassword,
                alea: alea,
                ivTemp: initial.temporaryIV,
                isENT: options.useENT
            ).authKey

            let solvedChallenge = try PronoteCrypto.aesCBCEncrypt(
                Data(challenge.utf8),
                key: authKey,
                iv: initial.sessionIV
            )

            var authData: [String: Any] = [
                "connexion": 0,
                "challenge": PronoteCrypto.hexString(from: solvedChallenge),
                "espace": session.spaceID
            ]

            let response = try await post(
                function: "Authentification",
                data: [apiProperties.data: authData],
                session: session,
                requestNumber: initial.requestNumber + 2,
                key: defaultKey,
                iv: initial.sessionIV,
                compressed: initial.requestsAreCompressed,
                encrypted: initial.requestsAreEncrypted
            )
            let data = try Self.dataDictionary(from: response, version: session.version)
            let accessCode = Self.int(data["Acces"])
            if accessCode != 0 {
                throw PronoteAuthenticationError.authenticationRejected(accessCode)
            }
            guard let cle = data["cle"] as? String else {
                throw PronoteAuthenticationError.missingSessionKey
            }
            let sessionKey = try PronoteCrypto.deriveSessionKey(
                cleCipherHex: cle,
                authKey: authKey,
                iv: initial.sessionIV
            )
            return (
                sessionKey,
                data["libelleUtil"] as? String,
                data["jetonConnexionAppliMobile"] as? String
            )
        }

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

    private func withDiagnostic<T>(
        _ operation: PronoteLoginStage,
        automaticReconnection: Bool,
        context: String,
        body: () async throws -> T
    ) async throws -> T {
        do {
            return try await body()
        } catch {
            let stage = automaticReconnection ? PronoteLoginStage.automaticReconnection : operation
            throw PronoteLoginDiagnosticError(
                stage: stage,
                operation: automaticReconnection ? operation : nil,
                message: "\(error.localizedDescription) \(context)"
            )
        }
    }

    private static func diagnosticContext(
        credentials: PronoteCredentials,
        options: PronoteLoginOptions,
        mobileUUID: String
    ) -> String {
        let tokenPresent = options.mobileToken.map { !$0.isEmpty } ?? false
        let mode: String
        if options.qrLogin {
            mode = "QR initial"
        } else if tokenPresent {
            mode = options.automaticReconnection
                ? "reconnexion par jeton mobile"
                : "connexion par jeton mobile"
        } else if options.useENT {
            mode = "identifiants ENT"
        } else {
            mode = "identifiants PRONOTE"
        }
        return "[diagnostic non sensible : mode=\(mode), jetonPrésent=\(tokenPresent), UUIDPrésent=\(!mobileUUID.isEmpty), clientIdentifierPrésent=\(!(options.clientIdentifier ?? "").isEmpty), jetonEnregistré=\(credentials.usesMobileToken), reconnexionAutomatique=\(options.automaticReconnection), enConnexionAppliMobile=\(tokenPresent), demandeConnexionAppliMobile=\(options.requestFirstMobileAuthentication), demandeConnexionAppliMobileJeton=\(options.qrLogin), QR=\(options.qrLogin), ENT=\(options.useENT)]"
    }

    private static func diagnosticError(
        _ error: Error,
        stage: PronoteLoginStage,
        options: PronoteLoginOptions,
        context: String
    ) -> PronoteLoginDiagnosticError {
        let automaticReconnection = options.automaticReconnection
        return PronoteLoginDiagnosticError(
            stage: automaticReconnection ? .automaticReconnection : stage,
            operation: automaticReconnection ? stage : nil,
            message: "\(error.localizedDescription) \(context)"
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
