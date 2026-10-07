import Foundation
import Security

enum PronoteFunctionParametersError: Error, Equatable, LocalizedError {
    case invalidSessionID
    case invalidIV
    case invalidServerURL
    case unsupportedHTTP
    case invalidResponse
    case invalidResponseOrder
    case missingResponseData
    case unsupportedDataSec

    var errorDescription: String? {
        switch self {
        case .invalidSessionID:
            return "L'identifiant de session PRONOTE est invalide."
        case .invalidIV:
            return "L'IV temporaire PRONOTE est invalide."
        case .invalidServerURL:
            return "L'URL PRONOTE est invalide."
        case .unsupportedHTTP:
            return "La connexion PRONOTE en HTTP n'est pas encore prise en charge."
        case .invalidResponse:
            return "La réponse FonctionParametres de PRONOTE est invalide."
        case .invalidResponseOrder:
            return "Le numéro d'ordre de la réponse PRONOTE est invalide."
        case .missingResponseData:
            return "La réponse FonctionParametres ne contient pas dataSec."
        case .unsupportedDataSec:
            return "Le format dataSec reçu par PRONOTE n'est pas pris en charge."
        }
    }
}

struct PronoteInitialSession {
    let sessionID: String
    let spaceID: Int
    let requestNumber: Int
    let temporaryIV: Data
    let sessionIV: Data
    let decodedParameters: Any
}

struct PronoteFunctionParametersClient {
    private let transport: PronoteHTTPTransporting

    init(transport: PronoteHTTPTransporting) {
        self.transport = transport
    }

    func start(
        session: PronoteSessionParameters,
        serverURL: String,
        clientIdentifier: String? = nil
    ) async throws -> PronoteInitialSession {

        guard !session.sessionID.isEmpty else {
            throw PronoteFunctionParametersError.invalidSessionID
        }

        guard
            let url = URL(string: serverURL),
            let scheme = url.scheme?.lowercased(),
            url.host != nil
        else {
            throw PronoteFunctionParametersError.invalidServerURL
        }

        guard scheme == "https" else {
            throw PronoteFunctionParametersError.unsupportedHTTP
        }

        let temporaryIV = try Self.randomIV()
        let sessionIV = PronoteCrypto.md5(temporaryIV)

        let defaultKey = PronoteCrypto.aesKey(fromSeed: nil)
        let defaultIV = Data(repeating: 0, count: 16)

        let requestNumber = try Self.encryptedOrder(
            1,
            key: defaultKey,
            iv: defaultIV
        )

        let parameters: [String: Any] = [
            "Uuid": temporaryIV.base64EncodedString(),
            "identifiantNav": clientIdentifier ?? NSNull()
        ]

        let dataWrapper: [String: Any] = [
            "data": parameters
        ]

        let encodedDataSec = try PronoteCodec.encodeRequestDataSec(
            dataWrapper,
            compressed: session.requestsAreCompressed,
            encrypted: session.requestsAreEncrypted,
            key: defaultKey,
            iv: defaultIV
        )

        guard let numericSessionID = Int(session.sessionID) else {
            throw PronoteFunctionParametersError.invalidSessionID
        }

        let body: [String: Any] = [
            "session": numericSessionID,
            "no": requestNumber,
            "id": "FonctionParametres",
            "dataSec": encodedDataSec
        ]

        let bodyData = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        let endpoint = try Self.appelFonctionURL(
            serverURL: serverURL,
            spaceID: session.spaceID,
            sessionID: session.sessionID,
            requestNumber: requestNumber
        )

        let responseData = try await transport.post(
            to: endpoint,
            body: bodyData,
            additionalHeaders: [:]
        )

        guard
            let response = try JSONSerialization.jsonObject(
                with: responseData
            ) as? [String: Any]
        else {
            throw PronoteFunctionParametersError.invalidResponse
        }

        guard let responseOrder = response["no"] as? String else {
            throw PronoteFunctionParametersError.invalidResponseOrder
        }

        let decodedOrder = try PronoteCrypto.data(fromHex: responseOrder)

        let plainOrder = try PronoteCrypto.aesCBCDecrypt(
            decodedOrder,
            key: defaultKey,
            iv: sessionIV
        )

        guard String(data: plainOrder, encoding: .utf8) == "2" else {
            throw PronoteFunctionParametersError.invalidResponseOrder
        }

        guard let responseDataSec = response["dataSec"] else {
            throw PronoteFunctionParametersError.missingResponseData
        }

        let decodedParameters: Any

        if session.requestsAreCompressed || session.requestsAreEncrypted {
            guard let responseHex = responseDataSec as? String else {
                throw PronoteFunctionParametersError.unsupportedDataSec
            }

            decodedParameters = try PronoteCodec.decodeResponseDataSec(
                responseHex,
                compressed: session.requestsAreCompressed,
                encrypted: session.requestsAreEncrypted,
                key: defaultKey,
                iv: sessionIV
            )
        } else {
            decodedParameters = responseDataSec
        }

        return PronoteInitialSession(
            sessionID: session.sessionID,
            spaceID: session.spaceID,
            requestNumber: 3,
            temporaryIV: temporaryIV,
            sessionIV: sessionIV,
            decodedParameters: decodedParameters
        )
    }

    private static func randomIV() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)

        guard SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        ) == errSecSuccess else {
            throw PronoteFunctionParametersError.invalidIV
        }

        return Data(bytes)
    }

    private static func encryptedOrder(
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

    static func appelFonctionURL(
        serverURL: String,
        spaceID: Int,
        sessionID: String,
        requestNumber: String
    ) throws -> URL {

        guard
            var components = URLComponents(string: serverURL),
            components.scheme != nil,
            components.host != nil
        else {
            throw PronoteFunctionParametersError.invalidServerURL
        }

        var path = components.path

        if path.lowercased().hasSuffix(".html") {
            path = String(
                path[..<(path.lastIndex(of: "/") ?? path.endIndex)]
            )
        }

        while path.hasSuffix("/") {
            path.removeLast()
        }

        if path.isEmpty {
            path = "/pronote"
        }

        components.path =
            "\(path)/appelfonction/\(spaceID)/\(sessionID)/\(requestNumber)"

        components.query = nil

        guard let url = components.url else {
            throw PronoteFunctionParametersError.invalidServerURL
        }

        return url
    }
}