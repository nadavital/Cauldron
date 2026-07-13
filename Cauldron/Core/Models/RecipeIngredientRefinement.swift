import Foundation

struct RecipeIngredientRefinement: Sendable, Equatable {
    let required: [String]
    let excluded: [String]

    nonisolated init(requiredText: String, excludedText: String) {
        required = Self.tokens(from: requiredText)
        excluded = Self.tokens(from: excludedText)
    }

    nonisolated var isEmpty: Bool { required.isEmpty && excluded.isEmpty }

    nonisolated func matches(ingredientNames: [String]) -> Bool {
        let normalizedNames = ingredientNames.map(Self.normalize)
        return required.allSatisfy { requiredToken in
            normalizedNames.contains { Self.containsPhrase(requiredToken, in: $0) }
        } && excluded.allSatisfy { excludedToken in
            !normalizedNames.contains { Self.containsPhrase(excludedToken, in: $0) }
        }
    }

    nonisolated private static func containsPhrase(_ phrase: String, in ingredient: String) -> Bool {
        let phraseWords = phrase.split(separator: " ").map(String.init)
        let ingredientWords = ingredient.split(separator: " ").map(String.init)
        guard !phraseWords.isEmpty, phraseWords.count <= ingredientWords.count else { return false }
        for start in 0...(ingredientWords.count - phraseWords.count) {
            if zip(phraseWords, ingredientWords[start...]).allSatisfy({ pair in
                canonical(pair.0) == canonical(pair.1)
            }) {
                return true
            }
        }
        return false
    }

    nonisolated private static func canonical(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count > 4, word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.count > 4, word.hasSuffix("es") { return String(word.dropLast(2)) }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    nonisolated private static func tokens(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").compactMap { fragment in
            let token = normalize(String(fragment).trimmingCharacters(in: .whitespacesAndNewlines))
            guard !token.isEmpty, seen.insert(token).inserted else { return nil }
            return token
        }
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
