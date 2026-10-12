import Foundation

enum HomeworkDescriptionFormatter {
    static func plainText(from source: String) -> String {
        guard source.contains("<"), source.contains(">") else {
            return normalize(source)
        }

        let document = """
        <!doctype html><html><head><meta charset="utf-8"></head><body>\(source)</body></html>
        """
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        do {
            let attributed = try NSAttributedString(
                data: Data(document.utf8),
                options: options,
                documentAttributes: nil
            )
            return normalize(attributed.string)
        } catch {
            return "La description du devoir n'a pas pu être affichée."
        }
    }

    private static func normalize(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var normalized: [String] = []
        var previousWasEmpty = false
        for line in lines {
            let isEmpty = line.isEmpty
            if !isEmpty || !previousWasEmpty {
                normalized.append(line)
            }
            previousWasEmpty = isEmpty
        }
        return normalized.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
