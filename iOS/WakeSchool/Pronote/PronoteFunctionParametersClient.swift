import Foundation

struct PronoteInitialSession: Equatable {
    let sessionID: String
    let spaceID: Int
    let requestNumber: Int
    let temporaryIV: Data
    let sessionIV: Data
}

enum PronoteFunctionParametersError: Error, Equatable, LocalizedError {
    case invalidSessionID
    case invalidSpaceID
    case invalidRequestNumber
    case invalidIV
    case invalidResponse
    case unexpectedResponseNumber
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidSessionID: return "L'identifiant de session PRONOTE est invalide."
        case .invalidSpaceID: return "L'identifiant d'espace PRONOTE est invalide."
        case .invalidRequestNumber: return "Le numéro d'ordre PRONOTE est invalide."
        case .invalidIV: return "L'IV PRONOTE est invalide."
        case .invalidResponse: return "La réponse FonctionParametres est invalide."
        case .unexpectedResponseNumber: return "Le numéro d'ordre de la réponse PRONOTE est inattendu."
        case .missingData: return "Les données FonctionParametres sont absentes."
        }
    }
}

struct PronoteFunctionParametersClient {
    private let transport: PronoteHTTPTransporting

    init(transport: PronoteHTTPTransporting) {
        self.transport = transport
    }

    func start(
        session: PronoteSessionParameters,
        serverURL: String,
        clientIdentifier: String? = nil,
        temporaryIV: Data
    ) async throws -> PronoteInitialSession {
        guard !session.sessionID.isEmpty else {
            throw PronoteFunctionParametersError.invalidSessionID
        }
        guard session.spaceID >= 0 else {
            throw PronoteFunctionParametersError.invalidSpaceID
        }
        guard temporaryIV.count == 16 else {
            throw PronoteFunctionParametersError.invalidIV
        }

        let initialOrder = try makeInitialOrder()

        guard let baseURL = URL(string: normalizedRoot(serverURL)) else {
            throw PronoteTransportError.invalidServerURL
        }

        let endpoint = baseURL
            .appendingPathComponent("appelfonction")
            .appendingPathComponent(String(session.spaceID))
            .appendingPathComponent(session.sessionID)
            .appendingPathComponent(initialOrder)

        let uuid = temporaryIV.base64EncodedString()

        var data: [String: Any] = [
            "Uuid": uuid
        ]
        data["identifiantNav"] = clientIdentifier as Any

        let body: [String: Any] = [
            "nom": "FonctionParametres",
            "session": Int(session.sessionID) ?? 0,
            "no": initialOrder,
            "id": "FonctionParametres",
            "dataSec": [
                "data": data
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        let responseData = try await transport.post(
            to: endpoint,
            body: bodyData,
            additionalHeaders: [:]
        )

        let sessionIV = PronoteCrypto.md5(temporaryIV)

        guard let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw PronoteFunctionParametersError.invalidResponse
        }

        guard let responseNumber = response["no"] as? String
                ?? response["numeroOrdre"] as? String else {
            throw PronoteFunctionParametersError.invalidResponse
        }

        let decoded = try PronoteCrypto.data(fromHex: responseNumber)
        let plain = try PronoteCrypto.aesCBCDecrypt(
            decoded,
            key: PronoteCrypto.md5(Data()),
            iv: sessionIV
        )

        guard let numberString = String(data: plain, encoding: .utf8),
              let number = Int(numberString),
              number == 2 else {
            throw PronoteFunctionParametersError.unexpectedResponseNumber
        }

        guard response["dataSec"] != nil else {
            throw PronoteFunctionParametersError.missingData
        }

        return PronoteInitialSession(
            sessionID: session.sessionID,
            spaceID: session.spaceID,
            requestNumber: 3,
            temporaryIV: temporaryIV,
            sessionIV: sessionIV
        )
    }

    private func makeInitialOrder() throws -> String {
        let key = PronoteCrypto.md5(Data())
        let iv = Data(repeating: 0, count: 16)
        let encrypted = try PronoteCrypto.aesCBCEncrypt(
            Data("1".utf8),
            key: key,
            iv: iv
        )
        return PronoteCodec.hex(encrypted)
    }

    private func normalizedRoot(_ serverURL: String) -> String {
        var value = serverURL
        while value.hasSuffix("/") {
            value.removeLast()
        }

        if value.hasSuffix("/mobile.eleve.html") {
            value.removeLast("/mobile.eleve.html".count)
        } else if value.hasSuffix("/eleve.html") {
            value.removeLast("/eleve.html".count)
        }

        return value
    }
}
