import XCTest
@testable import WakeSchool

final class PronoteAuthenticationCryptoTests: XCTestCase {
    func testNonENTLoginKeyDerivationMatchesPawnoteVectors() throws {
        for vector in PronoteCryptoFixtures.logins where !vector.ent {
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
        }
    }

    func testENTLoginKeyDerivationMatchesPronote2026Protocol() {
        let keys = PronoteCrypto.deriveLoginKeys(
            username: "ignored-login",
            password: "ent-password",
            alea: "ent-alea",
            ivTemp: Data(repeating: 0, count: 16),
            isENT: true
        )

        XCTAssertEqual(
            keys.sha256UpperHex,
            "03E14360A5AADAC18D4C54E23DBFADFD111EAC7BBB53EA4701873951162075B5"
        )
        XCTAssertEqual(
            PronoteCrypto.hexString(from: keys.authKey),
            "ddfbc0225c1d81018990182afd9da377"
        )
    }

    func testBinaryStringEncodingMatchesNodeForgeRawStrings() {
        XCTAssertEqual(
            PronoteCrypto.binaryStringData("élève"),
            Data([0xE9, 0x6C, 0xE8, 0x76, 0x65])
        )
    }
}
