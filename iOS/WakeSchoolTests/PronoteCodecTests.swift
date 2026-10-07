import XCTest
@testable import WakeSchool

final class PronoteCodecTests: XCTestCase {

    private let knownJSON = "{\"_Signature_\":{\"onglet\":7},\"donnees\":{\"N\":\"abc\",\"Actif\":true}}"

    // zlib level 6, windowBits=-15, generated from the exact JSON above.
    private let knownRawDeflateHex = "AB568A0FCE4CCF4B2C292D4A8D57B2AA56CACF4BCF492D51B232AFD5514AC9CFCB4B4D2D0609FB2959292526252BE92839269764A62959951495A6D6D60200"

    func testRawDeflateCanBeInflatedFromPronoteCompatibleFixture() throws {
        let compressed = try PronoteCodec.data(fromHex: knownRawDeflateHex)
        let plain = try PronoteCodec.inflate(compressed)
        XCTAssertEqual(String(data: plain, encoding: .utf8), knownJSON)
    }

    func testDeflateRoundTrip() throws {
        let input = Data(knownJSON.utf8)
        let compressed = try PronoteCodec.deflate(input)
        XCTAssertFalse(compressed.isEmpty)
        XCTAssertEqual(try PronoteCodec.inflate(compressed), input)
    }

    func testEncodeDecodeCompressedOnly() throws {
        let object: [String: Any] = [
            "_Signature_": ["onglet": 7],
            "donnees": ["N": "abc", "Actif": true]
        ]

        let encoded = try PronoteCodec.encodeDataSec(
            object,
            compressed: true,
            encrypted: false,
            key: Data(repeating: 0, count: 16),
            iv: Data(repeating: 0, count: 16)
        )

        guard case .encodedHex(let hex) = encoded else {
            return XCTFail("dataSec compressé doit être une chaîne hexadécimale")
        }

        let decoded = try PronoteCodec.decodeDataSec(
            hex,
            compressed: true,
            encrypted: false,
            key: Data(repeating: 0, count: 16),
            iv: Data(repeating: 0, count: 16)
        )

        let decodedJSON = try JSONSerialization.data(withJSONObject: decoded, options: [.sortedKeys])
        let expectedJSON = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertEqual(decodedJSON, expectedJSON)
    }

    func testEncodeDecodeEncryptedAndCompressed() throws {
        let object: [String: Any] = [
            "_Signature_": ["onglet": 16],
            "donnees": ["message": "WakeSchool", "number": 42]
        ]
        let key = PronoteCrypto.md5(Data("codec-test".utf8))
        let iv = PronoteCrypto.md5(Data("iv-test".utf8))

        let encoded = try PronoteCodec.encodeDataSec(
            object,
            compressed: true,
            encrypted: true,
            key: key,
            iv: iv
        )

        guard case .encodedHex(let hex) = encoded else {
            return XCTFail("dataSec chiffré doit être une chaîne hexadécimale")
        }
        XCTAssertFalse(hex.isEmpty)
        XCTAssertEqual(hex, hex.uppercased())

        let decoded = try PronoteCodec.decodeDataSec(
            hex,
            compressed: true,
            encrypted: true,
            key: key,
            iv: iv
        )

        let decodedJSON = try JSONSerialization.data(withJSONObject: decoded, options: [.sortedKeys])
        let expectedJSON = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertEqual(decodedJSON, expectedJSON)
    }

    func testNoTransformKeepsJSONObject() throws {
        let object: [String: Any] = ["id": "Identification", "value": 1]
        let result = try PronoteCodec.encodeDataSec(
            object,
            compressed: false,
            encrypted: false,
            key: Data(repeating: 0, count: 16),
            iv: Data(repeating: 0, count: 16)
        )

        guard case .jsonObject(let decoded) = result else {
            return XCTFail("sans transformation, dataSec doit rester un objet JSON")
        }
        let data = try JSONSerialization.data(withJSONObject: decoded, options: [.sortedKeys])
        let expected = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertEqual(data, expected)
    }

    func testInvalidHexIsRejected() {
        XCTAssertThrowsError(try PronoteCodec.data(fromHex: "ABC"))
        XCTAssertThrowsError(try PronoteCodec.data(fromHex: "GG"))
    }
}
