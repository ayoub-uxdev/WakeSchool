import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Erreurs de la couche crypto Pronote.
enum PronoteCryptoError: Error, Equatable {
    /// Chaîne hexadécimale invalide (même sémantique que `bytes.fromhex` de Python).
    case invalidHex
    /// Liste d'octets « 1,2,3 » invalide (même sémantique que `_enBytes` de pronotepy).
    case invalidByteList
    /// Rembourrage PKCS#7 invalide.
    case invalidPadding
    case invalidKeyLength
    case invalidIVLength
    /// Équivalent du `CryptoError` de pronotepy lors d'un déchiffrement AES.
    case decryptionFailed
    case encryptionFailed
    /// Message trop long pour RSA PKCS#1 v1.5 (maximum : taille de la clé - 11 octets).
    case rsaMessageTooLong
    /// Le rembourrage aléatoire fourni est invalide (mauvaise longueur ou octet nul).
    case rsaInvalidPadding
    case rsaKeyCreationFailed
    case rsaEncryptionFailed
    case randomGenerationFailed
}

/// Primitives cryptographiques du flux de connexion Pronote, alignées sur `pronotepy` 2.15.7.
///
/// Uniquement des fonctions pures : aucune requête réseau, aucun état, aucune authentification.
/// - MD5 / SHA-256 : CryptoKit
/// - AES-128-CBC : CommonCrypto (sans rembourrage ; le PKCS#7 est géré ici)
/// - RSA : Security (RSA brut) + rembourrage PKCS#1 v1.5 construit ici, pour pouvoir
///   injecter un rembourrage déterministe dans les tests.
enum PronoteCrypto {

    static let blockSize = 16

    // MARK: - Hachages

    static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    // MARK: - Hexadécimal

    /// Équivalent de `bytes.fromhex` : les espaces ASCII sont ignorés entre deux octets
    /// (jamais à l'intérieur d'une paire), tout autre caractère est refusé.
    static func data(fromHex string: String) throws -> Data {
        let input = Array(string.utf8)
        var output = [UInt8]()
        output.reserveCapacity(input.count / 2)

        var index = 0
        var highNibble: UInt8?

        while index < input.count {
            let byte = input[index]

            if isASCIIWhitespace(byte) {
                // Python's bytes.fromhex() allows whitespace only between
                // complete byte pairs, not between the two nibbles of a byte.
                guard highNibble == nil else {
                    throw PronoteCryptoError.invalidHex
                }
                index += 1
                continue
            }

            guard let nibble = hexNibble(byte) else {
                throw PronoteCryptoError.invalidHex
            }

            if let high = highNibble {
                output.append((high << 4) | nibble)
                highNibble = nil
            } else {
                highNibble = nibble
            }

            index += 1
        }

        guard highNibble == nil else {
            throw PronoteCryptoError.invalidHex
        }

        return Data(output)
    }

    static func hexString(from data: Data, uppercase: Bool = false) -> String {
        let digits = Array((uppercase ? "0123456789ABCDEF" : "0123456789abcdef").utf8)
        var output = [UInt8]()
        output.reserveCapacity(data.count * 2)
        for byte in data {
            output.append(digits[Int(byte >> 4)])
            output.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: output, as: UTF8.self)
    }

    // MARK: - Liste d'octets « 1,2,3 »

    /// Équivalent de `_enBytes` : `bytes([int(i) for i in string.split(",")])`.
    ///
    /// Reproduit `int()` pour l'ASCII : espaces autour, signe `+`/`-`, soulignés entre deux chiffres.
    /// Valeurs hors de 0...255 refusées. Les chiffres et espaces Unicode non ASCII, acceptés par
    /// `int()` en Python, sont refusés ici (Pronote n'envoie que de l'ASCII).
    static func data(fromByteList string: String) throws -> Data {
        var output = Data()
        for part in string.components(separatedBy: ",") {
            output.append(try parseByte(part))
        }
        return output
    }

    private static func parseByte(_ text: String) throws -> UInt8 {
        var scalars = Array(text.utf8)[...]
        while let first = scalars.first, isASCIIWhitespace(first) { scalars = scalars.dropFirst() }
        while let last = scalars.last, isASCIIWhitespace(last) { scalars = scalars.dropLast() }

        var negative = false
        if let first = scalars.first, first == UInt8(ascii: "+") || first == UInt8(ascii: "-") {
            negative = first == UInt8(ascii: "-")
            scalars = scalars.dropFirst()
        }
        guard !scalars.isEmpty else { throw PronoteCryptoError.invalidByteList }

        let items = Array(scalars)
        var value = 0
        var previousWasDigit = false
        for (position, byte) in items.enumerated() {
            if byte == UInt8(ascii: "_") {
                // Un souligné doit être entouré de deux chiffres.
                guard previousWasDigit,
                      position + 1 < items.count,
                      isASCIIDigit(items[position + 1]) else {
                    throw PronoteCryptoError.invalidByteList
                }
                previousWasDigit = false
            } else if isASCIIDigit(byte) {
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
                guard value <= 255 else { throw PronoteCryptoError.invalidByteList }
                previousWasDigit = true
            } else {
                throw PronoteCryptoError.invalidByteList
            }
        }
        guard !(negative && value != 0) else { throw PronoteCryptoError.invalidByteList }
        return UInt8(value)
    }

    // MARK: - PKCS#7 (blocs de 16 octets)

    static func pkcs7Pad(_ data: Data) -> Data {
        let padLength = blockSize - data.count % blockSize
        return data + Data(repeating: UInt8(padLength), count: padLength)
    }

    /// Même règles que `Crypto.Util.Padding.unpad(data, 16)` de pycryptodome.
    static func pkcs7Unpad(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count % blockSize == 0, let last = data.last else {
            throw PronoteCryptoError.invalidPadding
        }
        let padLength = Int(last)
        guard padLength >= 1, padLength <= min(blockSize, data.count) else {
            throw PronoteCryptoError.invalidPadding
        }
        let paddingStart = data.endIndex - padLength
        guard data[paddingStart..<data.endIndex].allSatisfy({ $0 == last }) else {
            throw PronoteCryptoError.invalidPadding
        }
        return Data(data[data.startIndex..<paddingStart])
    }

    // MARK: - AES-128-CBC

    /// `_Encryption.aes_set_key` : MD5 de la graine ; sans graine, MD5 de la chaîne vide.
    static func aesKey(fromSeed seed: Data?) -> Data {
        md5(seed ?? Data())
    }

    static func aesCBCEncrypt(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
        try crypt(CCOperation(kCCEncrypt), data: pkcs7Pad(plaintext), key: key, iv: iv)
    }

    /// Lève `decryptionFailed` si la longueur est invalide ou si le rembourrage est incorrect
    /// (comme le `CryptoError` de pronotepy).
    static func aesCBCDecrypt(_ ciphertext: Data, key: Data, iv: Data) throws -> Data {
        guard !ciphertext.isEmpty, ciphertext.count % blockSize == 0 else {
            throw PronoteCryptoError.decryptionFailed
        }
        let raw = try crypt(CCOperation(kCCDecrypt), data: ciphertext, key: key, iv: iv)
        do {
            return try pkcs7Unpad(raw)
        } catch {
            throw PronoteCryptoError.decryptionFailed
        }
    }

    private static func crypt(_ operation: CCOperation, data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 else { throw PronoteCryptoError.invalidKeyLength }
        guard iv.count == kCCBlockSizeAES128 else { throw PronoteCryptoError.invalidIVLength }

        var output = Data(count: data.count + kCCBlockSizeAES128)
        var bytesMoved = 0
        let outputCapacity = output.count
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(operation,
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(0), // CBC, aucun rembourrage automatique
                                keyBuffer.baseAddress, key.count,
                                ivBuffer.baseAddress,
                                dataBuffer.baseAddress, data.count,
                                outputBuffer.baseAddress, outputCapacity,
                                &bytesMoved)
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else {
            throw operation == CCOperation(kCCEncrypt)
                ? PronoteCryptoError.encryptionFailed
                : PronoteCryptoError.decryptionFailed
        }
        return Data(output.prefix(bytesMoved))
    }

    // MARK: - Dérivation des clés du flux de connexion

    struct LoginKeys: Equatable {
        /// SHA-256 hexadécimal en MAJUSCULES du mot de passe (précédé de `alea` hors ENT).
        let sha256UpperHex: String
        /// Clé AES d'authentification : MD5 de la graine.
        let authKey: Data
        /// IV : MD5 de l'IV temporaire.
        let iv: Data
    }

    /// Graine = identifiant (sauf ENT) + SHA256(alea + mot de passe).upper().
    static func deriveLoginKeys(username: String,
                                password: String,
                                alea: String,
                                ivTemp: Data,
                                isENT: Bool) -> LoginKeys {
        var passwordInput = Data()
        passwordInput.append(binaryStringData(alea))
        passwordInput.append(Data(password.utf8))

        let shaUpper = hexString(
            from: sha256(passwordInput),
            uppercase: true
        )
        var keySeed = Data()
        if !isENT {
            keySeed.append(Data(username.utf8))
        }
        keySeed.append(Data(shaUpper.utf8))

        return LoginKeys(sha256UpperHex: shaUpper,
                         authKey: aesKey(fromSeed: keySeed),
                         iv: md5(ivTemp))
    }

    static func encryptedMobileTokenProof(
        token: String,
        iv: Data
    ) throws -> String {
        let randomLength = Int.random(in: 2...9)
        let nonce = try secureRandomBytes(count: randomLength)
        return try encryptedMobileTokenProof(token: token, iv: iv, nonce: nonce)
    }

    static func encryptedMobileTokenProof(
        token: String,
        iv: Data,
        nonce: Data
    ) throws -> String {
        guard !token.isEmpty, (2...9).contains(nonce.count) else {
            throw PronoteCryptoError.invalidKeyLength
        }

        let checksum = nonce.reduce(0) { ($0 + Int($1)) % 255 }
        var message = nonce
        if checksum != 0 {
            message.append(UInt8(255 - checksum))
        }
        let cipher = try aesCBCEncrypt(
            message,
            key: aesKey(fromSeed: Data(token.utf8)),
            iv: iv
        )
        return hexString(from: cipher)
    }

    /// Pawnote/node-forge treats untagged binary strings as one byte per UTF-16 code unit.
    static func binaryStringData(_ string: String) -> Data {
        Data(string.utf16.map { UInt8(truncatingIfNeeded: $0) })
    }

    /// Équivalent de `_Communication.after_auth` : déchiffre `cle` (hexadécimal chiffré en AES),
    /// lit la liste d'octets obtenue et renvoie la clé de session (MD5 de ces octets).
    static func deriveSessionKey(cleCipherHex: String, authKey: Data, iv: Data) throws -> Data {
        let cipher = try data(fromHex: cleCipherHex)
        let plain = try aesCBCDecrypt(cipher, key: authKey, iv: iv)
        guard let text = String(data: plain, encoding: .utf8) else {
            throw PronoteCryptoError.decryptionFailed
        }
        return aesKey(fromSeed: try data(fromByteList: text))
    }

    // MARK: - RSA PKCS#1 v1.5

    /// Clé publique au format PKCS#1 `RSAPublicKey` (SEQUENCE { n, e }), attendu par `SecKeyCreateWithData`.
    static func rsaPublicKeyPKCS1DER(modulus: Data, exponent: Int) -> Data {
        let body = derInteger(modulus) + derInteger(bigEndianBytes(of: exponent))
        return Data([0x30]) + derLength(body.count) + body
    }

    /// Chiffre `message` en RSA PKCS#1 v1.5 : `(00 02 PS 00 M)^e mod n`.
    ///
    /// - Parameter randomPadding: fournit PS (octets non nuls, longueur demandée en argument).
    ///   Par défaut : octets aléatoires sécurisés. Ne passer une valeur fixe que dans les tests.
    static func rsaEncryptPKCS1v15(_ message: Data,
                                   modulus: Data,
                                   exponent: Int,
                                   randomPadding: ((Int) throws -> Data)? = nil) throws -> Data {
        let modulus = Data(modulus.drop(while: { $0 == 0 }))
        let keyLength = modulus.count
        guard keyLength >= 11, message.count <= keyLength - 11 else {
            throw PronoteCryptoError.rsaMessageTooLong
        }

        let paddingLength = keyLength - message.count - 3
        let generator = randomPadding ?? { try secureNonZeroRandomBytes(count: $0) }
        let padding = try generator(paddingLength)
        guard padding.count == paddingLength, !padding.contains(0) else {
            throw PronoteCryptoError.rsaInvalidPadding
        }
        let encoded = Data([0x00, 0x02]) + padding + Data([0x00]) + message

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: keyLength * 8
        ]
        let der = rsaPublicKeyPKCS1DER(modulus: modulus, exponent: exponent)
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil) else {
            throw PronoteCryptoError.rsaKeyCreationFailed
        }
        guard SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionRaw),
              let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, encoded as CFData, nil) as Data? else {
            throw PronoteCryptoError.rsaEncryptionFailed
        }
        guard encrypted.count <= keyLength else { throw PronoteCryptoError.rsaEncryptionFailed }
        // Un chiffré RSA fait toujours la taille de la clé (zéros de tête conservés).
        return Data(repeating: 0, count: keyLength - encrypted.count) + encrypted
    }

    // MARK: - Utilitaires internes

    static func secureNonZeroRandomBytes(count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            var chunk = [UInt8](repeating: 0, count: max(count - result.count, 16))
            guard SecRandomCopyBytes(kSecRandomDefault, chunk.count, &chunk) == errSecSuccess else {
                throw PronoteCryptoError.randomGenerationFailed
            }
            for byte in chunk where byte != 0 && result.count < count {
                result.append(byte)
            }
        }
        return result
    }

    private static func secureRandomBytes(count: Int) throws -> Data {
        var result = Data(count: count)
        let status = result.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PronoteCryptoError.randomGenerationFailed
        }
        return result
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (0x09...0x0D).contains(byte)
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    private static func bigEndianBytes(of value: Int) -> Data {
        var bytes = [UInt8]()
        var remaining = UInt(max(value, 0))
        repeat {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        } while remaining > 0
        return Data(bytes)
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        let bytes = bigEndianBytes(of: length)
        return Data([0x80 | UInt8(bytes.count)]) + bytes
    }

    private static func derInteger(_ magnitude: Data) -> Data {
        var bytes = Data(magnitude.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = Data([0]) }
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        return Data([0x02]) + derLength(bytes.count) + bytes
    }
}
