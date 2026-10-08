import Foundation

/// Données brutes contenues dans un QR code PRONOTE mobile.
struct PronoteQRCode: Codable, Equatable {
    let login: String
    let jeton: String
    let url: String

    var accountKind: PronoteAccountKind? {
        PronoteAccountKind(qrURL: url)
    }
}

struct PronoteQRLoginResult: Equatable {
    let credentials: PronoteCredentials
    let displayName: String?
}

enum PronoteQRLoginError: Error, LocalizedError, Equatable {
    case invalidQRCode
    case invalidPIN
    case invalidURL
    case decryptionFailed
    case emptyCredentials
    case missingMobileToken
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .invalidQRCode:
            return "Le QR code PRONOTE n'est pas reconnu."
        case .invalidPIN:
            return "Le code PRONOTE doit contenir exactement 4 chiffres."
        case .invalidURL:
            return "L'adresse PRONOTE contenue dans le QR code est invalide."
        case .decryptionFailed:
            return "Impossible de déchiffrer le QR code. Vérifie le code à 4 chiffres."
        case .emptyCredentials:
            return "Le QR code PRONOTE ne contient pas de données de connexion valides."
        case .missingMobileToken:
            return "PRONOTE n'a pas fourni le nouveau jeton de connexion mobile."
        case .invalidCredentials:
            return "Saisis l’adresse PRONOTE, l’identifiant et le mot de passe."
        }
    }
}

enum PronoteQRLogin {
    static func decodeQRCode(_ text: String, pin: String) throws -> PronoteQRCode {
        let cleanedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedPIN.count == 4, cleanedPIN.allSatisfy({ $0.isNumber }) else {
            throw PronoteQRLoginError.invalidPIN
        }

        guard let data = text.data(using: .utf8),
              let qr = try? JSONDecoder().decode(PronoteQRCode.self, from: data),
              !qr.login.isEmpty,
              !qr.jeton.isEmpty,
              !qr.url.isEmpty,
              qr.accountKind != nil else {
            throw PronoteQRLoginError.invalidQRCode
        }

        return qr
    }

    static func decryptCredentials(from qr: PronoteQRCode, pin: String) throws -> PronoteDecodedCredentials {
        let key = PronoteCrypto.md5(Data(pin.utf8))
        let iv = Data(repeating: 0, count: 16)

        do {
            let encryptedLogin = try PronoteCrypto.data(fromHex: qr.login)
            let encryptedToken = try PronoteCrypto.data(fromHex: qr.jeton)
            let loginData = try PronoteCrypto.aesCBCDecrypt(encryptedLogin, key: key, iv: iv)
            let tokenData = try PronoteCrypto.aesCBCDecrypt(encryptedToken, key: key, iv: iv)

            guard let login = String(data: loginData, encoding: .utf8),
                  let token = String(data: tokenData, encoding: .utf8),
                  !login.isEmpty,
                  !token.isEmpty else {
                throw PronoteQRLoginError.emptyCredentials
            }

            let url = try normalizeQRURL(qr.url)
            guard let accountKind = qr.accountKind else {
                throw PronoteQRLoginError.invalidURL
            }
            return PronoteDecodedCredentials(
                serverURL: url,
                username: login,
                password: token,
                accountKind: accountKind
            )
        } catch let error as PronoteQRLoginError {
            throw error
        } catch {
            throw PronoteQRLoginError.decryptionFailed
        }
    }

    private static func normalizeQRURL(_ value: String) throws -> String {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            throw PronoteQRLoginError.invalidURL
        }

        var path = components.path
        if let component = path.split(separator: "/").last {
            let accountPath = String(component)
                .replacingOccurrences(of: "mobile.", with: "")
                .replacingOccurrences(of: ".html", with: "")
                .lowercased()

            if ["eleve", "parent", "professeur"].contains(accountPath) {
                path = String(path.dropLast(component.count))
                while path.count > 1 && path.hasSuffix("/") {
                    path.removeLast()
                }
            }
        }

        components.path = path
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw PronoteQRLoginError.invalidURL
        }
        return url.absoluteString
    }
}

struct PronoteDecodedCredentials: Equatable {
    let serverURL: String
    let username: String
    let password: String
    let accountKind: PronoteAccountKind
}

/// Identité stable de cette installation WakeSchool.
/// Elle est conservée dans le Keychain et réutilisée pour les connexions PRONOTE mobiles.
enum PronoteMobileIdentity {
    private static let key = "pronote.mobile.uuid"
    private static let store = KeychainSecretStore(service: "com.ayoub.wakeschool")

    static func sharedUUID() throws -> String {
        if let data = try store.data(for: key),
           let value = String(data: data, encoding: .utf8),
           UUID(uuidString: value) != nil {
            return value
        }

        let value = UUID().uuidString
        guard let data = value.data(using: .utf8) else {
            throw PronoteQRLoginError.emptyCredentials
        }
        try store.set(data, for: key)
        return value
    }
}
