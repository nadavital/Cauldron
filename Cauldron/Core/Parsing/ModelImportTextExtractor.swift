import Foundation

/// Extracts import-ready text lines from recipe websites, mirroring lab URL extraction behavior.
struct ModelImportTextExtractor: Sendable {
    struct Extraction: Sendable {
        let method: String
        let title: String?
        let ingredientLines: [String]
        let stepLines: [String]
        let noteLines: [String]
        let rawLines: [String]
        let yields: String?
        let totalMinutes: Int?
        let imageURL: URL?
        let tags: [Tag]
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

            let decoded = HTMLEntityDecoder.decode(raw, stripTags: false)
            let variants = decoded == raw ? [raw] : [raw, decoded]
            for variant in variants {
                for payload in parseJSONLDPayloads(raw: variant) {
                    collectRecipeNodes(from: payload, into: &recipes)
                }
            }
        }

        guard !recipes.isEmpty else { return nil }
        let recipe = recipes.max(by: { recipeScore($0) < recipeScore($1) }) ?? recipes[0]

        let title = cleanText(stringValue(recipe["name"]))
        let ingredientLines = extractIngredients(from: recipe)
        let stepLines = extractInstructionLines(from: recipe)
        guard !ingredientLines.isEmpty, !stepLines.isEmpty else {
            return nil
        }

        var lines: [String] = []
        if !title.isEmpty { lines.append(title) }
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
        let tags = parseTags(from: recipe)

        return Extraction(
            method: "jsonld_recipe",
            title: title.isEmpty ? nil : title,
            ingredientLines: ingredientLines,
            stepLines: stepLines,
            noteLines: [],
            rawLines: lines,
            yields: yields,
            totalMinutes: totalMinutes,
            imageURL: imageURL,
            tags: tags
        )
    }

    private func extractFromVisibleHTML(_ html: String, sourceURL: URL?) -> Extraction? {
        let main = extractMainFragment(from: html)
        var text = stripHiddenContent(from: main)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = HTMLEntityDecoder.decode(text, stripTags: true)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: ". ", with: ".\n")
        text = cleanText(text)

        let title = extractTitle(from: html)
        var lines = text
            .components(separatedBy: .newlines)
            .map(cleanText)
            .filter { !$0.isEmpty }
        if let title, !title.isEmpty {
            lines.insert(title, at: 0)
        }

        guard !lines.isEmpty else { return nil }
        return Extraction(
            method: "html_visible_text",
            title: title,
            ingredientLines: [],
            stepLines: [],
            noteLines: [],
            rawLines: lines,
            yields: nil,
            totalMinutes: nil,
            imageURL: nil,
            tags: []
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
        // Best-effort split for malformed payloads concatenating objects without commas.
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
                if depth == 0 { continue }
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
            #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#,
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
            let title = cleanText(HTMLEntityDecoder.decode(stripped, stripTags: true))
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

        var minutes = 0
        if let hourRange = cleaned.range(of: #"(\d+)H"#, options: .regularExpression) {
            let hourDigits = cleaned[hourRange].filter(\.isNumber)
            minutes += (Int(hourDigits) ?? 0) * 60
        }
        if let minuteRange = cleaned.range(of: #"(\d+)M"#, options: .regularExpression) {
            let minuteDigits = cleaned[minuteRange].filter(\.isNumber)
            minutes += Int(minuteDigits) ?? 0
        }
        return minutes > 0 ? minutes : TimeParser.parseTimeString(cleaned)
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

    private func parseTags(from recipe: [String: Any]) -> [Tag] {
        var tags: [Tag] = []
        let category = cleanText(stringValue(recipe["recipeCategory"]))
        if !category.isEmpty {
            tags.append(Tag(name: category))
        }
        let cuisine = cleanText(stringValue(recipe["recipeCuisine"]))
        if !cuisine.isEmpty {
            tags.append(Tag(name: cuisine))
        }
        let keywords = cleanText(stringValue(recipe["keywords"]))
        if !keywords.isEmpty {
            tags.append(
                contentsOf: keywords
                    .split(separator: ",")
                    .map { Tag(name: cleanText(String($0))) }
                    .filter { !$0.name.isEmpty }
            )
        }
        return tags
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
        HTMLEntityDecoder.decode(value, stripTags: true)
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
}
