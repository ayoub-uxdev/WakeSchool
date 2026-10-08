import Foundation

/// Identifiants PRONOTE conservés exclusivement dans le Keychain.
///
/// Pour une connexion QR, `usesMobileToken` est vrai et `mobileUUID` contient
/// l'identifiant stable de cette installation WakeSchool.
struct PronoteCredentials: Codable, Equatable, CustomStringConvertible {
    var serverURL: String
    var username: String
    var password: String
    var usesMobileToken: Bool
    var mobileUUID: String?

    init(serverURL: String,
         username: String,
         password: String,
         usesMobileToken: Bool = false,
         mobileUUID: String? = nil) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.usesMobileToken = usesMobileToken
        self.mobileUUID = mobileUUID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(String.self, forKey: .serverURL)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        usesMobileToken = try container.decodeIfPresent(Bool.self, forKey: .usesMobileToken) ?? false
        mobileUUID = try container.decodeIfPresent(String.self, forKey: .mobileUUID)
    }

    var description: String {
        "PronoteCredentials(serverURL: \(serverURL), username: \(username), password: ***, usesMobileToken: \(usesMobileToken), mobileUUID: \(mobileUUID != nil ? "configured" : "nil"))"
    }
}
