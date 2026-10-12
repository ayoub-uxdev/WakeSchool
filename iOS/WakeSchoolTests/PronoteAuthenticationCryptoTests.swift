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

    func testPlainChallengeEncryptionMatchesPronotepyVector() throws {
        let vector = try XCTUnwrap(
            PronoteCryptoFixtures.logins.first { $0.name == "standard" }
        )
        let ivTemp = try PronoteCrypto.data(fromHex: vector.ivTempHex)
        let keys = PronoteCrypto.deriveLoginKeys(
            username: vector.username,
            password: vector.password,
            alea: vector.alea,
            ivTemp: ivTemp,
            isENT: false
        )
        let encryptedChallenge = try PronoteCrypto.aesCBCEncrypt(
            Data(vector.challenge.utf8),
            key: keys.authKey,
            iv: keys.iv
        )

        XCTAssertEqual(
            PronoteCrypto.hexString(from: encryptedChallenge),
            vector.challengeCipherHex
        )
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

    func testMobileTokenUsesStandardPronoteLoginKeyDerivation() throws {
        let username = "student"
        let token = "mobile-token"
        let alea = "synthetic-alea"
        let temporaryIV = Data((0...15).map { UInt8($0) })
        let sessionIV = PronoteCrypto.md5(temporaryIV)
        let key = PronoteCrypto.deriveLoginKeys(
            username: username,
            password: token,
            alea: alea,
            ivTemp: temporaryIV,
            isENT: false
        ).authKey
        let ciphertext = try PronoteCrypto.aesCBCEncrypt(
            Data("mobile challenge".utf8),
            key: key,
            iv: sessionIV
        )

        XCTAssertEqual(
            PronoteCrypto.hexString(from: ciphertext),
            "a1b3b8dd94947c5cddadc3f151bce0bc408bce30a645e7f4c0886b595789796a"
        )
    }

    func testBinaryStringEncodingMatchesNodeForgeRawStrings() {
        XCTAssertEqual(
            PronoteCrypto.binaryStringData("élève"),
            Data([0xE9, 0x6C, 0xE8, 0x76, 0x65])
        )
    }
}
