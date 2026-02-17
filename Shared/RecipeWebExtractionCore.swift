import Foundation

/// Shared HTML/JSON-LD extraction core used by app import and Share Extension paths.
struct RecipeWebExtractionCore: Sendable {
    struct Extraction: Sendable {
        let method: String
        let title: String?
        let pageTitle: String?
        let ingredientLines: [String]
        let stepLines: [String]
        let noteLines: [String]
        let rawLines: [String]
        let yields: String?
        let totalMinutes: Int?
        let imageURL: URL?
        let rawTagNames: [String]
    }

    func extract(fromHTML html: String, sourceURL: URL? = nil) -> Extraction? {
        if let jsonLD = extractFromJSONLD(html, sourceURL: sourceURL) {
            return jsonLD
        }
        return extractFromVisibleHTML(html, sourceURL: sourceURL)
    }

    private func extractFromJSONLD(_ html: String, sourceURL: URL?) -> Extraction? {
        var recipes: [[String: Any]] = []
        for block in jsonLDBlocks(in: html) {
            let raw = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            let decoded = decodeHTMLEntities(raw, stripTags: false)
            let variants = decoded == raw ? [raw] : [raw, decoded]
            for variant in variants {
                for payload in parseJSONLDPayloads(raw: variant) {
                    collectRecipeNodes(from: payload, into: &recipes)
                }
            }
        }

        guard !recipes.isEmpty else { return nil }
        let recipe = recipes.max(by: { recipeScore($0) < recipeScore($1) }) ?? recipes[0]

        let titleText = cleanText(stringValue(recipe["name"]))
        let title = titleText.isEmpty ? nil : titleText
        let pageTitle = extractTitle(from: html)
        let ingredientLines = extractIngredients(from: recipe)
        let stepLines = extractInstructionLines(from: recipe)
        guard !ingredientLines.isEmpty, !stepLines.isEmpty else {
            return nil
        }

        var lines: [String] = []
        if let title {
            lines.append(title)
        }
        lines.append("Ingredients")
        lines.append(contentsOf: ingredientLines)
        lines.append("Instructions")
        lines.append(contentsOf: stepLines)

        let yields = parseYield(recipe["recipeYield"])
        let totalMinutes = parseTotalMinutes(
            totalTime: stringValue(recipe["totalTime"]),
            cookTime: stringValue(recipe["cookTime"]),
            prepTime: stringValue(recipe["prepTime"])
        )
        let imageURL = parseImageURL(recipe["image"], baseURL: sourceURL)
        let rawTagNames = parseRawTagNames(from: recipe)

        return Extraction(
            method: "jsonld_recipe",
            title: title,
            pageTitle: pageTitle,
            ingredientLines: ingredientLines,
            stepLines: stepLines,
            noteLines: [],
            rawLines: lines,
            yields: yields,
            totalMinutes: totalMinutes,
            imageURL: imageURL,
            rawTagNames: rawTagNames
        )
    }

    private func extractFromVisibleHTML(_ html: String, sourceURL: URL?) -> Extraction? {
        let main = extractMainFragment(from: html)
        var text = stripHiddenContent(from: main)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = decodeHTMLEntities(text, stripTags: true)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: ". ", with: ".\n")
        text = cleanText(text)

        let pageTitle = extractTitle(from: html)
        var lines = text
            .components(separatedBy: .newlines)
            .map(cleanText)
            .filter { !$0.isEmpty }
        if let pageTitle, !pageTitle.isEmpty {
            lines.insert(pageTitle, at: 0)
        }

        guard !lines.isEmpty else { return nil }
        return Extraction(
            method: "html_visible_text",
            title: pageTitle,
            pageTitle: pageTitle,
            ingredientLines: [],
            stepLines: [],
            noteLines: [],
            rawLines: lines,
            yields: nil,
            totalMinutes: nil,
            imageURL: nil,
            rawTagNames: []
        )
    }

    private func jsonLDBlocks(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]*type\s*=\s*(?:[\"']?application/ld\+json[\"']?)[^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }

    private func parseJSONLDPayloads(raw: String) -> [Any] {
        var base = raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        base = base.replacingOccurrences(
            of: #"^\s*<!--\s*|\s*-->\s*$"#,
            with: "",
            options: .regularExpression
        )
        guard !base.isEmpty else { return [] }

        let escaped = escapeControlCharactersInJSONStringLiterals(base)
        let variants = unique([
            base,
            escaped,
            base.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression),
            escaped.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
        ])

        for variant in variants {
            guard let data = variant.data(using: .utf8) else { continue }
            if let obj = try? JSONSerialization.jsonObject(with: data, options: []) {
                return [obj]
            }
            if let decoded = decodeMultipleJSONValues(raw: variant), !decoded.isEmpty {
                return decoded
            }
        }
        return []
    }

    private func decodeMultipleJSONValues(raw: String) -> [Any]? {
        let parts = raw
            .replacingOccurrences(of: "}{", with: "}\n{")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return nil }

        var values: [Any] = []
        for part in parts {
            guard let data = part.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: []) else {
                return nil
            }
            values.append(value)
        }
        return values
    }

    private func collectRecipeNodes(from value: Any, into out: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            if isRecipeType(dict["@type"]) {
                out.append(dict)
            }
            for child in dict.values {
                collectRecipeNodes(from: child, into: &out)
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                collectRecipeNodes(from: child, into: &out)
            }
        }
    }

    private func isRecipeType(_ value: Any?) -> Bool {
        if let text = value as? String {
            let lowered = text.lowercased()
            if lowered.split(separator: "/").last == "recipe" {
                return true
            }
            return lowered.contains("recipe")
        }

        if let array = value as? [Any] {
            return array.contains(where: { isRecipeType($0) })
        }

        return false
    }

    private func recipeScore(_ recipe: [String: Any]) -> Int {
        let titleScore = cleanText(stringValue(recipe["name"])).isEmpty ? 0 : 3
        let ingredientScore = extractIngredients(from: recipe).count
        let stepScore = extractInstructionLines(from: recipe).count * 2
        return titleScore + ingredientScore + stepScore
    }

    private func extractIngredients(from recipe: [String: Any]) -> [String] {
        let value = recipe["recipeIngredient"] ?? recipe["ingredients"]
        var out: [String] = []
        for item in asArray(value) {
            if let text = item as? String {
                let cleaned = normalizeIngredientSourceText(text)
                if !cleaned.isEmpty {
                    out.append(cleaned)
                }
            } else if let dict = item as? [String: Any] {
                let cleaned = normalizeIngredientSourceText(stringValue(dict["text"]))
                if !cleaned.isEmpty {
                    out.append(cleaned)
                }
            }
        }
        return uniqueCaseInsensitive(out)
    }

    private func extractInstructionLines(from recipe: [String: Any]) -> [String] {
        var out: [String] = []

        func walk(_ node: Any?) {
            guard let node else { return }

            if let text = node as? String {
                let cleaned = cleanText(text)
                if !cleaned.isEmpty {
                    out.append(contentsOf: splitNumberedSteps(cleaned))
                }
                return
            }

            if let array = node as? [Any] {
                for item in array {
                    walk(item)
                }
                return
            }

            guard let dict = node as? [String: Any] else { return }

            let sectionName = cleanText(stringValue(dict["name"]))
            if !sectionName.isEmpty,
               sectionName.split(separator: " ").count <= 7,
               dict["itemListElement"] != nil {
                out.append("\(sectionName):")
            }

            if let text = dict["text"] as? String {
                let cleaned = cleanText(text)
                if !cleaned.isEmpty {
                    out.append(contentsOf: splitNumberedSteps(cleaned))
                }
            }

            if let list = dict["itemListElement"] {
                walk(list)
                return
            }

            for key in ["steps", "instructions", "recipeInstructions"] {
                if let child = dict[key] {
                    walk(child)
                }
            }
        }

        walk(recipe["recipeInstructions"] ?? recipe["instructions"])
        return uniqueCaseInsensitive(out)
    }

    private func splitNumberedSteps(_ text: String) -> [String] {
        let cleaned = cleanText(text)
        guard !cleaned.isEmpty else { return [] }

        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(\d{1,2})\.\s+"#) else {
            return [cleaned]
        }

        let ns = cleaned as NSString
        let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2, matches.first?.range.location == 0 else {
            return [cleaned]
        }

        var parts: [String] = []
        for (index, match) in matches.enumerated() {
            let start = match.range.location
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let part = cleanText(ns.substring(with: NSRange(location: start, length: end - start)))
            if !part.isEmpty {
                parts.append(part)
            }
        }

        return parts.isEmpty ? [cleaned] : parts
    }

    private func normalizeIngredientSourceText(_ value: String) -> String {
        var text = cleanText(value)
        guard !text.isEmpty else { return "" }

        text = text.replacingOccurrences(of: #"\(\s*,\s*"#, with: "(", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\(\s*;\s*"#, with: "(", options: .regularExpression)

        while true {
            let collapsed = text.replacingOccurrences(
                of: #"\(\(\s*([^()]*)\s*\)\)"#,
                with: "($1)",
                options: .regularExpression
            )
            let flattened = collapsed.replacingOccurrences(of: "((", with: "(").replacingOccurrences(of: "))", with: ")")
            if flattened == text {
                break
            }
            text = flattened
        }

        text = text.replacingOccurrences(of: #"\(\s+"#, with: "(", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+\)"#, with: ")", options: .regularExpression)

        var balanced = ""
        balanced.reserveCapacity(text.count)
        var depth = 0
        for char in text {
            if char == "(" {
                depth += 1
                balanced.append(char)
                continue
            }
            if char == ")" {
                if depth == 0 {
                    continue
                }
                depth -= 1
                balanced.append(char)
                continue
            }
            balanced.append(char)
        }
        if depth > 0 {
            balanced.append(String(repeating: ")", count: depth))
        }

        return cleanText(balanced)
    }

    private func extractMainFragment(from html: String) -> String {
        let patterns = [
            #"<article[^>]*>(.*?)</article>"#,
            #"<main[^>]*>(.*?)</main>"#
        ]

        var candidates: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) where match.numberOfRanges >= 2 {
                candidates.append(ns.substring(with: match.range(at: 1)))
            }
        }

        return candidates.max(by: { $0.count < $1.count }) ?? html
    }

    private func stripHiddenContent(from html: String) -> String {
        var output = html
        let patterns = [
            #"<script\b[^>]*>.*?</script>"#,
            #"<style\b[^>]*>.*?</style>"#,
            #"<noscript\b[^>]*>.*?</noscript>"#
        ]

        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }

        return output
    }

    private func extractTitle(from html: String) -> String? {
        let patterns = [
            #"<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']"#,
            #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']"#,
            #"<h1[^>]*>(.*?)</h1>"#,
            #"<title[^>]*>(.*?)</title>"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let ns = html as NSString
            guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
                  match.numberOfRanges >= 2 else {
                continue
            }

            let raw = ns.substring(with: match.range(at: 1))
            let stripped = raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            let title = cleanText(decodeHTMLEntities(stripped, stripTags: true))
            if !title.isEmpty {
                return title
            }
        }

        return nil
    }

    private func parseYield(_ value: Any?) -> String? {
        if let string = value as? String {
            let cleaned = cleanText(string)
            return cleaned.isEmpty ? nil : cleaned
        }
        if let number = value as? Int {
            return "\(number) servings"
        }
        if let array = value as? [Any], let first = array.first {
            return parseYield(first)
        }
        return nil
    }

    private func parseTotalMinutes(totalTime: String, cookTime: String, prepTime: String) -> Int? {
        if let total = parseDuration(totalTime) {
            return total
        }
        let cook = parseDuration(cookTime) ?? 0
        let prep = parseDuration(prepTime) ?? 0
        let combined = cook + prep
        return combined > 0 ? combined : nil
    }

    private func parseDuration(_ value: String) -> Int? {
        let cleaned = cleanText(value)
        guard !cleaned.isEmpty else { return nil }

        let upper = cleaned.uppercased()
        if upper.hasPrefix("P") {
            var minutes = 0
            if let hourRange = upper.range(of: #"(\d+)H"#, options: .regularExpression) {
                let digits = upper[hourRange].filter(\.isNumber)
                minutes += (Int(digits) ?? 0) * 60
            }
            if let minuteRange = upper.range(of: #"(\d+)M"#, options: .regularExpression) {
                let digits = upper[minuteRange].filter(\.isNumber)
                minutes += Int(digits) ?? 0
            }
            if minutes > 0 {
                return minutes
            }
        }

        return parseLooseTime(cleaned)
    }

    private func parseLooseTime(_ text: String) -> Int? {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let colon = firstMatch(pattern: #"(\d+):(\d+)"#, in: cleaned),
           let hours = Int(colon[0]),
           let minutes = Int(colon[1]) {
            return (hours * 60) + minutes
        }

        let combinedPattern = #"(\d+)\s*(?:hours?|hrs?|h)\s*(?:and\s*)?(\d+)?\s*(?:minutes?|mins?|m)?"#
        if let combined = firstMatch(pattern: combinedPattern, in: cleaned),
           let hours = Int(combined[0]) {
            let minuteValue = combined.count > 1 ? (Int(combined[1]) ?? 0) : 0
            return (hours * 60) + minuteValue
        }

        if let hours = firstMatch(pattern: #"(\d+)\s*(?:hours?|hrs?|h)\b"#, in: cleaned).flatMap({ Int($0[0]) }) {
            return hours * 60
        }

        if let minutes = firstMatch(pattern: #"(\d+)\s*(?:minutes?|mins?|m)\b"#, in: cleaned).flatMap({ Int($0[0]) }) {
            return minutes
        }

        if let value = Int(cleaned.filter { $0.isNumber || $0 == " " }.trimmingCharacters(in: .whitespaces)),
           value > 0 {
            return value
        }

        return nil
    }

    private func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        var captures: [String] = []
        for idx in 1..<match.numberOfRanges {
            guard let captureRange = Range(match.range(at: idx), in: text) else {
                captures.append("")
                continue
            }
            captures.append(String(text[captureRange]))
        }

        return captures
    }

    private func parseImageURL(_ value: Any?, baseURL: URL?) -> URL? {
        if let string = value as? String {
            return normalizeURL(from: string, relativeTo: baseURL)
        }
        if let array = value as? [Any], let first = array.first {
            return parseImageURL(first, baseURL: baseURL)
        }
        if let dict = value as? [String: Any], let url = dict["url"] {
            return parseImageURL(url, baseURL: baseURL)
        }
        return nil
    }

    private func parseRawTagNames(from recipe: [String: Any]) -> [String] {
        var tags: [String] = []

        for key in ["recipeCategory", "recipeCuisine", "keywords"] {
            for value in asArray(recipe[key]) {
                if let string = value as? String {
                    let splitValues = string
                        .split(separator: ",")
                        .map { cleanText(String($0)) }
                        .filter { !$0.isEmpty }
                    tags.append(contentsOf: splitValues)
                }
            }
        }

        return uniqueCaseInsensitive(tags)
    }

    private func normalizeURL(from raw: String, relativeTo baseURL: URL?) -> URL? {
        let cleaned = cleanText(raw)
        guard !cleaned.isEmpty else { return nil }

        if let absolute = URL(string: cleaned),
           let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return absolute
        }

        if cleaned.hasPrefix("//"), let url = URL(string: "https:\(cleaned)") {
            return url
        }

        if cleaned.hasPrefix("/"),
           let baseURL,
           let relative = URL(string: cleaned, relativeTo: baseURL) {
            return relative.absoluteURL
        }

        return nil
    }

    private func asArray(_ value: Any?) -> [Any] {
        guard let value else { return [] }
        if let array = value as? [Any] {
            return array
        }
        return [value]
    }

    private func stringValue(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        return ""
    }

    private func cleanText(_ value: String) -> String {
        decodeHTMLEntities(value, stripTags: true)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func unique(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                out.append(value)
            }
        }
        return out
    }

    private func uniqueCaseInsensitive(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for value in values {
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(key).inserted {
                out.append(value)
            }
        }
        return out
    }

    private func escapeControlCharactersInJSONStringLiterals(_ raw: String) -> String {
        var out = ""
        var inString = false
        var escaped = false

        for ch in raw {
            if inString {
                if escaped {
                    out.append(ch)
                    escaped = false
                    continue
                }
                if ch == "\\" {
                    out.append(ch)
                    escaped = true
                    continue
                }
                if ch == "\"" {
                    out.append(ch)
                    inString = false
                    continue
                }
                if ch == "\n" {
                    out.append("\\n")
                    continue
                }
                if ch == "\r" {
                    out.append("\\r")
                    continue
                }
                if ch == "\t" {
                    out.append("\\t")
                    continue
                }
                out.append(ch)
                continue
            }

            out.append(ch)
            if ch == "\"" {
                inString = true
                escaped = false
            }
        }

        return out
    }

    private func decodeHTMLEntities(_ text: String, stripTags: Bool) -> String {
        var result = text

        if stripTags {
            result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }

        let namedEntities: [String: String] = [
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
            "&frac14;": "1/4",
            "&frac12;": "1/2",
            "&frac34;": "3/4"
        ]

        result = decodeNumericEntities(result, pattern: "&#x([0-9A-Fa-f]+);") { hex in
            if let value = Int(hex, radix: 16), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
            return nil
        }

        result = decodeNumericEntities(result, pattern: "&#(\\d+);") { decimal in
            if let value = Int(decimal), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
            return nil
        }

        for (entity, character) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: character)
        }

        return result
    }

    private func decodeNumericEntities(_ text: String, pattern: String, decoder: (String) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        var result = text
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length)).reversed()

        for match in matches {
            guard match.numberOfRanges >= 2 else {
                continue
            }

            let fullRange = match.range(at: 0)
            let valueRange = match.range(at: 1)
            let value = nsString.substring(with: valueRange)

            if let decoded = decoder(value) {
                let fullMatch = nsString.substring(with: fullRange)
                result = result.replacingOccurrences(of: fullMatch, with: decoded)
            }
        }

        return result
    }
}
