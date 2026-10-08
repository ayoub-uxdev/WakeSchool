import Foundation

enum PronoteJSON {

    // MARK: - Unwrap

    /// Déballe récursivement les enveloppes PRONOTE courantes.
    static func unwrap(_ value: Any) -> Any {
        guard let dictionary = value as? [String: Any] else {
            return value
        }

        for key in [
            "dataSec",
            "donneesSec",
            "data",
            "donnees",
            "Data",
            "Donnees"
        ] {
            if let nested = dictionary[key] {
                return unwrap(nested)
            }
        }

        return value
    }

    // MARK: - Dictionary search

    static func nestedDictionary(
        _ dictionary: [String: Any],
        keys: [String]
    ) -> [String: Any]? {
        for key in keys {
            if let value = dictionary[key] as? [String: Any] {
                return value
            }
        }

        return nil
    }

    static func recursivelyFindDictionary(
        _ value: Any,
        keys: [String]
    ) -> [String: Any]? {
        guard let dictionary = value as? [String: Any] else {
            if let array = value as? [Any] {
                for child in array {
                    if let result = recursivelyFindDictionary(
                        child,
                        keys: keys
                    ) {
                        return result
                    }
                }
            }

            return nil
        }

        let wantedKeys = Set(keys)

        if dictionary.keys.contains(where: wantedKeys.contains) {
            return dictionary
        }

        for child in dictionary.values {
            if let result = recursivelyFindDictionary(
                child,
                keys: keys
            ) {
                return result
            }
        }

        return nil
    }

    // MARK: - Primitive values

    static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value

        case let value as NSString:
            return value as String

        case let value as NSNumber:
            return value.stringValue

        default:
            return nil
        }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value

        case let value as Float:
            return Double(value)

        case let value as Int:
            return Double(value)

        case let value as Int64:
            return Double(value)

        case let value as NSNumber:
            return value.doubleValue

        case let value as String:
            let normalized = value
                .replacingOccurrences(of: ",", with: ".")

            return Double(normalized)

        default:
            return nil
        }
    }

    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value

        case let value as NSNumber:
            return value.boolValue

        case let value as String:
            switch value.lowercased() {
            case "true", "1", "oui", "yes":
                return true

            case "false", "0", "non", "no":
                return false

            default:
                return nil
            }

        default:
            return nil
        }
    }

    // MARK: - Dates

    static func date(_ value: Any?) -> Date? {
        switch value {
        case let value as Date:
            return value

        case let value as NSNumber:
            return dateFromTimestamp(value.doubleValue)

        case let value as String:
            return dateFromString(value)

        default:
            return nil
        }
    }

    private static func dateFromTimestamp(
        _ timestamp: Double
    ) -> Date? {
        // Timestamp Unix en secondes.
        if timestamp > 100_000_000 {
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }

    private static func dateFromString(
        _ value: String
    ) -> Date? {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        isoFormatter.formatOptions = [
            .withInternetDateTime
        ]

        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.calendar = Calendar(
            identifier: .gregorian
        )
        formatter.timeZone = .current

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm",
            "dd/MM/yyyy"
        ]

        for format in formats {
            formatter.dateFormat = format

            if let date = formatter.date(
                from: trimmed
            ) {
                return date
            }
        }

        return nil
    }
}