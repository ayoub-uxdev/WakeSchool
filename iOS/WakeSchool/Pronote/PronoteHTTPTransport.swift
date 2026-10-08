import Foundation

struct PronoteSessionParameters: Equatable {
    let rootURL: URL
    let sessionID: String
    let spaceID: Int
    let skipRequestEncryption: Bool
    let skipRequestCompression: Bool
    let version: [Int]
    let rsaModulus: Data
    let rsaExponent: Int
    let rsaFromConstants: Bool
    let usesHTTPRSA: Bool

    var requestsAreEncrypted: Bool { !skipRequestEncryption }
    var requestsAreCompressed: Bool { !skipRequestCompression }

    init(
        rootURL: URL,
        sessionID: String,
        spaceID: Int,
        skipRequestEncryption: Bool,
        skipRequestCompression: Bool,
        version: [Int] = [2025, 1, 3],
        rsaModulus: Data = PronoteHTTPTransport.defaultRSAModulus,
        rsaExponent: Int = 0x10001,
        rsaFromConstants: Bool = true,
        usesHTTPRSA: Bool = false
    ) {
        self.rootURL = rootURL
        self.sessionID = sessionID
        self.spaceID = spaceID
        self.skipRequestEncryption = skipRequestEncryption
        self.skipRequestCompression = skipRequestCompression
        self.version = version
        self.rsaModulus = rsaModulus
        self.rsaExponent = rsaExponent
        self.rsaFromConstants = rsaFromConstants
        self.usesHTTPRSA = usesHTTPRSA
    }
}

struct PronoteAPIProperties {
    let data: String
    let requestID: String
    let orderNumber: String
    let secureData: String

    static func forVersion(_ version: [Int]) -> PronoteAPIProperties {
        let isAtLeast2025_1_3 = !version.lexicographicallyPrecedes([2025, 1, 3])
        let isAtLeast2024_3_9 = !version.lexicographicallyPrecedes([2024, 3, 9])

        return PronoteAPIProperties(
            data: isAtLeast2024_3_9 ? "data" : "donnees",
            requestID: isAtLeast2025_1_3 ? "id" : "nom",
            orderNumber: isAtLeast2025_1_3 ? "no" : "numeroOrdre",
            secureData: isAtLeast2025_1_3 ? "dataSec" : "donneesSec"
        )
    }
}

enum PronoteTransportError: Error, Equatable, LocalizedError {
    case invalidServerURL
    case invalidHTTPResponse
    case httpStatus(Int)
    case emptyResponse
    case sessionParametersNotFound
    case missingPageVersion
    case invalidSessionParameter(String)
    case pronoteError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "L'URL PRONOTE est invalide."
        case .invalidHTTPResponse: return "La réponse HTTP PRONOTE est invalide."
        case .httpStatus(let code): return "PRONOTE a répondu avec HTTP \(code)."
        case .emptyResponse: return "PRONOTE a renvoyé une réponse vide."
        case .sessionParametersNotFound: return "Impossible de trouver les paramètres de session PRONOTE dans la page HTML."
        case .missingPageVersion: return "La version PRONOTE est absente de la page de connexion."
        case .invalidSessionParameter(let name): return "Le paramètre de session PRONOTE \(name) est invalide."
        case .pronoteError(let code, let message): return "PRONOTE a refusé la requête (\(code)) : \(message)"
        }
    }
}

protocol PronoteHTTPTransporting {
    func bootstrap(
        serverURL: String,
        accountKind: PronoteAccountKind
    ) async throws -> PronoteSessionParameters
    func post(to url: URL, body: Data, additionalHeaders: [String: String]) async throws -> Data
}

final class PronoteHTTPTransport: PronoteHTTPTransporting {
    static let defaultRSAModulus: Data = {
        try! PronoteCrypto.data(
            fromHex: "B99B77A3D72D3A29B4271FC7B7300E2F791EB8948174BE7B8024667E915446D4EEA0C2424B8D1EBF7E2DDFF94691C6E994E839225C627D140A8F1146D1B0B5F18A09BBD3D8F421CA1E3E4796B301EEBCCF80D81A32A1580121B8294433C38377083C5517D5921E8A078CDC019B15775292EFDA2C30251B1CCABE812386C893E5"
        )
    }()

    private static let defaultRSAExponent = 0x10001
    private static let mobileAccountCookie = "appliMobile=1"
    private static let pronoteMobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 PRONOTE Mobile APP Version/2.0.11"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func bootstrap(
        serverURL: String,
        accountKind: PronoteAccountKind = .student
    ) async throws -> PronoteSessionParameters {
        let directURL = try Self.normalizeDirectURL(
            serverURL,
            accountKind: accountKind
        )
        var request = URLRequest(url: directURL)
        request.httpMethod = "GET"
        request.setValue(Self.pronoteMobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(Self.mobileAccountCookie, forHTTPHeaderField: "Cookie")

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
        return try Self.parseSessionParameters(
            from: html,
            directURL: http.url ?? directURL
        )
    }

    func post(to url: URL, body: Data, additionalHeaders: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.pronoteMobileUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.mobileAccountCookie, forHTTPHeaderField: "Cookie")
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

    static func normalizeDirectURL(
        _ serverURL: String,
        accountKind: PronoteAccountKind = .student
    ) throws -> URL {
        guard var components = URLComponents(string: serverURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            throw PronoteTransportError.invalidServerURL
        }

        var path = components.path
        if path == "/" {
            path = ""
        }

        if path.hasSuffix(".html") {
            if let range = path.range(of: "mobile.", options: .backwards) {
                path = String(path[..<range.lowerBound])
                while path.hasSuffix("/") {
                    path.removeLast()
                }
            } else if let slash = path.lastIndex(of: "/") {
                path = String(path[..<slash])
            }
        } else {
            while path.hasSuffix("/") {
                path.removeLast()
            }
        }

        let mobilePath = path.isEmpty
            ? "/mobile.\(accountKind.pathName).html"
            : "\(path)/mobile.\(accountKind.pathName).html"
        components.path = mobilePath
        var query = components.queryItems ?? []
        query.removeAll { ["login", "fd"].contains($0.name) }
        query.append(URLQueryItem(name: "fd", value: "1"))
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

    static func parseSessionParameters(
        from html: String
    ) throws -> PronoteSessionParameters {
        guard let directURL = URL(
            string: "https://pronote.invalid/pronote/mobile.eleve.html"
        ) else {
            throw PronoteTransportError.invalidServerURL
        }
        return try parseSessionParameters(
            from: html,
            directURL: directURL
        )
    }

    static func parseSessionParameters(
        from html: String,
        directURL: URL
    ) throws -> PronoteSessionParameters {
        let versionPattern = #">PRONOTE\s+(\d+)\.(\d+)\.(\d+)"#
        guard let versionMatch = firstMatch(versionPattern, in: html),
              let major = intCapture(versionMatch, in: html, at: 1),
              let minor = intCapture(versionMatch, in: html, at: 2),
              let patch = intCapture(versionMatch, in: html, at: 3) else {
            throw PronoteTransportError.missingPageVersion
        }
        let version = [major, minor, patch]

        let startPattern = #"(?i)\bStart\s*\(\s*\{"#
        var searchRange = html.startIndex..<html.endIndex
        var sawStart = false

        while let startMatch = html.range(
            of: startPattern,
            options: .regularExpression,
            range: searchRange
        ) {
            sawStart = true
            let opening = html.index(before: startMatch.upperBound)

            if let closing = matchingBrace(in: html, openingAt: opening) {
                let object = String(html[opening...closing])
                if let sessionID = property("h", in: object),
                   !sessionID.isEmpty,
                   let spaceID = intValue(property("a", in: object)) {
                    return try makeSessionParameters(
                        object: object,
                        directURL: directURL,
                        sessionID: sessionID,
                        spaceID: spaceID,
                        version: version
                    )
                }
            }

            searchRange = startMatch.upperBound..<html.endIndex
        }

        guard sawStart else {
            throw PronoteTransportError.sessionParametersNotFound
        }

        if let firstObject = firstStartObject(in: html, pattern: startPattern) {
            let object = String(html[firstObject])
            if property("h", in: object) == nil {
                throw PronoteTransportError.invalidSessionParameter("h")
            }
        }
        throw PronoteTransportError.invalidSessionParameter("a")
    }

    private static func makeSessionParameters(
        object: String,
        directURL: URL,
        sessionID: String,
        spaceID: Int,
        version: [Int]
    ) throws -> PronoteSessionParameters {
        let isVersionGte2025_1_3 =
            !version.lexicographicallyPrecedes([2025, 1, 3])

        let skipEncryption: Bool
        let skipCompression: Bool
        if isVersionGte2025_1_3 {
            skipEncryption = !(boolValue(property("CrA", in: object)) ?? false)
            skipCompression = !(boolValue(property("CoA", in: object)) ?? false)
        } else {
            skipEncryption = boolValue(property("sCrA", in: object)) ?? false
            skipCompression = boolValue(property("sCoA", in: object)) ?? false
        }

        let modulusValue = property("MR", in: object)
        let exponentValue = property("ER", in: object)
        let rsaFromConstants = modulusValue == nil && exponentValue == nil
        let modulus: Data
        let exponent: Int

        if rsaFromConstants {
            modulus = defaultRSAModulus
            exponent = defaultRSAExponent
        } else {
            guard let modulusValue,
                  let exponentValue,
                  let parsedModulus = try? PronoteCrypto.data(fromHex: modulusValue),
                  !parsedModulus.isEmpty,
                  let parsedExponent = Int(exponentValue, radix: 16),
                  parsedExponent > 0 else {
                throw PronoteTransportError.invalidSessionParameter("MR/ER")
            }
            modulus = parsedModulus
            exponent = parsedExponent
        }

        return PronoteSessionParameters(
            rootURL: rootURL(from: directURL),
            sessionID: sessionID,
            spaceID: spaceID,
            skipRequestEncryption: skipEncryption,
            skipRequestCompression: skipCompression,
            version: version,
            rsaModulus: modulus,
            rsaExponent: exponent,
            rsaFromConstants: rsaFromConstants,
            usesHTTPRSA: boolValue(property("http", in: object)) ?? false
        )
    }

    private static func firstMatch(
        _ pattern: String,
        in text: String
    ) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        return regex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
    }

    private static func intCapture(
        _ match: NSTextCheckingResult,
        in text: String,
        at index: Int
    ) -> Int? {
        guard let range = Range(match.range(at: index), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private static func property(
        _ name: String,
        in object: String
    ) -> String? {
        let pattern =
            #"(?i)["']?\#(NSRegularExpression.escapedPattern(for: name))["']?\s*:\s*(?:"([^"]*)"|'([^']*)'|(-?\d+)|([A-Za-z]+))"#
        guard let match = firstMatch(pattern, in: object) else {
            return nil
        }

        for captureIndex in 1...4 {
            if let range = Range(match.range(at: captureIndex), in: object) {
                return String(object[range])
            }
        }
        return nil
    }

    private static func matchingBrace(
        in text: String,
        openingAt opening: String.Index
    ) -> String.Index? {
        var depth = 0
        var quote: Character?
        var isEscaped = false
        var index = opening

        while index < text.endIndex {
            let character = text[index]

            if let activeQuote = quote {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func firstStartObject(
        in html: String,
        pattern: String
    ) -> ClosedRange<String.Index>? {
        guard let start = html.range(
            of: pattern,
            options: .regularExpression
        ) else {
            return nil
        }
        let opening = html.index(before: start.upperBound)
        guard let closing = matchingBrace(in: html, openingAt: opening) else {
            return nil
        }
        return opening...closing
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
