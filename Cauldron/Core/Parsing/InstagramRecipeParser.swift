import Foundation

/// Parser for extracting recipes from Instagram posts and reels
actor InstagramRecipeParser: RecipeParser {
    private let foundationModelsService: FoundationModelsService
    private let textParser: any ModelRecipeTextParsing

    init(
        foundationModelsService: FoundationModelsService,
        textParser: any ModelRecipeTextParsing = TextRecipeParser()
    ) {
        self.foundationModelsService = foundationModelsService
        self.textParser = textParser
    }

    func parse(from urlString: String) async throws -> Recipe {
        // Normalize URL to standard format
        guard let url = URL(string: urlString) else {
            throw ParsingError.invalidURL
        }

        // Fetch HTML content
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParsingError.invalidHTML
        }

        // Extract post metadata
        let caption = try extractCaption(from: html)
        let postTitle = extractPostTitle(from: html, caption: caption)
        let thumbnailURL = try? extractThumbnail(from: html)

        // Validate that caption contains recipe-like content
        guard descriptionLooksLikeRecipe(caption) else {
            throw ParsingError.noRecipeFound
        }

        let lines = caption
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let recipe = try await textParser.parse(
            lines: lines,
            sourceURL: URL(string: urlString),
            sourceTitle: postTitle,
            imageURL: thumbnailURL.flatMap { URL(string: $0) },
            tags: [],
            preferredTitle: postTitle,
            yieldsOverride: nil,
            totalMinutesOverride: nil
        )

        return recipe
    }

    // MARK: - Extraction Methods

    /// Extracts post title from HTML
    private func extractPostTitle(from html: String, caption: String? = nil) -> String {
        // If we have the caption, use the first line or first sentence as title
        if let caption = caption {
            let lines = caption.components(separatedBy: .newlines)

            // Find first non-empty line that doesn't look like an ingredient
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

                // Skip empty lines
                if trimmed.isEmpty {
                    continue
                }

                // Skip lines that look like ingredients (start with numbers)
                if TextSectionParser.looksLikeIngredient(trimmed) {
                    continue
                }

                // Skip lines that are too short or too long
                if trimmed.count < 10 || trimmed.count > 150 {
                    continue
                }

                // This looks like a good title - use it
                return trimmed
            }

            // Fallback: take first 60 characters of caption
            if caption.count > 60 {
                let index = caption.index(caption.startIndex, offsetBy: 60)
                return String(caption[..<index]) + "..."
            }
            return caption
        }

        return "Instagram Recipe"
    }

    /// Extracts post caption from HTML
    private func extractCaption(from html: String) throws -> String {
        var rawCaption: String?

        // Strategy 1: Try og:description meta tag
        if let description = extractMetaContent(from: html, property: "og:description") {
            rawCaption = description
        }

        // Strategy 2: Try description meta tag
        if rawCaption == nil, let description = extractMetaContent(from: html, name: "description") {
            rawCaption = description
        }

        // Strategy 3: Extract from JSON-LD structured data
        if rawCaption == nil, let caption = extractFromJsonLD(html) {
            rawCaption = caption
        }

        // Strategy 4: Extract from Instagram's embedded JSON data
        if rawCaption == nil, let caption = extractFromEmbeddedData(html) {
            rawCaption = caption
        }

        guard var caption = rawCaption else {
            throw ParsingError.noRecipeFound
        }

        // Clean up the caption
        caption = cleanInstagramCaption(caption)
        return caption
    }

    /// Cleans Instagram caption by removing metadata and unescaping HTML entities
    private func cleanInstagramCaption(_ caption: String) -> String {
        var cleaned = caption

        // Unescape HTML entities
        cleaned = unescapeHTMLEntities(cleaned)

        // Remove likes/comments prefix if present
        // Pattern: "249K likes, 212 comments - " or "123 likes - "
        let likesCommentsPattern = #"^\d+[KMB]?\s+(likes?|comments?|views?)(,\s*\d+[KMB]?\s+(likes?|comments?|views?))?\s*-\s*"#
        if let regex = try? NSRegularExpression(pattern: likesCommentsPattern, options: [.caseInsensitive]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Remove Instagram username/date prefix pattern
        // Pattern: ", - username on Month Day, Year: " or just "username on Month Day, Year: "
        // The username can contain dots, so use [\w.]+ to match it
        let patterns = [
            #"^[,\s]*-\s*[\w.]+\s+on\s+[A-Z][a-z]+\s+\d+,\s+\d{4}:\s*"#,  // With comma/dash
            #"^[\w.]+\s+on\s+[A-Z][a-z]+\s+\d+,\s+\d{4}:\s*"#  // Without comma/dash
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
                if cleaned != cleaned {
                    break
                }
            }
        }

        // Remove opening and closing quotes if present
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") {
            cleaned = String(cleaned.dropFirst())
        }
        if cleaned.hasSuffix("\"") || cleaned.hasSuffix("\".") {
            // Remove trailing quote and optional period
            if cleaned.hasSuffix("\".") {
                cleaned = String(cleaned.dropLast(2))
            } else {
                cleaned = String(cleaned.dropLast())
            }
        }

        // Remove Instagram metadata patterns (likes, comments, etc.)
        let metadataPatterns = [
            #"\d+[KMB]?\s+(likes?|comments?|views?|shares?)"#,
            #"^\d+[KMB]?\s"#,  // Leading numbers (often like counts)
            #"\s+·\s+"#        // Instagram uses · as separator
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

        // Remove hashtags at the end
        if let hashtagRange = cleaned.range(of: #"\s*#\w+"#, options: .regularExpression) {
            // Find all hashtags and remove them
            let pattern = #"\s*#[\w\s]+"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            }
        }

        // Remove lines that are just metadata or hashtags
        let lines = cleaned.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            if trimmed.isEmpty {
                return false
            }

            // Skip lines that are just numbers
            if trimmed.range(of: #"^\d+[KMB]?$"#, options: .regularExpression) != nil {
                return false
            }

            // Skip lines that are just hashtags
            if trimmed.hasPrefix("#") {
                return false
            }

            return true
        }

        cleaned = filteredLines.joined(separator: "\n")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts thumbnail URL from HTML
    private func extractThumbnail(from html: String) throws -> String {
        // Try og:image meta tag
        if let imageURL = extractMetaContent(from: html, property: "og:image") {
            // Unescape HTML entities in the URL (&amp; -> &)
            return unescapeHTMLEntities(imageURL)
        }

        // Try twitter:image meta tag
        if let imageURL = extractMetaContent(from: html, name: "twitter:image") {
            return unescapeHTMLEntities(imageURL)
        }

        throw ParsingError.imageNotFound
    }

    // MARK: - Recipe Parsing

    /// Checks if the caption text looks like a recipe
    private func descriptionLooksLikeRecipe(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Check for recipe keywords
        let recipeKeywords = ["ingredients", "recipe", "directions", "instructions", "steps",
                             "cup", "cups", "tablespoon", "teaspoon", "tbsp", "tsp",
                             "bake", "cook", "mix", "stir", "combine", "blend"]

        let keywordCount = recipeKeywords.filter { lowercased.contains($0) }.count
        return keywordCount >= 2
    }

    /// Parses ingredients and steps from caption text
    private func parseRecipeFromCaption(_ caption: String) -> ([Ingredient], [CookStep]) {
        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []

        let lines = caption.components(separatedBy: .newlines)

        var inIngredientsSection = false
        var inStepsSection = false

        for line in lines {
            var trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }

            // Clean up unit abbreviations by removing periods after common units
            // This helps the parser recognize "oz.", "tsp.", "tbsp.", etc.
            trimmedLine = cleanUnitAbbreviations(trimmedLine)

            // Check for section headers
            if TextSectionParser.isIngredientSectionHeader(trimmedLine) {
                inIngredientsSection = true
                inStepsSection = false
                continue
            } else if TextSectionParser.isStepsSectionHeader(trimmedLine) {
                inIngredientsSection = false
                inStepsSection = true
                continue
            }

            // Process lines based on current section
            if inIngredientsSection {
                // Parse as ingredient
                let ingredient = IngredientParser.parseIngredientText(trimmedLine)
                if !ingredient.name.isEmpty {
                    ingredients.append(ingredient)
                }
            } else if inStepsSection {
                // Parse as step if it's substantial text and not too short
                if trimmedLine.count > 15 && !isMetadataLine(trimmedLine) {
                    let timers = TimerExtractor.extractTimers(from: trimmedLine)
                    let step = CookStep(
                        id: UUID(),
                        index: steps.count,
                        text: trimmedLine,
                        timers: timers
                    )
                    steps.append(step)
                }
            } else {
                // Auto-detect: lines that look like ingredients
                if TextSectionParser.looksLikeIngredient(trimmedLine) {
                    let ingredient = IngredientParser.parseIngredientText(trimmedLine)
                    if !ingredient.name.isEmpty {
                        ingredients.append(ingredient)
                    }
                }
                // Lines that are substantial and don't look like ingredients might be steps
                // But exclude "to taste" lines which should be ingredients
                else if trimmedLine.count > 15 && !TextSectionParser.looksLikeIngredient(trimmedLine) && !isMetadataLine(trimmedLine) {
                    let timers = TimerExtractor.extractTimers(from: trimmedLine)
                    let step = CookStep(
                        id: UUID(),
                        index: steps.count,
                        text: trimmedLine,
                        timers: timers
                    )
                    steps.append(step)
                }
            }
        }

        return (ingredients, steps)
    }

    /// Removes periods from common unit abbreviations to help parsing
    private func cleanUnitAbbreviations(_ text: String) -> String {
        let units = ["oz", "lb", "tsp", "tbsp", "fl", "pt", "qt", "gal", "ml", "cl", "dl", "kg", "mg"]
        var cleaned = text

        for unit in units {
            // Replace "unit." with "unit " (keep the space)
            cleaned = cleaned.replacingOccurrences(of: "\(unit).", with: "\(unit) ")
        }

        return cleaned
    }

    /// Checks if a line is metadata that shouldn't be a step
    private func isMetadataLine(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Lines like "Salt to taste" or "Pepper to taste" are ingredients, not steps
        if lowercased.contains("to taste") && lowercased.count < 25 {
            return true
        }

        // Promotional/metadata patterns
        let promotionalPatterns = [
            "check out",
            "don't forget",
            "use code",
            "cookbook",
            "track your macros",
            "total macros",
            "calories:",
            "protein:",
            "carbs:",
            "fat:",
            "@"  // Social media mentions
        ]

        for pattern in promotionalPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }

        // Lines that start with emojis or special characters (often section headers)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        // Check if line is mostly just a section header (e.g., "Chicken" or "Bang Bang Sauce")
        if trimmed.count < 30 && !trimmed.contains("tsp") && !trimmed.contains("tbsp") && !trimmed.contains("cup") {
            // Could be a section header - check if it doesn't have quantities
            if !TextSectionParser.looksLikeIngredient(trimmed) && !trimmed.contains("add") && !trimmed.contains("mix") && !trimmed.contains("cook") {
                return true
            }
        }

        return false
    }

    // MARK: - Helper Methods

    /// Extracts content from meta tags by name attribute
    private func extractMetaContent(from html: String, name: String) -> String? {
        let pattern = "<meta\\s+name=\"\(name)\"\\s+content=\"([^\"]+)\""
        return extractWithRegex(html, pattern: pattern)
    }

    /// Extracts content from meta tags by property attribute
    private func extractMetaContent(from html: String, property: String) -> String? {
        let pattern = "<meta\\s+property=\"\(property)\"\\s+content=\"([^\"]+)\""
        return extractWithRegex(html, pattern: pattern)
    }

    /// Extracts caption from JSON-LD structured data
    private func extractFromJsonLD(_ html: String) -> String? {
        // Look for script tag with type="application/ld+json"
        let pattern = #"<script type="application/ld\+json">(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let nsString = html as NSString
        let jsonRange = match.range(at: 1)
        let jsonString = nsString.substring(with: jsonRange)

        // Try to parse JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let description = json["description"] as? String ?? json["caption"] as? String else {
            return nil
        }

        return description
    }

    /// Extracts caption from Instagram's embedded JSON data
    private func extractFromEmbeddedData(_ html: String) -> String? {
        // Instagram embeds data in window._sharedData or similar structures
        // This is a simplified approach - Instagram's structure changes frequently
        let pattern = #""caption":\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let nsString = html as NSString
        let captionRange = match.range(at: 1)
        var caption = nsString.substring(with: captionRange)

        // Unescape JSON escape sequences
        caption = caption.replacingOccurrences(of: "\\\"", with: "\"")
        caption = caption.replacingOccurrences(of: "\\\\", with: "\\")
        caption = caption.replacingOccurrences(of: "\\n", with: "\n")
        caption = caption.replacingOccurrences(of: "\\r", with: "\r")
        caption = caption.replacingOccurrences(of: "\\t", with: "\t")

        return caption.isEmpty ? nil : caption
    }

    /// Helper to extract text using regex pattern
    private func extractWithRegex(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let nsString = text as NSString
        let captureRange = match.range(at: 1)
        return nsString.substring(with: captureRange)
    }

    /// Unescapes HTML entities like &quot;, &amp;, &lt;, &gt;, &#39;, &#x1f525;
    private func unescapeHTMLEntities(_ text: String) -> String {
        var result = text

        // Common HTML entities
        let entities: [String: String] = [
            "&quot;": "\"",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#x27;": "'",
            "&#x2F;": "/",
            "&middot;": "·",
            "&#x2019;": "'"  // Right single quotation mark
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Handle hex entities like &#x1f525; (emojis)
        let hexPattern = "&#x([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: hexPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

            // Process matches in reverse to maintain string indices
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let hexRange = match.range(at: 1)
                    let hexString = nsString.substring(with: hexRange)
                    if let num = Int(hexString, radix: 16), let scalar = Unicode.Scalar(num) {
                        let char = String(Character(scalar))
                        let fullRange = match.range(at: 0)
                        if let swiftRange = Range(fullRange, in: result) {
                            result.replaceSubrange(swiftRange, with: char)
                        }
                    }
                }
            }
        }

        // Handle numeric entities like &#1234;
        let numericPattern = "&#(\\d+);"
        if let regex = try? NSRegularExpression(pattern: numericPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))

            // Process matches in reverse to maintain string indices
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let numRange = match.range(at: 1)
                    let numString = nsString.substring(with: numRange)
                    if let num = Int(numString), let scalar = Unicode.Scalar(num) {
                        let char = String(Character(scalar))
                        let fullRange = match.range(at: 0)
                        if let swiftRange = Range(fullRange, in: result) {
                            result.replaceSubrange(swiftRange, with: char)
                        }
                    }
                }
            }
        }

        return result
    }
}
