import Foundation

/// Conservative recognition shared by prepared-payload bridging and the text
/// assembler. Numeric titles are accepted only for known structural prefixes,
/// keeping quantities and numbered instruction labels as recipe content.
nonisolated enum RecipeSubsectionHeaderPolicy {
    private static let numericPrefixes: Set<String> = [
        "day", "part", "stage", "phase", "section", "round", "layer"
    ]

    static func title(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":"), trimmed.count <= 90 else { return nil }
        let title = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = title.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= 7 else { return nil }

        if title.contains(where: \.isNumber) {
            guard words.count >= 2,
                  numericPrefixes.contains(words[0].lowercased()),
                  Int(words[1]) != nil,
                  !words.dropFirst(2).contains(where: { word in
                      word.contains(where: \.isNumber)
                  }) else {
                return nil
            }
        }
        return title
    }
}
