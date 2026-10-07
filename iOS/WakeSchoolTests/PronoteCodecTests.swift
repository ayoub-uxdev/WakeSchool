import XCTest
@testable import WakeSchool

final class PronoteCodecCorrectedTests: XCTestCase {
    private let sampleJSON: [String: Any] = [
        "_Signature_": ["onglet": 7],
        "donnees": ["N": "abc", "Actif": true]
    ]

    func testRequestCompressionMatchesCurrentPronotepyVector() throws {
        let result = try PronoteCodec.encodeRequestDataSec(
            sampleJSON,
            compressed: true,
            encrypted: false,
            key: Data(repeating: 0, count: 32),
            iv: Data(repeating: 0, count: 16)
        )
        guard case .encodedHex(let hex) = result else { return XCTFail("expected hex") }
        XCTAssertEqual(hex, "358DC10DC0300803678A015B1DA76D92FD47A889D41FBA3B0B3D40ED0A5E1417875225B06A0371CB96DB5C7C59CA66214DBCE679CC62D9C45FE7EACB761034ED320743E90F3C550AEACDD4FC00")
    }

    func testResponseCompressionDecodesRawJSON() throws {
        let hex = "AB568A0FCE4CCF4B2C292D4A8D57B2AA56CACF4BCF492D51B232AFD5514AC9CFCB4B4D2D0609FB2959292526252BE92839269764A62959951495A6D6D60200"
        let value = try PronoteCodec.decodeResponseDataSec(
            hex,
            compressed: true,
            encrypted: false,
            key: Data(repeating: 0, count: 32),
            iv: Data(repeating: 0, count: 16)
        ) as? [String: Any]
        let signature = value?["_Signature_"] as? [String: Any]
        XCTAssertEqual(signature?["onglet"] as? Int, 7)
    }
}
