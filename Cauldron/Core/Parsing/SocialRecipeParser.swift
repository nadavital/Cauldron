import Foundation

/// Unified parser for social media recipe imports (YouTube, Instagram, TikTok).
actor SocialRecipeParser: RecipeParser {
    typealias HTMLFetcher = @Sendable (URL) async throws -> String

    private struct SocialExtraction {
        let title: String
        let bodyText: String
        let imageURL: URL?
    }

    private let textParser: any ModelRecipeTextParsing
    private let htmlFetcher: HTMLFetcher

    init(
        textParser: any ModelRecipeTextParsing = TextRecipeParser(),
        htmlFetcher: @escaping HTMLFetcher = SocialRecipeParser.defaultHTMLFetcher(for:)
    ) {
        self.textParser = textParser
        self.htmlFetcher = htmlFetcher
    }

    func parse(from source: String) async throws -> Recipe {
        let platform = PlatformDetector.detect(from: source)
        return try await parse(from: source, platform: platform)
    }

    func parse(from source: String, platform: Platform) async throws -> Recipe {
        guard platform == .youtube || platform == .instagram || platform == .tiktok else {
            throw ParsingError.platformNotSupported("This URL")
        }

        let normalizedURLString = try normalizedURLString(for: source, platform: platform)
        guard let fetchURL = URL(string: normalizedURLString) else {
            throw ParsingError.invalidURL
        }

        let html = try await htmlFetcher(fetchURL)
        let extraction = try extractSocialMetadata(from: html, platform: platform)

        guard SocialMetadataExtractor.looksLikeRecipe(extraction.bodyText) else {
            throw ParsingError.noRecipeFound
        }

        let lines = SocialMetadataExtractor.normalizedLines(from: extraction.bodyText)

        return try await textParser.parse(
            lines: lines,
            sourceURL: URL(string: source),
            sourceTitle: extraction.title,
            imageURL: extraction.imageURL,
            tags: [],
            preferredTitle: extraction.title,
            yieldsOverride: nil,
            totalMinutesOverride: nil
        )
    }

    private func normalizedURLString(for source: String, platform: Platform) throws -> String {
        switch platform {
        case .youtube:
            guard let normalized = PlatformDetector.normalizeYouTubeURL(source) else {
                throw ParsingError.invalidURL
            }
            return normalized
        case .instagram, .tiktok:
            guard URL(string: source) != nil else {
                throw ParsingError.invalidURL
            }
            return source
        case .recipeWebsite, .unknown:
            throw ParsingError.platformNotSupported("This URL")
        }
    }

    private func extractSocialMetadata(from html: String, platform: Platform) throws -> SocialExtraction {
        switch platform {
        case .youtube:
            return try extractYouTubeMetadata(from: html)
        case .instagram:
            return try extractInstagramMetadata(from: html)
        case .tiktok:
            return try extractTikTokMetadata(from: html)
        case .recipeWebsite, .unknown:
            throw ParsingError.platformNotSupported("This URL")
        }
    }

    nonisolated private static func defaultHTMLFetcher(for url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParsingError.invalidHTML
        }
        return html
    }
}

// MARK: - YouTube

private extension SocialRecipeParser {
    private func extractYouTubeMetadata(from html: String) throws -> SocialExtraction {
        let title = extractYouTubeTitle(from: html)
        let description = try extractYouTubeDescription(from: html)
        let imageURL = extractYouTubeThumbnailURL(from: html)

        return SocialExtraction(
            title: title,
            bodyText: description,
            imageURL: imageURL
        )
    }

    func extractYouTubeTitle(from html: String) -> String {
        if let title = SocialMetadataExtractor.extractMetaContent(from: html, property: "og:title") {
            return title
        }

        if let titleRange = html.range(of: "<title>"),
           let endRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
            let title = String(html[titleRange.upperBound..<endRange.lowerBound])
            return title.replacingOccurrences(of: " - YouTube", with: "").trimmingCharacters(in: .whitespaces)
        }

        return "YouTube Recipe"
    }

    func extractYouTubeDescription(from html: String) throws -> String {
        if let description = extractYouTubeDescriptionFromInitialData(html), !description.hasSuffix("...") {
            return description
        }

        if let description = SocialMetadataExtractor.extractMetaContent(from: html, name: "description"),
           !description.isEmpty,
           !description.hasSuffix("...") {
            return description
        }

        if let description = SocialMetadataExtractor.extractMetaContent(from: html, property: "og:description"),
           !description.isEmpty,
           !description.hasSuffix("...") {
            return description
        }

        throw ParsingError.noRecipeFound
    }

    func extractYouTubeThumbnailURL(from html: String) -> URL? {
        guard let rawThumbnail = SocialMetadataExtractor.extractMetaContent(from: html, property: "og:image") else {
            return nil
        }
        return URL(string: rawThumbnail)
    }

    func extractYouTubeDescriptionFromInitialData(_ html: String) -> String? {
        // Fast path: direct capture of attributed description payload.
        let descriptionPattern = #""attributedDescriptionBodyText":\{"content":"((?:[^"\\]|\\.)*)""#
        if let regex = try? NSRegularExpression(pattern: descriptionPattern, options: []),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           match.numberOfRanges >= 2 {
            let nsString = html as NSString
            let descRange = match.range(at: 1)
            var rawDescription = nsString.substring(with: descRange)

            rawDescription = rawDescription.replacingOccurrences(of: "\\\"", with: "\"")
            rawDescription = rawDescription.replacingOccurrences(of: "\\\\", with: "\\")
            rawDescription = rawDescription.replacingOccurrences(of: "\\n", with: "\n")
            rawDescription = rawDescription.replacingOccurrences(of: "\\r", with: "\r")
            rawDescription = rawDescription.replacingOccurrences(of: "\\t", with: "\t")

            if !rawDescription.isEmpty {
                return rawDescription
            }
        }

        // Fallback path: parse ytInitialData JSON and walk known renderer paths.
        guard let startRange = html.range(of: "var ytInitialData = ") else {
            return nil
        }

        let substring = html[startRange.upperBound...]
        guard let endMarker = substring.range(of: "</script>") else {
            return nil
        }

        var potentialJSON = String(substring[..<endMarker.lowerBound])

        if potentialJSON.hasPrefix("'") {
            potentialJSON = String(potentialJSON.dropFirst())
        }

        if potentialJSON.hasSuffix(";'") {
            potentialJSON = String(potentialJSON.dropLast(2))
        } else if potentialJSON.hasSuffix("'") {
            potentialJSON = String(potentialJSON.dropLast())
        } else if potentialJSON.hasSuffix(";") {
            potentialJSON = String(potentialJSON.dropLast())
        }

        var jsonString = potentialJSON
        if jsonString.hasPrefix("\\x") {
            jsonString = unescapeHexString(jsonString)
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        while jsonString.hasSuffix(";") || jsonString.hasSuffix("'") {
            jsonString = String(jsonString.dropLast())
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let description = extractYouTubeDescriptionFromStructuredContent(json) {
            return description
        }
        if let description = extractYouTubeDescriptionFromEngagementPanels(json) {
            return description
        }
        if let description = extractYouTubeDescriptionFromTwoColumn(json) {
            return description
        }

        return nil
    }

    func extractYouTubeDescriptionFromEngagementPanels(_ json: [String: Any]) -> String? {
        guard let engagementPanels = json["engagementPanels"] as? [[String: Any]] else {
            return nil
        }

        for panel in engagementPanels {
            if let renderer = panel["engagementPanelSectionListRenderer"] as? [String: Any],
               let content = renderer["content"] as? [String: Any],
               let descriptionRenderer = content["structuredDescriptionContentRenderer"] as? [String: Any],
               let items = descriptionRenderer["items"] as? [[String: Any]] {

                var fullDescription = ""
                for item in items {
                    if let videoDescriptionRenderer = item["videoDescriptionHeaderRenderer"] as? [String: Any],
                       let descriptionSnippet = videoDescriptionRenderer["descriptionSnippet"] as? [String: Any],
                       let runs = descriptionSnippet["runs"] as? [[String: Any]] {
                        fullDescription += runs.compactMap { $0["text"] as? String }.joined()
                    }

                    if let expandableVideoDescriptionBody = item["expandableVideoDescriptionBodyRenderer"] as? [String: Any],
                       let descriptionBodyText = expandableVideoDescriptionBody["descriptionBodyText"] as? [String: Any],
                       let runs = descriptionBodyText["runs"] as? [[String: Any]] {
                        fullDescription += runs.compactMap { $0["text"] as? String }.joined()
                    }
                }

                if !fullDescription.isEmpty {
                    return fullDescription
                }
            }

            if let renderer = panel["engagementPanelSectionListRenderer"] as? [String: Any],
               let content = renderer["content"] as? [String: Any],
               let descriptionRenderer = content["videoDescriptionRenderer"] as? [String: Any],
               let description = descriptionRenderer["description"] as? [String: Any],
               let runs = description["runs"] as? [[String: Any]] {
                let fullDescription = runs.compactMap { $0["text"] as? String }.joined()
                if !fullDescription.isEmpty {
                    return fullDescription
                }
            }
        }

        return nil
    }

    func extractYouTubeDescriptionFromTwoColumn(_ json: [String: Any]) -> String? {
        guard let contents = json["contents"] as? [String: Any],
              let twoColumnWatchNextResults = contents["twoColumnWatchNextResults"] as? [String: Any],
              let results = twoColumnWatchNextResults["results"] as? [String: Any],
              let resultsContents = results["results"] as? [String: Any],
              let contents2 = resultsContents["contents"] as? [[String: Any]] else {
            return nil
        }

        for content in contents2 {
            if let videoPrimaryInfoRenderer = content["videoPrimaryInfoRenderer"] as? [String: Any],
               let description = videoPrimaryInfoRenderer["description"] as? [String: Any],
               let runs = description["runs"] as? [[String: Any]] {
                let fullDescription = runs.compactMap { $0["text"] as? String }.joined()
                if !fullDescription.isEmpty {
                    return fullDescription
                }
            }
        }

        return nil
    }

    func extractYouTubeDescriptionFromStructuredContent(_ json: [String: Any]) -> String? {
        guard let engagementPanels = json["engagementPanels"] as? [[String: Any]] else {
            return nil
        }

        for panel in engagementPanels {
            guard let renderer = panel["engagementPanelSectionListRenderer"] as? [String: Any],
                  let content = renderer["content"] as? [String: Any],
                  let structured = content["structuredDescriptionContentRenderer"] as? [String: Any],
                  let items = structured["items"] as? [[String: Any]] else {
                continue
            }

            var description = ""

            for item in items {
                if let bodyRenderer = item["expandableVideoDescriptionBodyRenderer"] as? [String: Any] {
                    if let attributedDescription = bodyRenderer["attributedDescriptionBodyText"] as? [String: Any],
                       let textContent = attributedDescription["content"] as? String {
                        description += textContent
                    } else if let descriptionBodyText = bodyRenderer["descriptionBodyText"] as? [String: Any],
                              let runs = descriptionBodyText["runs"] as? [[String: Any]] {
                        description += runs.compactMap { $0["text"] as? String }.joined()
                    }
                }

                if let headerRenderer = item["videoDescriptionHeaderRenderer"] as? [String: Any],
                   let descriptionSnippet = headerRenderer["descriptionSnippet"] as? [String: Any],
                   let runs = descriptionSnippet["runs"] as? [[String: Any]] {
                    let headerText = runs.compactMap { $0["text"] as? String }.joined()
                    if !headerText.isEmpty && !description.contains(headerText) {
                        description = headerText + "\n" + description
                    }
                }
            }

            if !description.isEmpty {
                return description
            }
        }

        return nil
    }

    func unescapeHexString(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if index < text.index(text.endIndex, offsetBy: -3),
               text[index] == "\\",
               text[text.index(after: index)] == "x" {
                let hexStart = text.index(index, offsetBy: 2)
                let hexEnd = text.index(hexStart, offsetBy: 2)
                let hexString = String(text[hexStart..<hexEnd])

                if let hexValue = UInt8(hexString, radix: 16) {
                    result.append(Character(UnicodeScalar(hexValue)))
                    index = hexEnd
                    continue
                }
            }

            result.append(text[index])
            index = text.index(after: index)
        }

        return result
    }
}

// MARK: - Instagram

private extension SocialRecipeParser {
    private func extractInstagramMetadata(from html: String) throws -> SocialExtraction {
        let caption = try extractInstagramCaption(from: html)
        let title = extractInstagramPostTitle(caption: caption)

        return SocialExtraction(
            title: title,
            bodyText: caption,
            imageURL: extractInstagramThumbnailURL(from: html)
        )
    }

    func extractInstagramPostTitle(caption: String) -> String {
        let lines = caption.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            if TextSectionParser.looksLikeIngredient(trimmed) {
                continue
            }
            if trimmed.count < 10 || trimmed.count > 150 {
                continue
            }

            return trimmed
        }

        if caption.count > 60 {
            let index = caption.index(caption.startIndex, offsetBy: 60)
            return String(caption[..<index]) + "..."
        }

        return caption.isEmpty ? "Instagram Recipe" : caption
    }

    func extractInstagramCaption(from html: String) throws -> String {
        var rawCaption: String?

        if let description = SocialMetadataExtractor.extractMetaContent(from: html, property: "og:description") {
            rawCaption = description
        }

        if rawCaption == nil,
           let description = SocialMetadataExtractor.extractMetaContent(from: html, name: "description") {
            rawCaption = description
        }

        if rawCaption == nil,
           let caption = extractInstagramCaptionFromJSONLD(html) {
            rawCaption = caption
        }

        if rawCaption == nil,
           let caption = extractInstagramCaptionFromEmbeddedData(html) {
            rawCaption = caption
        }

        guard let caption = rawCaption else {
            throw ParsingError.noRecipeFound
        }

        return cleanInstagramCaption(caption)
    }

    func cleanInstagramCaption(_ caption: String) -> String {
        var cleaned = HTMLEntityDecoder.decode(caption, stripTags: false)

        let likesCommentsPattern = #"^\d+[KMB]?\s+(likes?|comments?|views?)(,\s*\d+[KMB]?\s+(likes?|comments?|views?))?\s*-\s*"#
        if let regex = try? NSRegularExpression(pattern: likesCommentsPattern, options: [.caseInsensitive]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        let patterns = [
            #"^[,\s]*-\s*[\w.]+\s+on\s+[A-Z][a-z]+\s+\d+,\s+\d{4}:\s*"#,
            #"^[\w.]+\s+on\s+[A-Z][a-z]+\s+\d+,\s+\d{4}:\s*"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") {
            cleaned = String(cleaned.dropFirst())
        }
        if cleaned.hasSuffix("\".") {
            cleaned = String(cleaned.dropLast(2))
        } else if cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropLast())
        }

        let metadataPatterns = [
            #"\d+[KMB]?\s+(likes?|comments?|views?|shares?)"#,
            #"^\d+[KMB]?\s"#,
            #"\s+·\s+"#
        ]

        for pattern in metadataPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            }
        }

        if cleaned.range(of: #"\s*#\w+"#, options: .regularExpression) != nil {
            let hashtagPattern = #"\s*#[\w\s]+"#
            if let regex = try? NSRegularExpression(pattern: hashtagPattern, options: []) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            }
        }

        let filteredLines = cleaned.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return false
            }
            if trimmed.range(of: #"^\d+[KMB]?$"#, options: .regularExpression) != nil {
                return false
            }
            if trimmed.hasPrefix("#") {
                return false
            }
            return true
        }

        return filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractInstagramThumbnailURL(from html: String) -> URL? {
        if let imageURL = SocialMetadataExtractor.extractMetaContent(from: html, property: "og:image") {
            return URL(string: HTMLEntityDecoder.decode(imageURL, stripTags: false))
        }

        if let imageURL = SocialMetadataExtractor.extractMetaContent(from: html, name: "twitter:image") {
            return URL(string: HTMLEntityDecoder.decode(imageURL, stripTags: false))
        }

        return nil
    }

    func extractInstagramCaptionFromJSONLD(_ html: String) -> String? {
        let pattern = #"<script type="application/ld\+json">(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let nsString = html as NSString
        let jsonRange = match.range(at: 1)
        let jsonString = nsString.substring(with: jsonRange)

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let description = json["description"] as? String ?? json["caption"] as? String else {
            return nil
        }

        return description
    }

    func extractInstagramCaptionFromEmbeddedData(_ html: String) -> String? {
        let pattern = #""caption":\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let nsString = html as NSString
        let captionRange = match.range(at: 1)
        var caption = nsString.substring(with: captionRange)

        caption = caption.replacingOccurrences(of: "\\\"", with: "\"")
        caption = caption.replacingOccurrences(of: "\\\\", with: "\\")
        caption = caption.replacingOccurrences(of: "\\n", with: "\n")
        caption = caption.replacingOccurrences(of: "\\r", with: "\r")
        caption = caption.replacingOccurrences(of: "\\t", with: "\t")

        return caption.isEmpty ? nil : caption
    }
}

// MARK: - TikTok

private extension SocialRecipeParser {
    private func extractTikTokMetadata(from html: String) throws -> SocialExtraction {
        let description = try extractTikTokDescription(from: html)
        let title = extractTikTokTitle(from: html, description: description)

        return SocialExtraction(
            title: title,
            bodyText: description,
            imageURL: extractTikTokThumbnailURL(from: html)
        )
    }

    func extractTikTokTitle(from html: String, description: String?) -> String {
        if let description {
            let lines = description.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.count > 10 && trimmed.count < 150 && !TextSectionParser.looksLikeIngredient(trimmed) {
                    return trimmed
                }
            }
        }

        if let title = SocialMetadataExtractor.extractMetaContent(from: html, property: "og:title") {
            return title
        }

        if let title = SocialMetadataExtractor.extractMetaContent(from: html, name: "twitter:title") {
            return title
        }

        if let titleRange = html.range(of: "<title>"),
           let endRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
            let title = String(html[titleRange.upperBound..<endRange.lowerBound])
            return title.replacingOccurrences(of: " | TikTok", with: "").trimmingCharacters(in: .whitespaces)
        }

        return "TikTok Recipe"
    }

    func extractTikTokDescription(from html: String) throws -> String {
        var rawDescription: String?

        if let description = SocialMetadataExtractor.extractMetaContent(from: html, property: "og:description") {
            rawDescription = description
        }

        if rawDescription == nil,
           let description = SocialMetadataExtractor.extractMetaContent(from: html, name: "description") {
            rawDescription = description
        }

        if rawDescription == nil,
           let description = extractTikTokDescriptionFromEmbeddedData(html) {
            rawDescription = description
        }

        if rawDescription == nil,
           let description = extractTikTokDescriptionFromSigiState(html) {
            rawDescription = description
        }

        guard let rawDescription else {
            throw ParsingError.noRecipeFound
        }

        return cleanTikTokDescription(rawDescription)
    }

    func cleanTikTokDescription(_ description: String) -> String {
        var cleaned = description

        cleaned = unescapeUnicode(cleaned)
        cleaned = cleaned.replacingOccurrences(of: "  ", with: "\n")

        if let hashtagIndex = cleaned.firstIndex(of: "#") {
            cleaned = String(cleaned[..<hashtagIndex])
        }

        let lines = cleaned.components(separatedBy: .newlines)
        var processedLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }

            let quantityPattern = #"(\d+(?:\.\d+|/\d+)?|½|¼|¾)\s+(?:lb|lbs|oz|cup|cups|tsp|tbsp|teaspoon|tablespoon|g|kg|ml|cl|dl)\b"#
            if let regex = try? NSRegularExpression(pattern: quantityPattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))

                if matches.count > 1 {
                    var ingredients: [String] = []
                    var currentStart = trimmed.startIndex

                    for (index, match) in matches.enumerated() {
                        if index > 0, let matchRange = Range(match.range, in: trimmed) {
                            let ingredient = String(trimmed[currentStart..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                            if !ingredient.isEmpty {
                                ingredients.append(ingredient)
                            }
                            currentStart = matchRange.lowerBound
                        }
                    }

                    let lastIngredient = String(trimmed[currentStart...]).trimmingCharacters(in: .whitespaces)
                    if !lastIngredient.isEmpty {
                        ingredients.append(lastIngredient)
                    }

                    processedLines.append(contentsOf: ingredients)
                } else {
                    processedLines.append(trimmed)
                }
            } else {
                processedLines.append(trimmed)
            }
        }

        cleaned = processedLines.joined(separator: "\n")

        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unescapeUnicode(_ text: String) -> String {
        var result = text

        let pattern = #"\\u([0-9a-fA-F]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

        for match in matches.reversed() {
            if match.numberOfRanges >= 2,
               let hexRange = Range(match.range(at: 1), in: result),
               let fullRange = Range(match.range(at: 0), in: result) {
                let hexString = String(result[hexRange])
                if let num = Int(hexString, radix: 16),
                   let scalar = Unicode.Scalar(num) {
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }

        return result
    }

    func extractTikTokThumbnailURL(from html: String) -> URL? {
        if let imageURL = SocialMetadataExtractor.extractMetaContent(from: html, property: "og:image") {
            return URL(string: imageURL)
        }

        if let imageURL = SocialMetadataExtractor.extractMetaContent(from: html, name: "twitter:image") {
            return URL(string: imageURL)
        }

        if let imageURL = extractTikTokImageFromEmbeddedData(html) {
            return URL(string: imageURL)
        }

        return nil
    }

    func extractTikTokImageFromEmbeddedData(_ html: String) -> String? {
        let patterns = [
            #""cover":\s*"(https?://[^"\\]+)""#,
            #""dynamicCover":\s*"(https?://[^"\\]+)""#,
            #""originCover":\s*"(https?://[^"\\]+)""#,
            #""thumbnail":\s*"(https?://[^"\\]+)""#,
            #""imageURL":\s*"(https?://[^"\\]+)""#,
            #""coverUrl":\s*"(https?://[^"\\]+)""#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges >= 2,
               let urlRange = Range(match.range(at: 1), in: html) {
                var imageURL = String(html[urlRange])
                imageURL = imageURL.replacingOccurrences(of: "\\/", with: "/")
                imageURL = unescapeUnicode(imageURL)
                return imageURL
            }
        }

        return nil
    }

    func extractTikTokDescriptionFromEmbeddedData(_ html: String) -> String? {
        let pattern = #""desc":\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges >= 2,
              let descRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        var description = String(html[descRange])
        description = description.replacingOccurrences(of: "\\\"", with: "\"")
        description = description.replacingOccurrences(of: "\\\\", with: "\\")
        description = description.replacingOccurrences(of: "\\n", with: "\n")
        description = description.replacingOccurrences(of: "\\r", with: "\r")
        description = description.replacingOccurrences(of: "\\t", with: "\t")

        return description.isEmpty ? nil : description
    }

    func extractTikTokDescriptionFromSigiState(_ html: String) -> String? {
        guard let stateRange = html.range(of: "SIGI_STATE") ?? html.range(of: "__UNIVERSAL_DATA_FOR_REHYDRATION__") else {
            return nil
        }

        let substring = String(html[stateRange.upperBound...])
        let pattern = #""desc":\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: substring, range: NSRange(substring.startIndex..., in: substring)),
              match.numberOfRanges >= 2,
              let descRange = Range(match.range(at: 1), in: substring) else {
            return nil
        }

        var description = String(substring[descRange])
        description = description.replacingOccurrences(of: "\\\"", with: "\"")
        description = description.replacingOccurrences(of: "\\\\", with: "\\")
        description = description.replacingOccurrences(of: "\\n", with: "\n")
        description = description.replacingOccurrences(of: "\\r", with: "\r")
        description = description.replacingOccurrences(of: "\\t", with: "\t")
        description = description.replacingOccurrences(of: "\\u0026", with: "&")

        return description.isEmpty ? nil : description
    }
}
