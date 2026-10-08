import XCTest
@testable import WakeSchool

final class PronoteCodecTests: XCTestCase {
    func testRawDeflateRoundTripsPawnoteHexEncodedJSON() throws {
        let json = Data(#"{"x":1}"#.utf8)
        let hexadecimalJSON = Data(PronoteCodec.hex(json).utf8)

        let compressed = try PronoteCodec.deflate(hexadecimalJSON)
        let decoded = try PronoteCodec.inflate(compressed)

        XCTAssertEqual(decoded, json)
    }

    func testCompressedDataSecRoundTripsJSON() throws {
        let payload: [String: Any] = [
            "donnees": ["N": "abc", "Actif": true]
        ]

        let encoded = try PronoteCodec.encodeDataSec(
            payload,
            compressed: true,
            encrypted: false,
            key: Data(repeating: 0, count: 32),
            iv: Data(repeating: 0, count: 16)
        )
        guard case .encodedHex(let hex) = encoded else {
            return XCTFail("Les données compressées doivent être encodées en hexadécimal.")
        }

        let decoded = try PronoteCodec.decodeDataSec(
            hex,
            compressed: true,
            encrypted: false,
            key: Data(repeating: 0, count: 32),
            iv: Data(repeating: 0, count: 16)
        ) as? [String: Any]

        let nested = decoded?["donnees"] as? [String: Any]
        XCTAssertEqual(nested?["N"] as? String, "abc")
        XCTAssertEqual(nested?["Actif"] as? Bool, true)
    }
}
