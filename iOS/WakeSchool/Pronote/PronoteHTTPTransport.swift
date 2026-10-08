import Foundation

struct PronoteSessionParameters: Equatable {
    let rootURL: URL
    let sessionID: String
    let spaceID: Int
    let skipRequestEncryption: Bool
    let skipRequestCompression: Bool
    let usesHTTPRSA: Bool

    var requestsAreEncrypted: Bool { !skipRequestEncryption }
    var requestsAreCompressed: Bool { !skipRequestCompression }
}

enum PronoteTransportError: Error, Equatable, LocalizedError {
    case invalidServerURL
    case invalidHTTPResponse
    case httpStatus(Int)
    case emptyResponse
    case sessionParametersNotFound
    case invalidSessionParameter(String)
    case pronoteError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "L'URL PRONOTE est invalide."
        case .invalidHTTPResponse: return "La réponse HTTP PRONOTE est invalide."
        case .httpStatus(let code): return "PRONOTE a répondu avec HTTP \(code)."
        case .emptyResponse: return "PRONOTE a renvoyé une réponse vide."
        case .sessionParametersNotFound: return "Impossible de trouver les paramètres de session PRONOTE dans la page HTML."
        case .invalidSessionParameter(let name): return "Le paramètre de session PRONOTE \(name) est invalide."
        case .pronoteError(let code, let message): return "PRONOTE a refusé la requête (\(code)) : \(message)"
        }
    }
}

protocol PronoteHTTPTransporting {
    func bootstrap(serverURL: String) async throws -> PronoteSessionParameters
    func post(to url: URL, body: Data, additionalHeaders: [String: String]) async throws -> Data
}

final class PronoteHTTPTransport: PronoteHTTPTransporting {
    private static let pronoteMobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 PRONOTE Mobile APP Version/2.0.11"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func bootstrap(serverURL: String) async throws -> PronoteSessionParameters {
        let directURL = try Self.normalizeDirectURL(serverURL)
        var request = URLRequest(url: directURL)
        request.httpMethod = "GET"
        request.setValue(Self.pronoteMobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PronoteTransportError.invalidHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PronoteTransportError.httpStatus(http.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw PronoteTransportError.emptyResponse
        }
        return try Self.parseSessionParameters(from: html, directURL: directURL)
    }

    func post(to url: URL, body: Data, additionalHeaders: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.pronoteMobileUserAgent, forHTTPHeaderField: "User-Agent")
        additionalHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PronoteTransportError.invalidHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PronoteTransportError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw PronoteTransportError.emptyResponse }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["Erreur"] as? [String: Any],
           let code = Self.intValue(error["G"]),
           code != 0 {
            let message = (error["Titre"] as? String) ?? "Erreur inconnue"
            throw PronoteTransportError.pronoteError(code, message)
        }
        return data
    }

    static func normalizeDirectURL(_ serverURL: String) throws -> URL {
        guard var components = URLComponents(string: serverURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            throw PronoteTransportError.invalidServerURL
        }

        var path = components.path
        if path.isEmpty || path == "/" {
            path = "/pronote/mobile.eleve.html"
        } else if path.hasSuffix("/eleve.html") && !path.hasSuffix("/mobile.eleve.html") {
            path = String(path.dropLast("eleve.html".count)) + "mobile.eleve.html"
        } else if path.hasSuffix("/pronote") {
            path += "/mobile.eleve.html"
        } else if path.hasSuffix("/") {
            path += "mobile.eleve.html"
        } else if !path.contains(".html") {
            path += "/mobile.eleve.html"
        }
        components.path = path
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "login" }
        query.append(URLQueryItem(name: "login", value: "true"))
        components.queryItems = query
        guard let url = components.url else { throw PronoteTransportError.invalidServerURL }
        return url
    }

    static func rootURL(from directURL: URL) -> URL {
        var components = URLComponents(url: directURL, resolvingAgainstBaseURL: false)!
        let path = components.path
        if let range = path.range(of: "/mobile.") {
            components.path = String(path[..<range.lowerBound]) + "/"
        } else if let range = path.range(of: "/eleve.html") {
            components.path = String(path[..<range.lowerBound]) + "/"
        } else {
            components.path = path.hasSuffix("/") ? path : path + "/"
        }
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    static func appelfonctionURL(rootURL: URL, spaceID: Int, sessionID: String, order: String) -> URL {
        rootURL
            .appendingPathComponent("appelfonction")
            .appendingPathComponent(String(spaceID))
            .appendingPathComponent(sessionID)
            .appendingPathComponent(order)
    }

    static func parseSessionParameters(from html: String, directURL: URL) throws -> PronoteSessionParameters {
        guard let startRange = html.range(of: "Start", options: .caseInsensitive),
              let open = html[startRange.upperBound...].firstIndex(of: "{"),
              let close = html[open...].firstIndex(of: "}") else {
            throw PronoteTransportError.sessionParametersNotFound
        }

        let raw = String(html[html.index(after: open)..<close])
        var values: [String: String] = [:]
        for part in raw.split(separator: ",") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            let key = pieces[0].trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            let value = pieces[1].trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            values[key] = value
        }

        guard let sessionID = values["h"], !sessionID.isEmpty else {
            throw PronoteTransportError.invalidSessionParameter("h")
        }
        guard let spaceID = intValue(values["a"]) else {
            throw PronoteTransportError.invalidSessionParameter("a")
        }

        // Pronote's protocol document calls these sCrA/sCoA (skip flags), while
        // some deployed pages expose CrA/CoA. Support both spellings.
        let skipEncryption = boolValue(values["sCrA"] ?? values["CrA"]) ?? false
        let skipCompression = boolValue(values["sCoA"] ?? values["CoA"]) ?? false
        let usesHTTPRSA = directURL.scheme?.lowercased() == "http"

        return PronoteSessionParameters(
            rootURL: rootURL(from: directURL),
            sessionID: sessionID,
            spaceID: spaceID,
            skipRequestEncryption: skipEncryption,
            skipRequestCompression: skipCompression,
            usesHTTPRSA: usesHTTPRSA
        )
    }

    private static func boolValue(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
