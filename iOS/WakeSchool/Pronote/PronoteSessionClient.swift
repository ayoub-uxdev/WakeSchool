import Foundation

final class PronoteSessionClient {
    private let transport: PronoteHTTPTransporting
    private let session: PronoteAuthenticationResult
    private var requestNumber: Int
    private var key: Data

    init(transport: PronoteHTTPTransporting, session: PronoteAuthenticationResult) {
        self.transport = transport
        self.session = session
        self.requestNumber = session.requestNumber
        self.key = session.sessionKey
    }

    var userName: String? { session.userName }
    var mobileToken: String? { session.mobileToken }
    var rootURL: URL { session.rootURL }

    func request(function: String, data: [String: Any] = [:]) async throws -> Any {
        let logicalNumber = requestNumber
        let encryptedOrder = try PronoteCrypto.aesCBCEncrypt(Data(String(logicalNumber).utf8), key: key, iv: session.sessionIV)
        let order = PronoteCodec.hex(encryptedOrder)
        let dataSec = try PronoteCodec.encodeRequestDataSec(data, compressed: session.requestsAreCompressed, encrypted: session.requestsAreEncrypted, key: key, iv: session.sessionIV)

        let body: [String: Any] = [
            "session": Int(session.sessionID) ?? 0,
            "no": order,
            "id": function,
            "dataSec": Self.dataSecJSON(dataSec)
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        let endpoint = PronoteHTTPTransport.appelfonctionURL(rootURL: session.rootURL, spaceID: session.spaceID, sessionID: session.sessionID, order: order)
        let responseData = try await transport.post(to: endpoint, body: bodyData, additionalHeaders: [:])
        guard var response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw PronoteSessionError.invalidResponse
        }

        if let responseNo = response["no"] as? String ?? response["numeroOrdre"] as? String {
            let plain = try PronoteCrypto.aesCBCDecrypt(try PronoteCrypto.data(fromHex: responseNo), key: key, iv: session.sessionIV)
            if let text = String(data: plain, encoding: .utf8), let number = Int(text), number != logicalNumber + 1 {
                throw PronoteSessionError.unexpectedResponseNumber(number)
            }
        }

        if let error = response["Erreur"] as? [String: Any] {
            let code = Int((error["G"] as? NSNumber)?.intValue ?? Int(error["G"] as? String ?? "0") ?? 0)
            throw PronoteSessionError.pronoteError(code, error["Titre"] as? String ?? "Erreur inconnue")
        }

        if let responseDataSec = response["dataSec"] as? String {
            response["dataSec"] = try PronoteCodec.decodeResponseDataSec(responseDataSec, compressed: session.requestsAreCompressed, encrypted: session.requestsAreEncrypted, key: key, iv: session.sessionIV)
        }
        requestNumber += 2
        return response
    }

    func userParameters() async throws -> Any {
        try await request(function: "ParametresUtilisateur", data: [:])
    }

    func timetable(weekNumber: Int, resource: [String: Any]) async throws -> Any {
        let payload: [String: Any] = [
            "data": [
                "ressource": resource,
                "Ressource": resource,
                "numeroSemaine": weekNumber,
                "NumeroSemaine": weekNumber,
                "avecAbsencesEleve": false,
                "avecConseilDeClasse": true,
                "estEDTPermanence": false,
                "avecAbsencesRessource": true,
                "avecDisponibilites": true,
                "avecInfosPrefsGrille": true
            ],
            "_Signature_": ["onglet": 16]
        ]
        return try await request(function: "PageEmploiDuTemps", data: payload)
    }

    func homework(from start: Date, to end: Date, resource: [String: Any]) async throws -> Any {
        let payload: [String: Any] = [
            "data": [
                "ressource": resource,
                "Ressource": resource,
                "dateDebut": Self.dayString(start),
                "dateFin": Self.dayString(end),
                "avecRessource": true
            ],
            "_Signature_": ["onglet": 20]
        ]
        return try await request(function: "PageCahierDeTexte", data: payload)
    }

    func grades(period: [String: Any]) async throws -> Any {
        let payload: [String: Any] = [
            "data": ["periode": period],
            "_Signature_": ["onglet": 198]
        ]
        return try await request(function: "DernieresNotes", data: payload)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func dataSecJSON(_ value: PronoteDataSec) -> Any {
        switch value { case .jsonObject(let object): return object; case .encodedHex(let hex): return hex }
    }
}

enum PronoteSessionError: Error, LocalizedError, Equatable {
    case invalidResponse
    case unexpectedResponseNumber(Int)
    case pronoteError(Int, String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Réponse PRONOTE invalide."
        case .unexpectedResponseNumber(let number): return "Numéro d'ordre PRONOTE inattendu : \(number)."
        case .pronoteError(let code, let message): return "Erreur PRONOTE \(code) : \(message)"
        }
    }
}
