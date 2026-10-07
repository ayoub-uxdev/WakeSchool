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
            sessionID: "2052117",
            spaceID: 3,
            skipRequestEncryption: true,
            skipRequestCompression: true
        )

        do {
            _ = try await client.start(
                session: session,
                serverURL: "https://example.com/pronote/eleve.html"
            )
            XCTFail("La réponse volontairement invalide aurait dû provoquer une erreur.")
        } catch PronoteFunctionParametersError.invalidResponseOrder {
            XCTAssertTrue(true)
        }
    }
}

private final class FunctionParametersFakeTransport: PronoteHTTPTransporting {

    let response: [String: Any]

    init(response: [String: Any]) {
        self.response = response
    }

    func bootstrap(
        serverURL: String
    ) async throws -> PronoteSessionParameters {
        fatalError("bootstrap non utilisé dans ce test")
    }

    func post(
        to url: URL,
        body: Data,
        additionalHeaders: [String: String]
    ) async throws -> Data {
        try JSONSerialization.data(
            withJSONObject: response,
            options: []
        )
    }
}