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

        let encryptedOrder = try PronoteCrypto.aesCBCEncrypt(
            Data(String(logicalNumber).utf8),
            key: key,
            iv: session.sessionIV
        )

        let order = PronoteCodec.hex(encryptedOrder)

        let dataSec = try PronoteCodec.encodeDataSec(
            data,
            compressed: session.requestsAreCompressed,
            encrypted: session.requestsAreEncrypted,
            key: key,
            iv: session.sessionIV
        )

        let properties = PronoteAPIProperties.forVersion(
            session.version
        )
        let body: [String: Any] = [
            "session": Int(session.sessionID) ?? 0,
            properties.orderNumber: order,
            properties.requestID: function,
            properties.secureData: Self.dataSecJSON(dataSec)
        ]

        let bodyData = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

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

        guard var response = try JSONSerialization.jsonObject(
            with: responseData
        ) as? [String: Any] else {
            throw PronoteSessionError.invalidResponse
        }

        if let responseNo = response["no"] as? String
            ?? response["numeroOrdre"] as? String {

            let responseNoData = try PronoteCrypto.data(fromHex: responseNo)

            let plain = try PronoteCrypto.aesCBCDecrypt(
                responseNoData,
                key: key,
                iv: session.sessionIV
            )

            if let text = String(data: plain, encoding: .utf8),
               let number = Int(text),
               number != logicalNumber + 1 {
                throw PronoteSessionError.unexpectedResponseNumber(number)
            }
        }

        if let error = response["Erreur"] as? [String: Any] {
            let code: Int

            if let value = error["G"] as? NSNumber {
                code = value.intValue
            } else if let value = error["G"] as? String {
                code = Int(value) ?? 0
            } else {
                code = 0
            }

            let message = error["Titre"] as? String ?? "Erreur inconnue"

            throw PronoteSessionError.pronoteError(
                code,
                message
            )
        }

        if let responseDataSec = response[properties.secureData] as? String {
            response[properties.secureData] = try PronoteCodec.decodeDataSec(
                responseDataSec,
                compressed: session.requestsAreCompressed,
                encrypted: session.requestsAreEncrypted,
                key: key,
                iv: session.sessionIV
            )
        } else if properties.secureData != "dataSec",
                  let responseDataSec = response["dataSec"] as? String {
            response["dataSec"] = try PronoteCodec.decodeDataSec(
                responseDataSec,
                compressed: session.requestsAreCompressed,
                encrypted: session.requestsAreEncrypted,
                key: key,
                iv: session.sessionIV
            )
        }

        requestNumber += 2

        return response
    }

    func userParameters() async throws -> Any {
        try await request(
            function: "ParametresUtilisateur",
            data: [:]
        )
    }

    func timetable(
        weekNumber: Int,
        resource: [String: Any]
    ) async throws -> Any {
        let signature = try Self.signature(onglet: 16, resource: resource)

        let properties = PronoteAPIProperties.forVersion(session.version)
        let payload: [String: Any] = [
            properties.data: [
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
            Self.signatureKey(for: session.version): signature
        ]

        return try await request(
            function: "PageEmploiDuTemps",
            data: payload
        )
    }

    func homework(
        resource: [String: Any],
        weekRange: ClosedRange<Int>
    ) async throws -> Any {
        let signature = try Self.signature(onglet: 88, resource: resource)

        let properties = PronoteAPIProperties.forVersion(session.version)
        let payload: [String: Any] = [
            properties.data: [
                "domaine": [
                    "_T": 8,
                    "V": "[\(weekRange.lowerBound)..\(weekRange.upperBound)]"
                ]
            ],
            Self.signatureKey(for: session.version): signature
        ]

        return try await request(
            function: "PageCahierDeTexte",
            data: payload
        )
    }

    func grades(
        period: [String: Any],
        resource: [String: Any]
    ) async throws -> Any {
        let signature = try Self.signature(onglet: 198, resource: resource)
        guard let periodID = period["N"],
              let periodName = period["L"] else {
            throw PronoteSessionError.invalidPeriod
        }
        let properties = PronoteAPIProperties.forVersion(session.version)
        let payload: [String: Any] = [
            properties.data: [
                "Periode": [
                    "N": periodID,
                    "L": periodName
                ]
            ],
            Self.signatureKey(for: session.version): signature
        ]

        return try await request(
            function: "DernieresNotes",
            data: payload
        )
    }

    private static func signature(
        onglet: Int,
        resource: [String: Any]
    ) throws -> [String: Any] {
        guard let resourceID = resource["N"] else {
            throw PronoteSessionError.missingStudentResource
        }
        return [
            "onglet": onglet,
            "membre": [
                "N": resourceID,
                "G": 4
            ]
        ]
    }

    private static func signatureKey(for version: [Int]) -> String {
        version.lexicographicallyPrecedes([2024, 3, 9])
            ? "_Signature_"
            : "Signature"
    }

    private static func dataSecJSON(
        _ value: PronoteDataSec
    ) -> Any {
        switch value {
        case .jsonObject(let object):
            return object

        case .encodedHex(let hex):
            return hex
        }
    }
}

enum PronoteSessionError: Error, LocalizedError, Equatable {
    case invalidResponse
    case missingStudentResource
    case invalidPeriod
    case unexpectedResponseNumber(Int)
    case pronoteError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Réponse PRONOTE invalide."

        case .missingStudentResource:
            return "La ressource élève PRONOTE ne contient pas d'identifiant."

        case .invalidPeriod:
            return "La période scolaire PRONOTE ne contient pas d'identifiant ou de libellé."

        case .unexpectedResponseNumber(let number):
            return "Numéro d'ordre PRONOTE inattendu : \(number)"

        case .pronoteError(let code, let message):
            return "Erreur PRONOTE \(code) : \(message)"
        }
    }
}