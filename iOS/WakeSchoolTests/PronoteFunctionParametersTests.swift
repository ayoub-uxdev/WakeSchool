import XCTest
@testable import WakeSchool

final class PronoteFunctionParametersTests: XCTestCase {

    func testInitialOrderMatchesPronoteReferenceVector() throws {
        let key = PronoteCrypto.md5(Data())
        let iv = Data(repeating: 0, count: 16)

        let encrypted = try PronoteCrypto.aesCBCEncrypt(
            Data("1".utf8),
            key: key,
            iv: iv
        )

        XCTAssertEqual(
            PronoteCodec.hex(encrypted).lowercased(),
            "3fa959b13967e0ef176069e01e23c8d7"
        )
    }

    func testSessionIVIsMD5OfTemporaryIV() {
        let temporaryIV = Data((0..<16).map(UInt8.init))
        let sessionIV = PronoteCrypto.md5(temporaryIV)

        XCTAssertEqual(
            PronoteCodec.hex(sessionIV).lowercased(),
            "1e1f0f0f3f8f2f3d8e5c5d8d7b7f5f8d"
        )
    }
}
