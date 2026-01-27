//
//  HTMLEntityDecoder.swift
//  Cauldron
//
//  Created on November 13, 2025.
//

import Foundation

/// Decodes HTML entities and optionally strips HTML tags
///
/// Handles:
/// - Named entities (&nbsp;, &amp;, &lt;, &gt;, &quot;, etc.)
/// - Numeric entities (&#32;, &#x20;)
/// - Fraction entities (&frac12;, &frac14;, &frac34;)
/// - Unicode characters cleanup (checkboxes, bullets)
struct HTMLEntityDecoder {

    /// Named HTML entities mapped to their character equivalents
    private static let namedEntities: [String: String] = [
        "&nbsp;": " ",
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&#39;": "'",
        "&apos;": "'",
        "&rsquo;": "'",
        "&ldquo;": "\"",
        "&rdquo;": "\"",
        "&mdash;": "—",
        "&ndash;": "–",
        "&frac14;": "¼",
        "&frac12;": "½",
        "&frac34;": "¾"
    ]

    /// Decode HTML entities and optionally strip tags
    ///
    /// - Parameters:
    ///   - text: The HTML text to decode
    ///   - stripTags: Whether to remove HTML tags (default: true)
    /// - Returns: Cleaned text with entities decoded
    ///
    /// Examples:
    /// ```swift
    /// HTMLEntityDecoder.decode("&lt;b&gt;Hello&lt;/b&gt;")
    /// // "Hello"
    ///
    /// HTMLEntityDecoder.decode("&frac12; cup", stripTags: false)
    /// // "½ cup"
    ///
    /// HTMLEntityDecoder.decode("&#x25a; test")
    /// // "º test"
    /// ```
    static func decode(_ text: String, stripTags: Bool = true) -> String {
        var result = text

        // Remove HTML tags if requested
        if stripTags {
            result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }

        // Decode numeric HTML entities (hex format: &#xHEX;)
        result = decodeNumericEntities(result, pattern: "&#x([0-9A-Fa-f]+);") { hex in
            if let value = Int(hex, radix: 16), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
            return nil
        }

        // Decode numeric HTML entities (decimal format: &#DECIMAL;)
        result = decodeNumericEntities(result, pattern: "&#(\\d+);") { decimal in
            if let value = Int(decimal), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
            return nil
        }

        // Decode named HTML entities
        for (entity, character) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: character)
        }

        // Remove unwanted unicode characters
        // Checkboxes: U+2610 ☐, U+2611 ☑, U+2612 ☒
        // Squares: U+25A1 □, U+25A0 ■
        // Small squares: U+25AB ▫, U+25AA ▪
        result = result.replacingOccurrences(of: "[☐☑☒□■▫▪]", with: "", options: .regularExpression)

        // Remove leading bullet points and list markers
        result = result.replacingOccurrences(of: "^[•●○◦▪▫-]\\s*", with: "", options: .regularExpression)

        // Clean horizontal whitespace only (preserve newlines)
        result = result.replacingOccurrences(of: "[^\\S\\n]+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Decode numeric entities using a pattern and decoder function
    ///
    /// - Parameters:
    ///   - text: The text to decode
    ///   - pattern: The regex pattern to match entities
    ///   - decoder: Function to convert matched value to character
    /// - Returns: Text with entities decoded
    private static func decodeNumericEntities(_ text: String, pattern: String, decoder: (String) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        var result = text
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length)).reversed()

        for match in matches {
            if match.numberOfRanges >= 2 {
                let fullRange = match.range(at: 0)
                let valueRange = match.range(at: 1)
                let value = nsString.substring(with: valueRange)

                if let decoded = decoder(value) {
                    let fullMatch = nsString.substring(with: fullRange)
                    result = result.replacingOccurrences(of: fullMatch, with: decoded)
                }
            }
        }

        return result
    }
}
