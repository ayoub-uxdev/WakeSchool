import XCTest
@testable import WakeSchool

final class PronoteFunctionParametersClientTests: XCTestCase {

    func testInitialRequestNumberMatchesPronoteProtocol() throws {
        let key = PronoteCrypto.aesKey(fromSeed: nil)
        let iv = Data(repeating: 0, count: 16)

        let encrypted = try PronoteCrypto.aesCBCEncrypt(
            Data("1".utf8),
            key: key,
            iv: iv
        )

        let hex = PronoteCrypto.hexString(
            from: encrypted,
            uppercase: false
        )

        XCTAssertEqual(
            hex,
            "3fa959b13967e0ef176069e01e23c8d7"
        )
    }

    func testInitialSessionUsesRequestNumberThreeAfterFunctionParameters() async throws {
        let transport = FunctionParametersFakeTransport(
            response: [
                "no": "INVALID"
            ]
        )

        let client = PronoteFunctionParametersClient(
            transport: transport
        )

        let session = PronoteSessionParameters(
            rootURL: URL(string: "https://example.com/pronote/")!,
            sessionID: "2052117",
            spaceID: 3,
            skipRequestEncryption: true,
            skipRequestCompression: true
        )

        do {
            _ = try await client.start(
                session: session,
                temporaryIV: Data(repeating: 1, count: 16)
            )
            XCTFail("La réponse volontairement invalide aurait dû provoquer une erreur.")
        } catch PronoteCryptoError.invalidHex {
            XCTAssertTrue(true)
        }
    }

    func testInitialFunctionParametersPayloadUsesZeroIV() async throws {
        let key = PronoteCrypto.md5(Data())
        let zeroIV = Data(repeating: 0, count: 16)
        let temporaryIV = Data(repeating: 0xA5, count: 16)
        let responseOrder = try PronoteCrypto.aesCBCEncrypt(
            Data("2".utf8),
            key: key,
            iv: PronoteCrypto.md5(temporaryIV)
        )
        let functionOptions: [String: Any] = [
            "data": [
                "General": [
                    "PremierLundi": ["V": "07/09/2026"],
                    "ListePeriodes": [
                        ["N": "period-1", "L": "Période 1"]
                    ],
                    "ListeHeuresFin": [
                        "V": [
                            ["G": 0, "L": "08h00"],
                            ["G": 1, "L": "09h00"]
                        ]
                    ]
                ]
            ]
        ]
        let encodedFunctionOptions = try PronoteCodec.encodeDataSec(
            functionOptions,
            compressed: true,
            encrypted: true,
            key: key,
            iv: PronoteCrypto.md5(temporaryIV)
        )
        guard case .encodedHex(let functionOptionsHex) = encodedFunctionOptions else {
            return XCTFail("Les paramètres FonctionParametres auraient dû être encodés.")
        }
        let transport = FunctionParametersFakeTransport(
            response: [
                "no": PronoteCodec.hex(responseOrder),
                "dataSec": functionOptionsHex
            ]
        )
        let session = PronoteSessionParameters(
            rootURL: URL(string: "https://example.com/pronote/")!,
            sessionID: "2052117",
            spaceID: 3,
            skipRequestEncryption: false,
            skipRequestCompression: false
        )
        let client = PronoteFunctionParametersClient(transport: transport)

        let initial = try await client.start(
            session: session,
            clientIdentifier: "device-id",
            temporaryIV: temporaryIV
        )
        XCTAssertEqual(initial.schoolPeriods.count, 1)
        XCTAssertEqual(initial.schoolPeriods.first?["N"] as? String, "period-1")
        XCTAssertEqual(initial.schoolDayEndTimes.count, 2)
        XCTAssertEqual(
            Calendar.current.component(.day, from: try XCTUnwrap(initial.schoolYearStart)),
            7
        )

        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(transport.requestBody))
                as? [String: Any]
        )
        let encryptedPayload = try XCTUnwrap(body["dataSec"] as? String)
        let decodedPayload = try PronoteCodec.decodeDataSec(
            encryptedPayload,
            compressed: true,
            encrypted: true,
            key: key,
            iv: zeroIV
        ) as? [String: Any]

        let requestData = try XCTUnwrap(decodedPayload?["data"] as? [String: Any])
        XCTAssertEqual(
            requestData["Uuid"] as? String,
            temporaryIV.base64EncodedString()
        )
        XCTAssertEqual(requestData["identifiantNav"] as? String, "device-id")
    }

    func testMalformedFunctionOptionsAreRecordedWithoutStoppingSessionSetup() async throws {
        let temporaryIV = Data(repeating: 0xA7, count: 16)
        let responseOrder = try PronoteCrypto.aesCBCEncrypt(
            Data("2".utf8),
            key: PronoteCrypto.md5(Data()),
            iv: PronoteCrypto.md5(temporaryIV)
        )
        let transport = FunctionParametersFakeTransport(
            response: [
                "no": PronoteCodec.hex(responseOrder),
                "dataSec": "invalid"
            ]
        )
        let session = PronoteSessionParameters(
            rootURL: URL(string: "https://example.com/pronote/")!,
            sessionID: "2052117",
            spaceID: 3,
            skipRequestEncryption: false,
            skipRequestCompression: true
        )

        let initial = try await PronoteFunctionParametersClient(transport: transport).start(
            session: session,
            temporaryIV: temporaryIV
        )

        XCTAssertNil(initial.schoolYearStart)
        XCTAssertTrue(initial.schoolPeriods.isEmpty)
        XCTAssertEqual(initial.functionOptionsErrorCode, "FUNCTION_OPTIONS_INVALID_HEX")
    }
}

private final class FunctionParametersFakeTransport: PronoteHTTPTransporting {

    let response: [String: Any]
    private(set) var requestBody: Data?

    init(response: [String: Any]) {
        self.response = response
    }

    func bootstrap(
        serverURL: String,
        accountKind: PronoteAccountKind
    ) async throws -> PronoteSessionParameters {
        fatalError("bootstrap non utilisé dans ce test")
    }

    func post(
        to url: URL,
        body: Data,
        additionalHeaders: [String: String]
    ) async throws -> Data {
        requestBody = body
        return try JSONSerialization.data(
            withJSONObject: response,
            options: []
        )
    }
}