import XCTest
@testable import WakeSchool

final class PronoteFunctionParametersTests: XCTestCase {
    func testInitialOrderMatchesPronoteReferenceVector() throws {
        let key = PronoteCrypto.aesKey(fromSeed: nil)
        let iv = Data(repeating: 0, count: 16)
        let encrypted = try PronoteCrypto.aesCBCEncrypt(Data("1".utf8), key: key, iv: iv)
        XCTAssertEqual(PronoteCrypto.hexString(from: encrypted, uppercase: true), "3FA959B13967E0EF176069E01E23C8D7")
    }

    func testAppelFonctionURLUsesSessionRoot() throws {
        let rootURL = try XCTUnwrap(URL(string: "https://example.test/pronote/"))
        let url = PronoteHTTPTransport.appelfonctionURL(
            rootURL: rootURL,
            spaceID: 3,
            sessionID: "42",
            order: "ABC"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://example.test/pronote/appelfonction/3/42/ABC"
        )
    }
}
