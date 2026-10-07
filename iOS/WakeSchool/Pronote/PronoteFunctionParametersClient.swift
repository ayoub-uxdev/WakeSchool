import Foundation
import Security

struct PronoteInitialSession {
    let sessionID: String
    let spaceID: Int
    let requestNumber: Int
    let temporaryIV: Data
    let sessionIV: Data
    let requestsAreEncrypted: Bool
    let requestsAreCompressed: Bool
    let parameters: Any?
}

enum PronoteFunctionParametersError: Error, LocalizedError, Equatable {
    case invalidSession
    case invalidIV
    case invalidResponse
    case unexpectedResponseNumber(Int)
    case missingData
    var errorDescription: String? {
        switch self {
        case .invalidSession: return "Session PRONOTE invalide."
        case .invalidIV: return "IV PRONOTE invalide."
        case .invalidResponse: return "Réponse FonctionParametres invalide."
        case .unexpectedResponseNumber(let n): return "Numéro d'ordre PRONOTE inattendu : \(n)."
        case .missingData: return "Les paramètres PRONOTE sont absents."
        }
    }
}

struct PronoteFunctionParametersClient {
    let transport: PronoteHTTPTransporting

    func start(session: PronoteSessionParameters, clientIdentifier: String? = nil, temporaryIV: Data = Self.randomIV()) async throws -> PronoteInitialSession {
        guard !session.sessionID.isEmpty, session.spaceID >= 0, temporaryIV.count == 16 else {
            throw PronoteFunctionParametersError.invalidSession
        }

        let defaultKey = PronoteCrypto.md5(Data())
        let defaultIV = Data(repeating: 0, count: 16)
        let encryptedOrder = try PronoteCrypto.aesCBCEncrypt(Data("1".utf8), key: defaultKey, iv: defaultIV)
        let order = PronoteCodec.hex(encryptedOrder)
        let endpoint = PronoteHTTPTransport.appelfonctionURL(rootURL: session.rootURL, spaceID: session.spaceID, sessionID: session.sessionID, order: order)

        let uuid: String
        if session.usesHTTPRSA {
            let modulus = try PronoteCrypto.data(fromHex: Self.rsaModulusHex)
            let encryptedIV = try PronoteCrypto.rsaEncryptPKCS1v15(temporaryIV, modulus: modulus, exponent: 65537)
            uuid = encryptedIV.base64EncodedString()
        } else {
            uuid = temporaryIV.base64EncodedString()
        }

        var data: [String: Any] = ["Uuid": uuid]
        data["identifiantNav"] = clientIdentifier ?? NSNull()
        let dataObject: [String: Any] = ["data": data]

        let dataSec = try PronoteCodec.encodeRequestDataSec(
            dataObject,
            compressed: session.requestsAreCompressed,
            encrypted: session.requestsAreEncrypted,
            key: defaultKey,
            iv: defaultIV
        )

        let body: [String: Any] = [
            "session": Int(session.sessionID) ?? 0,
            "no": order,
            "id": "FonctionParametres",
            "dataSec": Self.dataSecJSON(dataSec)
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        let responseData = try await transport.post(to: endpoint, body: bodyData, additionalHeaders: [:])
        guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw PronoteFunctionParametersError.invalidResponse
        }

        let sessionIV = PronoteCrypto.md5(temporaryIV)
        guard let responseOrder = response["no"] as? String ?? response["numeroOrdre"] as? String else {
            throw PronoteFunctionParametersError.invalidResponse
        }
        let responseNumber = try decryptOrder(responseOrder, key: defaultKey, iv: sessionIV)
        guard responseNumber == 2 else { throw PronoteFunctionParametersError.unexpectedResponseNumber(responseNumber) }

        var parameters: Any?
        if let dataSec = response["dataSec"] as? String {
            parameters = try? PronoteCodec.decodeResponseDataSec(dataSec, compressed: session.requestsAreCompressed, encrypted: session.requestsAreEncrypted, key: defaultKey, iv: sessionIV)
        } else if let object = response["dataSec"] as? [String: Any] {
            parameters = object
        } else {
            parameters = nil
        }

        return PronoteInitialSession(
            sessionID: session.sessionID,
            spaceID: session.spaceID,
            requestNumber: 3,
            temporaryIV: temporaryIV,
            sessionIV: sessionIV,
            requestsAreEncrypted: session.requestsAreEncrypted,
            requestsAreCompressed: session.requestsAreCompressed,
            parameters: parameters
        )
    }

    private func decryptOrder(_ hex: String, key: Data, iv: Data) throws -> Int {
        let encrypted = try PronoteCrypto.data(fromHex: hex)
        let plain = try PronoteCrypto.aesCBCDecrypt(encrypted, key: key, iv: iv)
        guard let text = String(data: plain, encoding: .utf8), let value = Int(text) else {
            throw PronoteFunctionParametersError.invalidResponse
        }
        return value
    }

    private static func dataSecJSON(_ value: PronoteDataSec) -> Any {
        switch value {
        case .jsonObject(let object): return object
        case .encodedHex(let hex): return hex
        }
    }

    private static func randomIV() -> Data {
        var data = Data(repeating: 0, count: 16)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return data
    }

    private static let rsaModulusHex = "b99b77a3d72d3a29b4271fc7b7300e2f791eb8948174be7b8024667e915446d4eea0c2424b8d1ebf7e2ddff94691c6e994e839225c627d140a8f1146d1b0b5f18a09bbd3d8f421ca1e3e4796b301eebccf80d81a32a1580121b8294433c38377083c5517d5921e8a078cdc019b15775292efda2c30251b1ccabe812386c893e5"
}
