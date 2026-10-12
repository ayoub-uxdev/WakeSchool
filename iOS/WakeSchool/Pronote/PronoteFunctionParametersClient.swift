import Foundation

struct PronoteInitialSession {
    let sessionID: String
    let spaceID: Int
    let requestNumber: Int
    let temporaryIV: Data
    let sessionIV: Data
    let requestsAreEncrypted: Bool
    let requestsAreCompressed: Bool
    let schoolYearStart: Date?
    let schoolPeriods: [[String: Any]]
    let schoolDayEndTimes: [[String: Any]]
    let functionOptionsErrorCode: String?

    init(
        sessionID: String,
        spaceID: Int,
        requestNumber: Int,
        temporaryIV: Data,
        sessionIV: Data,
        requestsAreEncrypted: Bool,
        requestsAreCompressed: Bool,
        schoolYearStart: Date? = nil,
        schoolPeriods: [[String: Any]] = [],
        schoolDayEndTimes: [[String: Any]] = [],
        functionOptionsErrorCode: String? = nil
    ) {
        self.sessionID = sessionID
        self.spaceID = spaceID
        self.requestNumber = requestNumber
        self.temporaryIV = temporaryIV
        self.sessionIV = sessionIV
        self.requestsAreEncrypted = requestsAreEncrypted
        self.requestsAreCompressed = requestsAreCompressed
        self.schoolYearStart = schoolYearStart
        self.schoolPeriods = schoolPeriods
        self.schoolDayEndTimes = schoolDayEndTimes
        self.functionOptionsErrorCode = functionOptionsErrorCode
    }
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

        let uuidData: Data
        if session.rsaFromConstants && !session.usesHTTPRSA {
            uuidData = temporaryIV
        } else {
            uuidData = try PronoteCrypto.rsaEncryptPKCS1v15(
                temporaryIV,
                modulus: session.rsaModulus,
                exponent: session.rsaExponent
            )
        }

        var data: [String: Any] = [
            "Uuid": uuidData.base64EncodedString()
        ]
        if let clientIdentifier {
            data["identifiantNav"] = clientIdentifier
        } else {
            data["identifiantNav"] = NSNull()
        }

        let payload: [String: Any] = [
            "data": data,
            "donnees": data
        ]
        let initialRequestIV = Data(repeating: 0, count: 16)
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let encodedPayload = try PronoteCodec.encodeDataSec(
            payload,
            compressed: session.requestsAreCompressed,
            encrypted: session.requestsAreEncrypted,
            key: PronoteCrypto.md5(Data()),
            iv: initialRequestIV
        )

        let properties = PronoteAPIProperties.forVersion(session.version)
        var body: [String: Any] = [
            "session": Int(session.sessionID) ?? 0,
            properties.orderNumber: initialOrder,
            properties.requestID: "FonctionParametres",
            properties.secureData: Self.dataSecJSON(encodedPayload)
        ]
        if !session.version.lexicographicallyPrecedes([2025, 1, 3]) {
            body["nom"] = "FonctionParametres"
        }
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])
        let endpoint = PronoteHTTPTransport.appelfonctionURL(
            rootURL: session.rootURL,
            spaceID: session.spaceID,
            sessionID: session.sessionID,
            order: initialOrder
        )
        let responseData = try await transport.post(
            to: endpoint,
            body: bodyData,
            additionalHeaders: [:]
        )

        guard let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw PronoteFunctionParametersError.invalidResponse
        }

        guard let responseNumber = response[properties.orderNumber] as? String
                ?? response["no"] as? String
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

        guard let secureData = response[properties.secureData]
            ?? response["dataSec"]
            ?? response["donneesSec"] else {
            throw PronoteFunctionParametersError.missingData
        }

        let functionData: [String: Any]
        var functionOptionsErrorCode: String?
        if let object = secureData as? [String: Any] {
            functionData = object
        } else if let encoded = secureData as? String {
            do {
                let decoded = try PronoteCodec.decodeDataSec(
                    encoded,
                    compressed: session.requestsAreCompressed,
                    encrypted: session.requestsAreEncrypted,
                    key: PronoteCrypto.md5(Data()),
                    iv: sessionIV
                )
                if let object = decoded as? [String: Any] {
                    functionData = object
                } else {
                    functionData = [:]
                    functionOptionsErrorCode = "FUNCTION_OPTIONS_NOT_OBJECT"
                }
            } catch {
                functionData = [:]
                functionOptionsErrorCode = Self.functionOptionsDecodeErrorCode(for: error)
            }
        } else {
            functionData = [:]
            functionOptionsErrorCode = "FUNCTION_OPTIONS_INVALID_FORMAT"
        }
        let data = functionData["data"] as? [String: Any]
            ?? functionData["donnees"] as? [String: Any]
            ?? functionData
        let schoolYearStart = PronoteMapper.schoolYearStart(from: data)
        let schoolPeriods = PronoteMapper.periods(from: functionData)
        let schoolDayEndTimes = Self.listValue(in: data, key: "ListeHeuresFin")

        return PronoteInitialSession(
            sessionID: session.sessionID,
            spaceID: session.spaceID,
            requestNumber: 3,
            temporaryIV: temporaryIV,
            sessionIV: sessionIV,
            requestsAreEncrypted: session.requestsAreEncrypted,
            requestsAreCompressed: session.requestsAreCompressed,
            schoolYearStart: schoolYearStart,
            schoolPeriods: schoolPeriods,
            schoolDayEndTimes: schoolDayEndTimes,
            functionOptionsErrorCode: functionOptionsErrorCode
        )
    }

    private static func listValue(in data: [String: Any], key: String) -> [[String: Any]] {
        guard let general = data["General"] as? [String: Any]
                ?? data["general"] as? [String: Any],
              let value = general[key] as? [String: Any] else {
            return []
        }
        return value["V"] as? [[String: Any]] ?? []
    }

    private static func functionOptionsDecodeErrorCode(for error: Error) -> String {
        if let error = error as? PronoteCodecError {
            switch error {
            case .invalidJSON:
                return "FUNCTION_OPTIONS_INVALID_JSON"
            case .compressionFailed:
                return "FUNCTION_OPTIONS_COMPRESSION_FAILED"
            case .decompressionFailed:
                return "FUNCTION_OPTIONS_DECOMPRESSION_FAILED"
            case .invalidHex:
                return "FUNCTION_OPTIONS_INVALID_HEX"
            }
        }
        if let error = error as? PronoteCryptoError {
            switch error {
            case .invalidHex:
                return "FUNCTION_OPTIONS_INVALID_HEX"
            default:
                return "FUNCTION_OPTIONS_DECODE_FAILED"
            }
        }
        return "FUNCTION_OPTIONS_DECODE_FAILED"
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

    private static func dataSecJSON(_ value: PronoteDataSec) -> Any {
        switch value {
        case .jsonObject(let object):
            return object
        case .encodedHex(let hex):
            return hex
        }
    }
}