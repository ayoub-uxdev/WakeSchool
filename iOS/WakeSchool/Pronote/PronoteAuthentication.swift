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
    case challengeDecryptionFailed(
        version: [Int],
        challengeByteCount: Int,
        aleaByteCount: Int,
        loginByteCount: Int,
        loginUTF8ByteCount: Int,
        tokenByteCount: Int,
        tokenUTF8ByteCount: Int,
        temporaryIVByteCount: Int,
        sessionIVByteCount: Int,
        loginWasNormalized: Bool,
        passwordWasNormalized: Bool,
        requestsAreEncrypted: Bool,
        requestsAreCompressed: Bool,
        isQRLogin: Bool,
        usesENTAuthentication: Bool
    )
    case challengeFormatInvalid
    case missingSessionKey
    case unsupportedLogin

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Réponse d'authentification PRONOTE invalide."
        case .missingField(let field):
            return "Champ PRONOTE manquant : \(field)."
        case .challengeDecryptionFailed(
            let version,
            let challengeByteCount,
            let aleaByteCount,
            let loginByteCount,
            let loginUTF8ByteCount,
            let tokenByteCount,
            let tokenUTF8ByteCount,
            let temporaryIVByteCount,
            let sessionIVByteCount,
            let loginWasNormalized,
            let passwordWasNormalized,
            let requestsAreEncrypted,
            let requestsAreCompressed,
            let isQRLogin,
            let usesENTAuthentication
        ):
            let versionText = version.map(String.init).joined(separator: ".")
            return """
                Impossible de déchiffrer le challenge PRONOTE. \
                Diagnostic sans identifiants : version=\(versionText), \
                challenge=\(challengeByteCount) octets, alea=\(aleaByteCount) octets, \
                login=\(loginByteCount) octets/\(loginUTF8ByteCount) UTF-8, \
                jeton=\(tokenByteCount) octets/\(tokenUTF8ByteCount) UTF-8, \
                IVtemp=\(temporaryIVByteCount) octets, IVsession=\(sessionIVByteCount) octets, \
                loginNormalisé=\(loginWasNormalized), motDePasseNormalisé=\(passwordWasNormalized), \
                requêtesChiffrées=\(requestsAreEncrypted), \
                requêtesCompressées=\(requestsAreCompressed), QR=\(isQRLogin), \
                modeENT=\(usesENTAuthentication).
                """
        case .challengeFormatInvalid:
            return "Challenge PRONOTE invalide."
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
            "uuidAppliMobile": options.mobileUUID ?? "",
            "loginTokenSAV": options.mobileToken ?? ""
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

        var identificationData = try Self.dataDictionary(
            from: identificationResponse,
            version: session.version
        )
        var challenge = try Self.string(identificationData["challenge"], field: "challenge")
        var alea = (identificationData["alea"] as? String) ?? ""
        var modeCompMdp = Self.int(identificationData["modeCompMdp"]) == 1
        var modeCompLog = Self.int(identificationData["modeCompLog"]) == 1

        var normalizedUsername = modeCompLog ? username.lowercased() : username
        var normalizedPassword = modeCompMdp ? password.lowercased() : password

        var authenticationUsesENT = options.useENT
        var usedENTFallback = false
        var loginKeys = PronoteCrypto.deriveLoginKeys(
            username: normalizedUsername,
            password: normalizedPassword,
            alea: alea,
            ivTemp: initial.temporaryIV,
            isENT: authenticationUsesENT
        )
        var authKey = loginKeys.authKey

        var challengeBytes: Data
        do {
            challengeBytes = try PronoteCrypto.data(fromHex: challenge)
        } catch {
            throw PronoteAuthenticationError.challengeFormatInvalid
        }

        var challengePlain: Data
        do {
            challengePlain = try PronoteCrypto.aesCBCDecrypt(
                challengeBytes,
                key: authKey,
                iv: initial.sessionIV
            )
        } catch {
            guard isQRLogin, !authenticationUsesENT else {
                throw Self.challengeDecryptionError(
                    version: session.version,
                    challengeBytes: challengeBytes,
                    alea: alea,
                    username: normalizedUsername,
                    password: normalizedPassword,
                    initial: initial,
                    modeCompLog: modeCompLog,
                    modeCompMdp: modeCompMdp,
                    isQRLogin: isQRLogin,
                    usesENTAuthentication: authenticationUsesENT
                )
            }

            var entIdentification = identification
            entIdentification["pourENT"] = true
            let entIdentificationResponse = try await post(
                function: "Identification",
                data: [apiProperties.data: entIdentification],
                session: session,
                requestNumber: initial.requestNumber + 2,
                key: defaultKey,
                iv: initial.sessionIV,
                compressed: initial.requestsAreCompressed,
                encrypted: initial.requestsAreEncrypted
            )
            identificationData = try Self.dataDictionary(
                from: entIdentificationResponse,
                version: session.version
            )
            challenge = try Self.string(identificationData["challenge"], field: "challenge")
            alea = (identificationData["alea"] as? String) ?? ""
            modeCompMdp = Self.int(identificationData["modeCompMdp"]) == 1
            modeCompLog = Self.int(identificationData["modeCompLog"]) == 1
            normalizedUsername = modeCompLog ? username.lowercased() : username
            normalizedPassword = modeCompMdp ? password.lowercased() : password
            authenticationUsesENT = true
            usedENTFallback = true

            do {
                challengeBytes = try PronoteCrypto.data(fromHex: challenge)
            } catch {
                throw PronoteAuthenticationError.challengeFormatInvalid
            }
            loginKeys = PronoteCrypto.deriveLoginKeys(
                username: normalizedUsername,
                password: normalizedPassword,
                alea: alea,
                ivTemp: initial.temporaryIV,
                isENT: authenticationUsesENT
            )
            authKey = loginKeys.authKey

            do {
                challengePlain = try PronoteCrypto.aesCBCDecrypt(
                    challengeBytes,
                    key: authKey,
                    iv: initial.sessionIV
                )
            } catch {
                throw Self.challengeDecryptionError(
                    version: session.version,
                    challengeBytes: challengeBytes,
                    alea: alea,
                    username: normalizedUsername,
                    password: normalizedPassword,
                    initial: initial,
                    modeCompLog: modeCompLog,
                    modeCompMdp: modeCompMdp,
                    isQRLogin: isQRLogin,
                    usesENTAuthentication: authenticationUsesENT
                )
            }
        }

        guard let challengeText = String(data: challengePlain, encoding: .utf8) else {
            throw PronoteAuthenticationError.challengeFormatInvalid
        }

        let solved = String(
            challengeText.enumerated().compactMap {
                $0.offset.isMultiple(of: 2) ? $0.element : nil
            }
        )

        let solvedCipher = try PronoteCrypto.aesCBCEncrypt(
            Data(solved.utf8),
            key: authKey,
            iv: initial.sessionIV
        )

        let authData: [String: Any] = [
            "connexion": 0,
            "challenge": PronoteCrypto.hexString(from: solvedCipher, uppercase: false),
            "espace": session.spaceID
        ]

        let authResponse = try await post(
            function: "Authentification",
            data: [apiProperties.data: authData],
            session: session,
            requestNumber: initial.requestNumber + (usedENTFallback ? 4 : 2),
            key: defaultKey,
            iv: initial.sessionIV,
            compressed: initial.requestsAreCompressed,
            encrypted: initial.requestsAreEncrypted
        )

        let authenticatedData = try Self.dataDictionary(
            from: authResponse,
            version: session.version
        )
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
            requestNumber: initial.requestNumber + (usedENTFallback ? 6 : 4),
            sessionKey: sessionKey,
            sessionIV: initial.sessionIV,
            requestsAreEncrypted: initial.requestsAreEncrypted,
            requestsAreCompressed: initial.requestsAreCompressed,
            userName: userName,
            mobileToken: token,
            initialParameters: nil
        )
    }

    private static func challengeDecryptionError(
        version: [Int],
        challengeBytes: Data,
        alea: String,
        username: String,
        password: String,
        initial: PronoteInitialSession,
        modeCompLog: Bool,
        modeCompMdp: Bool,
        isQRLogin: Bool,
        usesENTAuthentication: Bool
    ) -> PronoteAuthenticationError {
        PronoteAuthenticationError.challengeDecryptionFailed(
            version: version,
            challengeByteCount: challengeBytes.count,
            aleaByteCount: PronoteCrypto.binaryStringData(alea).count,
            loginByteCount: PronoteCrypto.binaryStringData(username).count,
            loginUTF8ByteCount: Data(username.utf8).count,
            tokenByteCount: PronoteCrypto.binaryStringData(password).count,
            tokenUTF8ByteCount: Data(password.utf8).count,
            temporaryIVByteCount: initial.temporaryIV.count,
            sessionIVByteCount: initial.sessionIV.count,
            loginWasNormalized: modeCompLog,
            passwordWasNormalized: modeCompMdp,
            requestsAreEncrypted: initial.requestsAreEncrypted,
            requestsAreCompressed: initial.requestsAreCompressed,
            isQRLogin: isQRLogin,
            usesENTAuthentication: usesENTAuthentication
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
