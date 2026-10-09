import Foundation

enum PronoteAccountKind: Int, Codable, CaseIterable, Hashable, Identifiable {
    case student = 6
    case parent = 7
    case teacher = 8

    var id: Int { rawValue }

    var pathName: String {
        switch self {
        case .student: return "eleve"
        case .parent: return "parent"
        case .teacher: return "professeur"
        }
    }

    var displayName: String {
        switch self {
        case .student: return "Élève"
        case .parent: return "Parent"
        case .teacher: return "Enseignant"
        }
    }

    init?(qrURL: String) {
        guard let path = URLComponents(string: qrURL)?.path,
              let component = path.split(separator: "/").last else {
            return nil
        }

        let name = String(component)
            .replacingOccurrences(of: "mobile.", with: "")
            .replacingOccurrences(of: ".html", with: "")
            .lowercased()

        switch name {
        case "eleve": self = .student
        case "parent": self = .parent
        case "professeur": self = .teacher
        default: return nil
        }
    }
}

/// Identifiants PRONOTE conservés exclusivement dans le Keychain.
///
/// Pour les connexions QR ou ENT, `usesMobileToken` est vrai et `mobileUUID`
/// contient l'identifiant stable de cette installation WakeSchool.
struct PronoteCredentials: Codable, Equatable, CustomStringConvertible {
    var serverURL: String
    var username: String
    var password: String
    var accountKind: PronoteAccountKind
    var usesMobileToken: Bool
    var mobileUUID: String?

    init(serverURL: String,
         username: String,
         password: String,
         accountKind: PronoteAccountKind = .student,
         usesMobileToken: Bool = false,
         mobileUUID: String? = nil) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.accountKind = accountKind
        self.usesMobileToken = usesMobileToken
        self.mobileUUID = mobileUUID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(String.self, forKey: .serverURL)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        accountKind = try container.decodeIfPresent(
            PronoteAccountKind.self,
            forKey: .accountKind
        ) ?? .student
        usesMobileToken = try container.decodeIfPresent(Bool.self, forKey: .usesMobileToken) ?? false
        mobileUUID = try container.decodeIfPresent(String.self, forKey: .mobileUUID)
    }

    var description: String {
        "PronoteCredentials(serverURL: \(serverURL), username: \(username), password: ***, usesMobileToken: \(usesMobileToken), mobileUUID: \(mobileUUID != nil ? "configured" : "nil"))"
    }
}
