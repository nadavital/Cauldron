import Foundation

/// Parser for extracting recipes from TikTok videos
actor TikTokRecipeParser: RecipeParser {
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

        // Extract video metadata
        let description = try extractDescription(from: html)

        let videoTitle = extractVideoTitle(from: html, description: description)
        let thumbnailURL = try? extractThumbnail(from: html)

        // Validate that description contains recipe-like content
        guard descriptionLooksLikeRecipe(description) else {
            throw ParsingError.noRecipeFound
        }

        let lines = description
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let recipe = try await textParser.parse(
            lines: lines,
            sourceURL: URL(string: urlString),
            sourceTitle: videoTitle,
            imageURL: thumbnailURL.flatMap { URL(string: $0) },
            tags: [],
            preferredTitle: videoTitle,
            yieldsOverride: nil,
            totalMinutesOverride: nil
        )

        return recipe
    }

    // MARK: - Extraction Methods

    /// Extracts video title from HTML
    private func extractVideoTitle(from html: String, description: String? = nil) -> String {
        // If we have description, try to extract a good title from first line
        if let description = description {
            let lines = description.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.count > 10 && trimmed.count < 150 {
                    // Skip lines that look like ingredients
                    if !TextSectionParser.looksLikeIngredient(trimmed) {
                        return trimmed
                    }
                }
            }
        }

        // Strategy 1: Try meta tag for og:title
        if let title = extractMetaContent(from: html, property: "og:title") {
            return title
        }

        // Strategy 2: Try twitter:title meta tag
        if let title = extractMetaContent(from: html, name: "twitter:title") {
            return title
        }

        // Strategy 3: Try title tag
        if let titleRange = html.range(of: "<title>"),
           let endRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
            let title = String(html[titleRange.upperBound..<endRange.lowerBound])
            // Remove TikTok suffix
            return title.replacingOccurrences(of: " | TikTok", with: "").trimmingCharacters(in: .whitespaces)
        }

        return "TikTok Recipe"
    }

    /// Extracts video description from HTML
    private func extractDescription(from html: String) throws -> String {
        var rawDescription: String?

        // Strategy 1: Try og:description meta tag
        if let description = extractMetaContent(from: html, property: "og:description") {
            rawDescription = description
        }

        // Strategy 2: Try description meta tag
        if rawDescription == nil, let description = extractMetaContent(from: html, name: "description") {
            rawDescription = description
        }

        // Strategy 3: Extract from TikTok's embedded JSON data
        if rawDescription == nil, let description = extractFromEmbeddedData(html) {
            rawDescription = description
        }

        // Strategy 4: Extract from SIGI_STATE (TikTok's state object)
        if rawDescription == nil, let description = extractFromSigiState(html) {
            rawDescription = description
        }

        guard var description = rawDescription else {
            throw ParsingError.noRecipeFound
        }

        // Clean and format the description
        description = cleanTikTokDescription(description)
        return description
    }

    /// Cleans TikTok description by removing hashtags, unescaping unicode, and formatting
    private func cleanTikTokDescription(_ description: String) -> String {
        var cleaned = description

        // Unescape Unicode sequences like \u002F -> /
        cleaned = unescapeUnicode(cleaned)

        // TikTok descriptions sometimes have double spaces instead of newlines
        // Convert double+ spaces to newlines for better parsing
        cleaned = cleaned.replacingOccurrences(of: "  ", with: "\n")

        // Remove hashtags (everything from first # to end)
        if let hashtagIndex = cleaned.firstIndex(of: "#") {
            cleaned = String(cleaned[..<hashtagIndex])
        }

        // Split into lines
        let lines = cleaned.components(separatedBy: .newlines)

        // Process each line to split multiple ingredients on same line
        var processedLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }

            // Check if this line has multiple quantity patterns (likely multiple ingredients on one line)
            // Pattern to match: number/fraction + space + unit
            let quantityPattern = #"(\d+(?:\.\d+|/\d+)?|½|¼|¾)\s+(?:lb|lbs|oz|cup|cups|tsp|tbsp|teaspoon|tablespoon|g|kg|ml|cl|dl)\b"#
            if let regex = try? NSRegularExpression(pattern: quantityPattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))

                if matches.count > 1 {
                    // Multiple quantities found - split by finding the start of each quantity
                    var ingredients: [String] = []
                    var currentStart = trimmed.startIndex

                    for (index, match) in matches.enumerated() {
                        if index > 0, let matchRange = Range(match.range, in: trimmed) {
                            // Extract previous ingredient (from currentStart to start of this match)
                            let ingredient = String(trimmed[currentStart..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                            if !ingredient.isEmpty {
                                ingredients.append(ingredient)
                            }
                            currentStart = matchRange.lowerBound
                        }
                    }

                    // Add the last ingredient
                    let lastIngredient = String(trimmed[currentStart...]).trimmingCharacters(in: .whitespaces)
                    if !lastIngredient.isEmpty {
                        ingredients.append(lastIngredient)
                    }

                    // Add all split ingredients
                    processedLines.append(contentsOf: ingredients)
                } else {
                    // Single or no quantity - add line as-is
                    processedLines.append(trimmed)
                }
            } else {
                processedLines.append(trimmed)
            }
        }

        cleaned = processedLines.joined(separator: "\n")

        // Clean up multiple consecutive newlines
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Unescapes Unicode sequences like \u002F
    private func unescapeUnicode(_ text: String) -> String {
        var result = text

        // Pattern to match \uXXXX
        let pattern = #"\\u([0-9a-fA-F]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

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

        return result
    }

    /// Extracts thumbnail URL from HTML
    private func extractThumbnail(from html: String) throws -> String {
        // Try og:image meta tag
        if let imageURL = extractMetaContent(from: html, property: "og:image") {
            return imageURL
        }

        // Try twitter:image meta tag
        if let imageURL = extractMetaContent(from: html, name: "twitter:image") {
            return imageURL
        }

        // Try to extract from JSON embedded data
        if let imageURL = extractImageFromEmbeddedData(html) {
            return imageURL
        }

        throw ParsingError.imageNotFound
    }

    /// Extracts image URL from TikTok's embedded JSON data
    private func extractImageFromEmbeddedData(_ html: String) -> String? {
        // Try to find video cover/thumbnail in embedded JSON
        // TikTok uses various patterns like "cover", "dynamicCover", "originCover"
        let patterns = [
            #""cover":\s*"(https?://[^"\\]+)"#,
            #""dynamicCover":\s*"(https?://[^"\\]+)"#,
            #""originCover":\s*"(https?://[^"\\]+)"#,
            #""thumbnail":\s*"(https?://[^"\\]+)"#,
            #""imageURL":\s*"(https?://[^"\\]+)"#,
            #""coverUrl":\s*"(https?://[^"\\]+)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges >= 2 {
                let nsString = html as NSString
                let urlRange = match.range(at: 1)
                var imageURL = nsString.substring(with: urlRange)

                // Unescape URL (e.g., \/ -> /)
                imageURL = imageURL.replacingOccurrences(of: "\\/", with: "/")
                imageURL = unescapeUnicode(imageURL)

                return imageURL
            }
        }

        return nil
    }

    // MARK: - Recipe Parsing

    /// Checks if the description text looks like a recipe
    private func descriptionLooksLikeRecipe(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Check for recipe keywords
        let recipeKeywords = ["ingredients", "recipe", "directions", "instructions", "steps",
                             "cup", "cups", "tablespoon", "teaspoon", "tbsp", "tsp",
                             "bake", "cook", "mix", "stir", "combine", "blend"]

        let keywordCount = recipeKeywords.filter { lowercased.contains($0) }.count
        return keywordCount >= 2
    }

    /// Parses ingredients and steps from description text
    private func parseRecipeFromDescription(_ description: String) -> ([Ingredient], [CookStep]) {
        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []

        let lines = description.components(separatedBy: .newlines)

        var inIngredientsSection = false
        var inStepsSection = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }

            // Check for section headers (use trimmed line, not cleaned)
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
                // Parse as ingredient - don't clean the line, numbers are important!
                let ingredient = IngredientParser.parseIngredientText(trimmedLine)
                if !ingredient.name.isEmpty {
                    ingredients.append(ingredient)
                }
            } else if inStepsSection {
                // Parse as step if it's substantial text
                // Clean emoji bullets from steps
                let cleanedLine = cleanLine(trimmedLine)
                if cleanedLine.count > 10 {
                    let timers = TimerExtractor.extractTimers(from: cleanedLine)
                    let step = CookStep(
                        id: UUID(),
                        index: steps.count,
                        text: cleanedLine,
                        timers: timers
                    )
                    steps.append(step)
                }
            } else {
                // Auto-detect: lines that look like ingredients (don't clean - preserve numbers!)
                if TextSectionParser.looksLikeIngredient(trimmedLine) {
                    let ingredient = IngredientParser.parseIngredientText(trimmedLine)
                    if !ingredient.name.isEmpty {
                        ingredients.append(ingredient)
                    }
                }
                // Lines that are substantial and don't look like ingredients might be steps
                // But exclude promotional/non-recipe content
                else if trimmedLine.count > 10 && !TextSectionParser.looksLikeIngredient(trimmedLine) && !isNonRecipeContent(trimmedLine) {
                    // Clean emoji bullets from steps
                    let cleanedLine = cleanLine(trimmedLine)
                    let timers = TimerExtractor.extractTimers(from: cleanedLine)
                    let step = CookStep(
                        id: UUID(),
                        index: steps.count,
                        text: cleanedLine,
                        timers: timers
                    )
                    steps.append(step)
                }
            }
        }

        return (ingredients, steps)
    }

    /// Checks if a line is non-recipe content (title, shoutout, etc.)
    private func isNonRecipeContent(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Filter out promotional/social content
        let patterns = [
            "shoutout",
            "check out",
            "follow",
            "@",  // Mentions
            "recipe you'll need",  // Often in titles
            "only .* recipe",  // Pattern like "the only mac and cheese recipe"
        ]

        for pattern in patterns {
            if lowercased.contains(pattern) {
                return true
            }
        }

        return false
    }

    /// Cleans common TikTok formatting from lines (emoji bullets, etc.)
    private func cleanLine(_ line: String) -> String {
        var cleaned = line

        // Remove common emoji bullets at the start
        let emojiPattern = "^[\\p{Emoji}\\p{Emoji_Presentation}\\p{Emoji_Component}]+\\s*"
        if let regex = try? NSRegularExpression(pattern: emojiPattern, options: []) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Remove common bullet points and list markers
        let bulletPatterns = ["^[•●○■□▪▫–—-]\\s*", "^\\*\\s+", "^>\\s+"]
        for pattern in bulletPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Extracts description from TikTok's embedded JSON data
    private func extractFromEmbeddedData(_ html: String) -> String? {
        // TikTok embeds data in various JSON structures
        let pattern = #""desc":\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let nsString = html as NSString
        let descRange = match.range(at: 1)
        var description = nsString.substring(with: descRange)

        // Unescape JSON escape sequences
        description = description.replacingOccurrences(of: "\\\"", with: "\"")
        description = description.replacingOccurrences(of: "\\\\", with: "\\")
        description = description.replacingOccurrences(of: "\\n", with: "\n")
        description = description.replacingOccurrences(of: "\\r", with: "\r")
        description = description.replacingOccurrences(of: "\\t", with: "\t")

        return description.isEmpty ? nil : description
    }

    /// Extracts description from TikTok's SIGI_STATE object
    private func extractFromSigiState(_ html: String) -> String? {
        // Look for SIGI_STATE or __UNIVERSAL_DATA_FOR_REHYDRATION__
        guard let stateRange = html.range(of: "SIGI_STATE") ?? html.range(of: "__UNIVERSAL_DATA_FOR_REHYDRATION__") else {
            return nil
        }

        // Extract a large chunk after the state marker
        let startIndex = stateRange.upperBound
        let substring = String(html[startIndex...])

        // Look for description field in the JSON
        let pattern = #""desc":\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: substring, range: NSRange(substring.startIndex..., in: substring)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        let nsString = substring as NSString
        let descRange = match.range(at: 1)
        var description = nsString.substring(with: descRange)

        // Unescape JSON escape sequences
        description = description.replacingOccurrences(of: "\\\"", with: "\"")
        description = description.replacingOccurrences(of: "\\\\", with: "\\")
        description = description.replacingOccurrences(of: "\\n", with: "\n")
        description = description.replacingOccurrences(of: "\\r", with: "\r")
        description = description.replacingOccurrences(of: "\\t", with: "\t")
        description = description.replacingOccurrences(of: "\\u0026", with: "&")

        return description.isEmpty ? nil : description
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
}
