import Foundation

/// Identifiants Pronote. Ne se stockent QUE dans le Keychain (voir `CredentialsStore`).
struct PronoteCredentials: Codable, Equatable, CustomStringConvertible {
    var serverURL: String
    var username: String
    var password: String

    /// Le mot de passe n'apparaît jamais dans les logs.
    var description: String {
        "PronoteCredentials(serverURL: \(serverURL), username: \(username), password: ***)"
    }
}
