```swift
import Foundation

/// Réponses PRONOTE restent volontairement non-Codable : la structure varie selon
/// la version du serveur. Le DTO expose uniquement les primitives dont le mapper a besoin.
enum PronoteDTO {

    static func unwrap(_ value: Any) -> Any {
        guard let dictionary = value as? [String: Any] else { return value }

        if let dataSec = dictionary["dataSec"] {
            return unwrap(dataSec)
        }

        if let data = dictionary["data"] {
            return unwrap(data)
        }

        if let donnees = dictionary["donnees"] {
            return unwrap(donnees)
        }

        return value
    }

    static func array(_ value: Any, keys: [String]) -> [[String: Any]] {
        guard let dictionary = value as? [String: Any] else {
            return []
        }

        for key in keys {
            if let array = dictionary[key] as? [[String: Any]] {
                return array
            }

            if let nested = dictionary[key] as? [String: Any] {
                if let array = nested["liste"] as? [[String: Any]] {
                    return array
                }

                if let array = nested["items"] as? [[String: Any]] {
                    return array
                }
            }
        }

        return []
    }

    static func string(
        _ value: Any?,
        keys: [String] = []
    ) -> String? {

        if let value = value as? String {
            return value
        }

        if let value = value as? NSNumber {
            return value.stringValue
        }

        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let result = string(dictionary[key]) {
                    return result
                }
            }

            for key in [
                "L",
                "libelle",
                "nom",
                "name",
                "valeur",
                "value"
            ] {
                if let result = string(dictionary[key]) {
                    return result
                }
            }
        }

        return nil
    }

    static func number(
        _ value: Any?,
        keys: [String] = []
    ) -> Double? {

        if let value = value as? Double {
            return value
        }

        if let value = value as? Int {
            return Double(value)
        }

        if let value = value as? NSNumber {
            return value.doubleValue
        }

        if let value = value as? String {
            return Double(
                value.replacingOccurrences(
                    of: ",",
                    with: "."
                )
            )
        }

        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let result = number(dictionary[key]) {
                    return result
                }
            }

            for key in [
                "N",
                "valeur",
                "value",
                "note",
                "noteSur",
                "sur",
                "coef",
                "coefficient"
            ] {
                if let result = number(dictionary[key]) {
                    return result
                }
            }
        }

        return nil
    }

    static func bool(_ value: Any?) -> Bool? {

        if let value = value as? Bool {
            return value
        }

        if let value = value as? NSNumber {
            return value.boolValue
        }

        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1", "oui":
                return true

            case "false", "0", "non":
                return false

            default:
                return nil
            }
        }

        return nil
    }

    static func date(_ value: Any?) -> Date? {

        if let value = value as? Date {
            return value
        }

        guard let text = value as? String else {
            return nil
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current

        for format in formats {
            formatter.dateFormat = format

            if let date = formatter.date(from: text) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: text)
    }

    static func nestedDictionary(
        _ value: Any?,
        keys: [String]
    ) -> [String: Any]? {

        guard let dictionary = value as? [String: Any] else {
            return nil
        }

        for key in keys {
            if let result = dictionary[key] as? [String: Any] {
                return result
            }
        }

        return nil
    }

    static func recursivelyFindDictionary(
        _ value: Any,
        keys: Set<String>
    ) -> [String: Any]? {

        if let dictionary = value as? [String: Any] {

            if !Set(dictionary.keys).isDisjoint(with: keys) {
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

        } else if let array = value as? [Any] {

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
}
```
