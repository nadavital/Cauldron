import Foundation

struct PreparedShareRecipePayload: Codable {
    let title: String
    let ingredients: [String]
    let steps: [String]
    let yields: String?
    let totalMinutes: Int?
    let sourceURL: String?
    let sourceTitle: String?
    let imageURL: String?
}

enum SharedRecipePreprocessor {
    static func prepareRecipePayload(from url: URL) async -> PreparedShareRecipePayload? {
        guard let html = await fetchHTML(from: url),
              let recipeObject = extractFirstRecipeObject(from: html) else {
            return nil
        }

        let title = cleanedString(recipeObject["name"]) ?? cleanedString(recipeObject["headline"]) ?? cleanedHTMLTitle(from: html)
        let ingredients = extractIngredientLines(from: recipeObject)
        let steps = extractStepLines(from: recipeObject)

        guard let title, !title.isEmpty, !ingredients.isEmpty, !steps.isEmpty else {
            return nil
        }

        let yields = extractYield(from: recipeObject)
        let totalMinutes = extractTotalMinutes(from: recipeObject)
        let sourceTitle = cleanedHTMLTitle(from: html)
        let imageURL = extractImageURL(from: recipeObject)

        return PreparedShareRecipePayload(
            title: title,
            ingredients: Array(ingredients.prefix(80)),
            steps: Array(steps.prefix(80)),
            yields: yields,
            totalMinutes: totalMinutes,
            sourceURL: url.absoluteString,
            sourceTitle: sourceTitle,
            imageURL: imageURL
        )
    }

    private static func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if let html = String(data: data, encoding: .utf8) {
                return html
            }

            if let html = String(data: data, encoding: .isoLatin1) {
                return html
            }

            return nil
        } catch {
            return nil
        }
    }

    private static func extractFirstRecipeObject(from html: String) -> [String: Any]? {
        let scripts = extractJSONLDScripts(from: html)
        for script in scripts {
            guard let data = script.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            if let recipe = findRecipeObject(in: json) {
                return recipe
            }
        }

        return nil
    }

    private static func extractJSONLDScripts(from html: String) -> [String] {
        let pattern = #"<script[^>]*type=[\"']application/ld\+json[\"'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let scriptRange = Range(match.range(at: 1), in: html) else {
                return nil
            }

            return stripCommentWrappers(from: html[scriptRange].trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func stripCommentWrappers(from script: String) -> String {
        var value = script
        if value.hasPrefix("<!--") {
            value.removeFirst(4)
        }
        if value.hasSuffix("-->") {
            value.removeLast(3)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func findRecipeObject(in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if isRecipeType(dict["@type"]) {
                return dict
            }

            if let graph = dict["@graph"] as? [Any] {
                for node in graph {
                    if let recipe = findRecipeObject(in: node) {
                        return recipe
                    }
                }
            }

            if let itemList = dict["itemListElement"] as? [Any] {
                for node in itemList {
                    if let recipe = findRecipeObject(in: node) {
                        return recipe
                    }
                }
            }
        }

        if let array = json as? [Any] {
            for item in array {
                if let recipe = findRecipeObject(in: item) {
                    return recipe
                }
            }
        }

        return nil
    }

    private static func isRecipeType(_ typeValue: Any?) -> Bool {
        if let type = typeValue as? String {
            return type.localizedCaseInsensitiveContains("Recipe")
        }

        if let types = typeValue as? [String] {
            return types.contains { $0.localizedCaseInsensitiveContains("Recipe") }
        }

        return false
    }

    private static func extractIngredientLines(from recipe: [String: Any]) -> [String] {
        let rawIngredients: [String]

        if let list = recipe["recipeIngredient"] as? [String] {
            rawIngredients = list
        } else if let list = recipe["ingredients"] as? [String] {
            rawIngredients = list
        } else {
            rawIngredients = []
        }

        return rawIngredients
            .map { cleanLine($0) }
            .filter { !$0.isEmpty }
    }

    private static func extractStepLines(from recipe: [String: Any]) -> [String] {
        guard let rawInstructions = recipe["recipeInstructions"] ?? recipe["instructions"] else {
            return []
        }

        let steps = flattenInstructionNodes(rawInstructions)
            .map { cleanLine($0) }
            .filter { !$0.isEmpty }

        return steps
    }

    private static func flattenInstructionNodes(_ value: Any) -> [String] {
        if let text = value as? String {
            return splitInstructionString(text)
        }

        if let array = value as? [Any] {
            return array.flatMap { flattenInstructionNodes($0) }
        }

        if let dict = value as? [String: Any] {
            if let text = cleanedString(dict["text"]) {
                return [text]
            }

            if let itemList = dict["itemListElement"] {
                return flattenInstructionNodes(itemList)
            }

            if let name = cleanedString(dict["name"]) {
                return [name]
            }
        }

        return []
    }

    private static func splitInstructionString(_ value: String) -> [String] {
        let cleaned = value.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = cleaned
            .components(separatedBy: "\n")
            .map { cleanLine($0) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return lines
        }

        let sentenceSplit = cleaned
            .components(separatedBy: ". ")
            .map { cleanLine($0) }
            .filter { !$0.isEmpty }

        return sentenceSplit.isEmpty ? [cleanLine(cleaned)] : sentenceSplit
    }

    private static func extractYield(from recipe: [String: Any]) -> String? {
        if let yieldString = cleanedString(recipe["recipeYield"]) {
            return yieldString
        }

        if let yieldList = recipe["recipeYield"] as? [Any],
           let first = yieldList.first,
           let value = cleanedString(first) {
            return value
        }

        return nil
    }

    private static func extractTotalMinutes(from recipe: [String: Any]) -> Int? {
        if let totalTime = cleanedString(recipe["totalTime"]),
           let minutes = parseDurationToMinutes(totalTime) {
            return minutes
        }

        if let prep = cleanedString(recipe["prepTime"]),
           let prepMinutes = parseDurationToMinutes(prep),
           let cook = cleanedString(recipe["cookTime"]),
           let cookMinutes = parseDurationToMinutes(cook) {
            return prepMinutes + cookMinutes
        }

        return nil
    }

    private static func parseDurationToMinutes(_ duration: String) -> Int? {
        let uppercased = duration.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard uppercased.hasPrefix("P") else { return nil }

        let pattern = #"P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(uppercased.startIndex..., in: uppercased)
        guard let match = regex.firstMatch(in: uppercased, options: [], range: range) else {
            return nil
        }

        let days = intCapture(match, in: uppercased, at: 1) ?? 0
        let hours = intCapture(match, in: uppercased, at: 2) ?? 0
        let minutes = intCapture(match, in: uppercased, at: 3) ?? 0

        let total = (days * 24 * 60) + (hours * 60) + minutes
        return total > 0 ? total : nil
    }

    private static func extractImageURL(from recipe: [String: Any]) -> String? {
        guard let imageValue = recipe["image"] else {
            return nil
        }

        return extractURLString(from: imageValue)
    }

    private static func extractURLString(from value: Any?) -> String? {
        guard let value else { return nil }

        if let string = cleanedString(value),
           let url = URL(string: string),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url.absoluteString
        }

        if let dict = value as? [String: Any] {
            if let directURL = extractURLString(from: dict["url"]) {
                return directURL
            }
            if let directURL = extractURLString(from: dict["@id"]) {
                return directURL
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let url = extractURLString(from: item) {
                    return url
                }
            }
        }

        return nil
    }

    private static func intCapture(_ match: NSTextCheckingResult, in text: String, at index: Int) -> Int? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: text) else {
            return nil
        }

        return Int(text[range])
    }

    private static func cleanedHTMLTitle(from html: String) -> String? {
        let pattern = #"<title[^>]*>([\s\S]*?)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let searchRange = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: searchRange),
              match.numberOfRanges > 1,
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return cleanLine(String(html[titleRange]))
    }

    private static func cleanedString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let cleaned = cleanLine(string)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func cleanLine(_ value: String) -> String {
        let strippedPrefix = value.replacingOccurrences(
            of: #"^\s*(?:\d+[\.)]|[-•*])\s*"#,
            with: "",
            options: .regularExpression
        )

        let withoutTags = strippedPrefix.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"[^\S\n]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
