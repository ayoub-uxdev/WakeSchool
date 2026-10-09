import XCTest
@testable import WakeSchool

final class PronoteQRLoginTests: XCTestCase {
    func testQRDecryptionPreservesRawCredentialBytes() throws {
        let pin = "1234"
        let key = PronoteCrypto.md5(Data(pin.utf8))
        let iv = Data(repeating: 0, count: 16)
        let loginBytes = Data([0xE9, 0x6C, 0xE8, 0x76, 0x65])
        let tokenBytes = Data([0xC3, 0xA9, 0x31, 0x32, 0x33])
        let encryptedLogin = try PronoteCrypto.aesCBCEncrypt(
            loginBytes,
            key: key,
            iv: iv
        )
        let encryptedToken = try PronoteCrypto.aesCBCEncrypt(
            tokenBytes,
            key: key,
            iv: iv
        )
        let qr = PronoteQRCode(
            login: PronoteCrypto.hexString(from: encryptedLogin),
            jeton: PronoteCrypto.hexString(from: encryptedToken),
            url: "https://example.test/pronote/eleve.html"
        )

        let credentials = try PronoteQRLogin.decryptCredentials(
            from: qr,
            pin: pin
        )

        XCTAssertEqual(
            PronoteCrypto.binaryStringData(credentials.username),
            loginBytes
        )
        XCTAssertEqual(
            Data(credentials.password.utf8),
            tokenBytes
        )
    }
}
