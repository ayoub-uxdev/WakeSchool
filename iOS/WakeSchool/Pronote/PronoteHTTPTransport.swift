import Foundation

enum PronoteTransportError: Error, Equatable, LocalizedError {
    case invalidServerURL
    case invalidHTTPResponse
    case httpStatus(Int)
    case emptyResponse
    case sessionParametersNotFound
    case invalidSessionParameter(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "L’URL du serveur PRONOTE est invalide."
        case .invalidHTTPResponse: return "La réponse du serveur PRONOTE n’est pas une réponse HTTP valide."
        case .httpStatus(let status): return "PRONOTE a répondu avec le code HTTP \(status)."
        case .emptyResponse: return "PRONOTE a renvoyé une réponse vide."
        case .sessionParametersNotFound: return "Les paramètres de session PRONOTE sont introuvables dans la page HTML."
        case .invalidSessionParameter(let name): return "Le paramètre de session PRONOTE « \(name) » est invalide."
        }
    }
}

struct PronoteSessionParameters: Equatable {
    let sessionID: String
    let spaceID: Int
    let skipRequestEncryption: Bool
    let skipRequestCompression: Bool

    var requestsAreEncrypted: Bool { !skipRequestEncryption }
    var requestsAreCompressed: Bool { !skipRequestCompression }
}

protocol PronoteHTTPTransporting {
    func bootstrap(serverURL: String) async throws -> PronoteSessionParameters
    func post(to url: URL, body: Data, additionalHeaders: [String: String]) async throws -> Data
}

final class PronoteHTTPTransport: PronoteHTTPTransporting {
    private let session: URLSession
    private let userAgent: String

    init(
        session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = HTTPCookieStorage()
            configuration.httpShouldSetCookies = true
            configuration.httpCookieAcceptPolicy = .always
            return URLSession(configuration: configuration)
        }(),
        userAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    ) {
        self.session = session
        self.userAgent = userAgent
    }

    func bootstrap(serverURL: String) async throws -> PronoteSessionParameters {
        guard var components = URLComponents(string: serverURL), components.scheme != nil, components.host != nil else {
            throw PronoteTransportError.invalidServerURL
        }

        let path: String
        if components.path.isEmpty || components.path == "/" {
            path = "/pronote/mobile.eleve.html"
        } else if components.path.lowercased().hasSuffix(".html") {
            let directory = String(components.path[..<(components.path.lastIndex(of: "/") ?? components.path.endIndex)])
            path = (directory.isEmpty ? "" : directory) + "/mobile.eleve.html"
        } else {
            path = (components.path.hasSuffix("/") ? components.path : components.path + "/") + "mobile.eleve.html"
        }

        components.path = path
        components.queryItems = [URLQueryItem(name: "login", value: "true")]

        guard let url = components.url else {
            throw PronoteTransportError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        _ = try validate(response)

        guard !data.isEmpty, let html = String(data: data, encoding: .utf8) else {
            throw PronoteTransportError.emptyResponse
        }

        return try Self.parseSessionParameters(from: html)
    }

    func post(to url: URL, body: Data, additionalHeaders: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        _ = try validate(response)

        guard !data.isEmpty else { throw PronoteTransportError.emptyResponse }
        return data
    }

    private func validate(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PronoteTransportError.invalidHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PronoteTransportError.httpStatus(httpResponse.statusCode)
        }
        return httpResponse
    }

    static func parseSessionParameters(from html: String) throws -> PronoteSessionParameters {
        guard let onloadRange = html.range(of: #"onload\s*=\s*[\"']"#, options: .regularExpression) else {
            throw PronoteTransportError.sessionParametersNotFound
        }
        let afterOnload = html[onloadRange.upperBound...]

        guard let startRange = afterOnload.range(of: #"Start\s*\(\s*"#, options: .regularExpression) else {
            throw PronoteTransportError.sessionParametersNotFound
        }
        let afterStart = afterOnload[startRange.upperBound...]

        guard let closing = findMatchingObjectEnd(in: afterStart) else {
            throw PronoteTransportError.sessionParametersNotFound
        }
        let object = String(afterStart[..<closing])

        guard let sessionID = stringValue(named: "h", in: object) else {
            throw PronoteTransportError.invalidSessionParameter("h")
        }
        guard let spaceID = intValue(named: "a", in: object) else {
            throw PronoteTransportError.invalidSessionParameter("a")
        }
        guard let skipEncryption = boolValue(named: "sCrA", in: object) else {
            throw PronoteTransportError.invalidSessionParameter("sCrA")
        }
        guard let skipCompression = boolValue(named: "sCoA", in: object) else {
            throw PronoteTransportError.invalidSessionParameter("sCoA")
        }

        return PronoteSessionParameters(
            sessionID: sessionID,
            spaceID: spaceID,
            skipRequestEncryption: skipEncryption,
            skipRequestCompression: skipCompression
        )
    }

    private static func findMatchingObjectEnd(in text: Substring) -> String.Index? {
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if (inSingleQuote || inDoubleQuote) && character == "\\" { escaped = true; continue }
            if character == "'" && !inDoubleQuote { inSingleQuote.toggle(); continue }
            if character == "\"" && !inSingleQuote { inDoubleQuote.toggle(); continue }
            guard !inSingleQuote && !inDoubleQuote else { continue }
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func stringValue(named name: String, in object: String) -> String? {
        let pattern = "(?:^|[,{]\\s*)" + NSRegularExpression.escapedPattern(for: name) + "\\s*:\\s*['\"]([^'\"]*)['\"]"
        return firstCapture(pattern, in: object)
    }

    private static func intValue(named name: String, in object: String) -> Int? {
        let pattern = "(?:^|[,{]\\s*)" + NSRegularExpression.escapedPattern(for: name) + "\\s*:\\s*(-?\\d+)"
        guard let value = firstCapture(pattern, in: object) else { return nil }
        return Int(value)
    }

    private static func boolValue(named name: String, in object: String) -> Bool? {
        let pattern = "(?:^|[,{]\\s*)" + NSRegularExpression.escapedPattern(for: name) + "\\s*:\\s*(true|false)"
        guard let value = firstCapture(pattern, in: object) else { return nil }
        return value == "true"
    }

    private static func firstCapture(_ pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let captureRange = Range(match.range(at: 1), in: string) else { return nil }
        return String(string[captureRange])
    }
}
