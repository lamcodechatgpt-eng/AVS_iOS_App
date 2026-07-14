import Foundation

enum HTMLUtilities {
    static func decodeEntities(_ input: String) -> String {
        var output = input
        // `&amp;` must be decoded first so a nested entity such as
        // `&amp;quot;` can be decoded by a later replacement in this pass.
        let named: [(String, String)] = [
            ("&amp;", "&"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", "\u{00A0}")
        ]
        for (entity, value) in named {
            output = output.replacingOccurrences(of: entity,
                                                  with: value,
                                                  options: .caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-f]+);", options: .caseInsensitive) else {
            return output
        }
        let mutable = NSMutableString(string: output)
        let matches = regex.matches(in: output, range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() {
            guard let valueRange = Range(match.range(at: 1), in: output) else { continue }
            let token = String(output[valueRange])
            let radix = token.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(token.dropFirst()) : token
            guard let value = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(value) else { continue }
            mutable.replaceCharacters(in: match.range, with: String(scalar))
        }
        return mutable as String
    }

    static func plainText(fromHTML html: String) -> String {
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>",
                                                     with: " ",
                                                     options: .regularExpression)
        return decodeEntities(withoutTags)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum SearchUtilities {
    /// Creates the path component expected by AnimeVietsub's `/tim-kiem/` route.
    /// Encoding each word separately keeps `+` as the word separator while making
    /// reserved characters such as `/`, `?` and `#` harmless inside the path.
    static func pathComponent(from query: String) -> String? {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .lowercased()

        let words = normalized.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%+")
        let encoded = words.compactMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) }
        guard encoded.count == words.count else { return nil }
        return encoded.joined(separator: "+")
    }
}
