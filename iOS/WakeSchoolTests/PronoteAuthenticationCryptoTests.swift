import XCTest
@testable import WakeSchool

final class PronoteAuthenticationCryptoTests: XCTestCase {
    func testLoginKeyDerivationMatchesPawnoteVectors() throws {
        for vector in PronoteCryptoFixtures.logins {
            let temporaryIV = try PronoteCrypto.data(fromHex: vector.ivTempHex)
            let keys = PronoteCrypto.deriveLoginKeys(
                username: vector.username,
                password: vector.password,
                alea: vector.alea,
                ivTemp: temporaryIV,
                isENT: vector.ent
            )

            XCTAssertEqual(
                keys.sha256UpperHex,
                vector.sha256UpperHex,
                vector.name
            )
            XCTAssertEqual(
                PronoteCrypto.hexString(from: keys.authKey),
                vector.authKeyHex,
                vector.name
            )
            XCTAssertEqual(
                PronoteCrypto.hexString(from: keys.iv),
                vector.ivHex,
                vector.name
            )

            let challengeCipher = try PronoteCrypto.data(
                fromHex: vector.challengeCipherHex
            )
            let challengePlain = try PronoteCrypto.aesCBCDecrypt(
                challengeCipher,
                key: keys.authKey,
                iv: keys.iv
            )
            XCTAssertEqual(
                String(data: challengePlain, encoding: .utf8),
                vector.challenge,
                vector.name
            )
        }
    }

    func testBinaryStringEncodingMatchesNodeForgeRawStrings() {
        XCTAssertEqual(
            PronoteCrypto.binaryStringData("élève"),
            Data([0xE9, 0x6C, 0xE8, 0x76, 0x65])
        )
    }
}
