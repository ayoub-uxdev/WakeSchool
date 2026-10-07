import Foundation

enum PronoteSessionError: Error, Equatable, LocalizedError {
    case invalidSession
    case invalidResponse
    case invalidResponseOrder
    case missingDataSec
    case unsupportedDataSec

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            return "La session PRONOTE est invalide."
        case .invalidResponse:
            return "La réponse PRONOTE est invalide."
        case .invalidResponseOrder:
            return "Le numéro d'ordre PRONOTE est invalide."
        case .missingDataSec:
            return "PRONOTE n'a pas fourni dataSec."
        case .unsupportedDataSec:
            return "Le format dataSec PRONOTE n'est pas pris en charge."
        }
    }
}

struct PronoteSessionClient {
    private let transport: PronoteHTTPTransporting
    private let session: PronoteAuthenticationResult
    private let serverURL: String

    private var requestNumber: Int
    private let encryptionKey: Data
    private let encryptionIV: Data

    init(
        transport: PronoteHTTPTransporting,
        session: PronoteAuthenticationResult,
        serverURL: String
    ) throws {
        guard !session.sessionID.isEmpty else {
            throw PronoteSessionError.invalidSession
        }

        self.transport = transport
        self.session = session
        self.serverURL = serverURL
        self.requestNumber = session.requestNumber
        self.encryptionKey = session.authenticationKey

        // Après FonctionParametres, l'IV de session reste celui
        // communiqué au début de la session.
        //
        // Il sera remplacé ici par le même IV utilisé pendant
        // l'authentification.
        self.encryptionIV = session.sessionIV
    }

    // MARK: - ParametresUtilisateur

    func fetchUserParameters() async throws -> Any {
        try await request(
            function: "ParametresUtilisateur",
            data: [:]
        )
    }

    // MARK: - Generic request

    func request(
        function: String,
        data: [String: Any]
    ) async throws -> Any {

        let logicalNumber = requestNumber

        let encryptedNumber = try encryptedOrder(
            logicalNumber,
            key: encryptionKey,
            iv: encryptionIV
        )

        let dataWrapper: [String: Any] = [
            "data": data
        ]

        let encodedDataSec = try PronoteCodec.encodeRequestDataSec(
            dataWrapper,
            compressed: true,
            encrypted: true,
            key: encryptionKey,
            iv: encryptionIV
        )

        guard let numericSessionID = Int(session.sessionID) else {
            throw PronoteSessionError.invalidSession
        }

        let body: [String: Any] = [
            "session": numericSessionID,
            "no": encryptedNumber,
            "id": function,
            "dataSec": encodedDataSec
        ]

        let bodyData = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        let endpoint = try PronoteFunctionParametersClient.appelFonctionURL(
            serverURL: serverURL,
            spaceID: session.spaceID,
            sessionID: session.sessionID,
            requestNumber: encryptedNumber
        )

        let responseData = try await transport.post(
            to: endpoint,
            body: bodyData,
            additionalHeaders: [:]
        )

        guard let response = try JSONSerialization.jsonObject(
            with: responseData
        ) as? [String: Any] else {
            throw PronoteSessionError.invalidResponse
        }

        guard let responseOrder = response["no"] as? String else {
            throw PronoteSessionError.invalidResponseOrder
        }

        let decodedOrder = try PronoteCrypto.data(
            fromHex: responseOrder
        )

        let plainOrder = try PronoteCrypto.aesCBCDecrypt(
            decodedOrder,
            key: encryptionKey,
            iv: encryptionIV
        )

        guard
            let responseNumberString = String(
                data: plainOrder,
                encoding: .utf8
            ),
            let responseNumber = Int(responseNumberString),
            responseNumber == logicalNumber + 1
        else {
            throw PronoteSessionError.invalidResponseOrder
        }

        guard let responseDataSec = response["dataSec"] else {
            throw PronoteSessionError.missingDataSec
        }

        guard let responseHex = responseDataSec as? String else {
            throw PronoteSessionError.unsupportedDataSec
        }

        let decoded = try PronoteCodec.decodeResponseDataSec(
            responseHex,
            compressed: true,
            encrypted: true,
            key: encryptionKey,
            iv: encryptionIV
        )

        requestNumber += 2

        return decoded
    }

    // MARK: - Crypto

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
}