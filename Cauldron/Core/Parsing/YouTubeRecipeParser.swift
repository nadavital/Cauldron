import Foundation

/// Parser for extracting recipes from YouTube video descriptions
actor YouTubeRecipeParser: RecipeParser {
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
        guard let normalizedURL = PlatformDetector.normalizeYouTubeURL(urlString),
              let url = URL(string: normalizedURL) else {
            throw ParsingError.invalidURL
        }

        // Fetch HTML content
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParsingError.invalidHTML
        }

        // Extract video metadata
        let videoTitle = try extractVideoTitle(from: html)
        let description = try extractDescription(from: html)
        let thumbnailURL = try? extractThumbnail(from: html)

        // Validate that description contains recipe-like content
        guard descriptionLooksLikeRecipe(description) else {
            throw ParsingError.noRecipeFound
        }

        let normalizedDescription = description.replacingOccurrences(of: "\\n", with: "\n")
        let lines = normalizedDescription
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
    private func extractVideoTitle(from html: String) throws -> String {
        // Strategy 1: Try meta tag
        if let title = extractMetaContent(from: html, property: "og:title") {
            return title
        }

        // Strategy 2: Try title tag
        if let titleRange = html.range(of: "<title>"),
           let endRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
            let title = String(html[titleRange.upperBound..<endRange.lowerBound])
            // Remove " - YouTube" suffix
            return title.replacingOccurrences(of: " - YouTube", with: "").trimmingCharacters(in: .whitespaces)
        }

        return "YouTube Recipe"
    }

    /// Extracts video description from HTML using multiple strategies
    private func extractDescription(from html: String) throws -> String {
        // Strategy 1: Extract from ytInitialData JSON FIRST (most complete)
        if let description = extractFromYtInitialData(html) {
            print("📝 YouTube Parser: Extracted description from ytInitialData, length: \(description.count)")
            // Ignore if it's just a truncated preview (ends with "...")
            if !description.hasSuffix("...") {
                print("✅ YouTube Parser: Using ytInitialData description (not truncated)")
                return description
            } else {
                print("⚠️ YouTube Parser: ytInitialData description is truncated, trying other methods")
            }
        } else {
            print("❌ YouTube Parser: Failed to extract from ytInitialData")
        }

        // Strategy 2: Try meta description tag (often truncated)
        if let description = extractMetaContent(from: html, name: "description"),
           !description.isEmpty, !description.hasSuffix("...") {
            print("✅ YouTube Parser: Using meta description tag")
            return description
        }

        // Strategy 3: Try Open Graph description (also often truncated)
        if let description = extractMetaContent(from: html, property: "og:description"),
           !description.isEmpty, !description.hasSuffix("...") {
            print("✅ YouTube Parser: Using og:description")
            return description
        }

        // If all we got were truncated descriptions, throw an error
        print("❌ YouTube Parser: All extraction methods failed or returned truncated content")
        throw ParsingError.noRecipeFound
    }

    /// Extracts thumbnail URL from HTML
    private func extractThumbnail(from html: String) throws -> String {
        // Try Open Graph image
        if let thumbnail = extractMetaContent(from: html, property: "og:image") {
            return thumbnail
        }

        // Fallback: Construct from video ID if possible
        // YouTube thumbnail format: https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg
        throw ParsingError.imageNotFound
    }

    // MARK: - Recipe Text Parsing

    /// Parse recipe from freeform description text
    /// Uses the same logic-based approach as HTMLRecipeParser (no AI)
    private func parseRecipeFromDescription(_ text: String) -> (ingredients: [Ingredient], steps: [CookStep]) {
        // Replace escaped newlines (\n) with actual newlines if they exist
        let normalizedText = text.replacingOccurrences(of: "\\n", with: "\n")

        let lines = normalizedText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        print("📝 Parsing description with \(lines.count) lines")
        print("📝 First 10 lines:")
        for (index, line) in lines.prefix(10).enumerated() {
            print("  Line \(index): \(line)")
        }

        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []
        var inIngredientsSection = false
        var inStepsSection = false

        for line in lines {
            let lowercased = line.lowercased()

            // Detect section headers
            if lowercased.contains("ingredient") && lowercased.count < 50 {
                inIngredientsSection = true
                inStepsSection = false
                continue
            } else if lowercased.contains("instruction") ||
                      lowercased.contains("direction") ||
                      lowercased.contains("method") ||
                      lowercased.contains("how to") ||
                      lowercased.hasPrefix("preparation") ||
                      (lowercased.contains("step") && lowercased.count < 50) {
                inIngredientsSection = false
                inStepsSection = true
                continue
            }

            // Check for numbered steps (e.g., "1.", "2)", "3 -")
            if TextSectionParser.looksLikeNumberedStep(line) {
                let timers = TimerExtractor.extractTimers(from: line)
                let step = CookStep(
                    id: UUID(),
                    index: steps.count,
                    text: line,
                    timers: timers
                )
                steps.append(step)
                // Numbered steps indicate we're in a steps section
                inIngredientsSection = false
                inStepsSection = true
                continue
            }

            // Parse based on current section
            if inIngredientsSection {
                // Parse as ingredient using shared utility
                let ingredient = IngredientParser.parseIngredientText(line)
                if !ingredient.name.isEmpty {
                    ingredients.append(ingredient)
                }
            } else if inStepsSection {
                // Parse as step if it's substantial text
                if line.count > 10 {
                    let timers = TimerExtractor.extractTimers(from: line)
                    let step = CookStep(
                        id: UUID(),
                        index: steps.count,
                        text: line,
                        timers: timers
                    )
                    steps.append(step)
                }
            } else {
                // Auto-detect: lines that look like ingredients (start with number or common amounts)
                if TextSectionParser.looksLikeIngredient(line) {
                    let ingredient = IngredientParser.parseIngredientText(line)
                    if !ingredient.name.isEmpty {
                        ingredients.append(ingredient)
                    }
                }
                // Lines that are substantial and don't look like ingredients might be steps
                else if line.count > 10 && !TextSectionParser.looksLikeIngredient(line) {
                    let timers = TimerExtractor.extractTimers(from: line)
                    let step = CookStep(
                        id: UUID(),
                        index: steps.count,
                        text: line,
                        timers: timers
                    )
                    steps.append(step)
                }
            }
        }

        return (ingredients, steps)
    }

    // Note: Parsing methods have been extracted to shared utilities:
    // - TextSectionParser.looksLikeNumberedStep()
    // - TextSectionParser.looksLikeIngredient()
    // - IngredientParser.parseIngredientText()
    // - IngredientParser.extractQuantityAndUnit()
    // - QuantityValueParser.parse()
    // - UnitParser.parse()

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

    /// Extracts description from ytInitialData JSON object
    private func extractFromYtInitialData(_ html: String) -> String? {
        // NEW APPROACH: Try to extract just the description text using regex pattern matching
        // Look for the attributedDescriptionBodyText.content field directly in the HTML
        let descriptionPattern = #""attributedDescriptionBodyText":\{"content":"((?:[^"\\]|\\.)*)""#
        if let regex = try? NSRegularExpression(pattern: descriptionPattern, options: []),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           match.numberOfRanges >= 2 {
            let nsString = html as NSString
            let descRange = match.range(at: 1)
            var rawDescription = nsString.substring(with: descRange)

            // Unescape JSON escape sequences (\n, \", \\, etc.)
            rawDescription = rawDescription.replacingOccurrences(of: "\\\"", with: "\"")
            rawDescription = rawDescription.replacingOccurrences(of: "\\\\", with: "\\")
            rawDescription = rawDescription.replacingOccurrences(of: "\\n", with: "\n")
            rawDescription = rawDescription.replacingOccurrences(of: "\\r", with: "\r")
            rawDescription = rawDescription.replacingOccurrences(of: "\\t", with: "\t")

            if !rawDescription.isEmpty {
                print("✅ Extracted description using regex pattern, length: \(rawDescription.count)")
                return rawDescription
            }
        }

        // FALLBACK: Original full JSON parsing approach
        print("⚠️ Regex extraction failed, trying full JSON parse")

        // Look for ytInitialData JSON
        guard let startRange = html.range(of: "var ytInitialData = ") else {
            print("❌ Could not find 'var ytInitialData = ' in HTML")
            return nil
        }

        let startIndex = startRange.upperBound

        // Extract a large chunk that should contain the complete JSON
        // Look for the next script tag or large marker
        let substring = html[startIndex...]
        guard let endMarker = substring.range(of: "</script>") else {
            print("❌ Could not find </script> tag")
            return nil
        }

        // Get the chunk up to the script end
        var potentialJSON = String(substring[..<endMarker.lowerBound])
        print("📏 Extracted potential JSON chunk: \(potentialJSON.count) chars")

        // Check what the first character is - sometimes there's a quote or other character
        let firstChars = String(potentialJSON.prefix(20))
        print("📝 First 20 chars: \(firstChars)")

        // If the JSON is wrapped in quotes, unwrap it first (before unescaping)
        if potentialJSON.hasPrefix("'") {
            potentialJSON = String(potentialJSON.dropFirst())
            print("📝 Removed leading quote, new length: \(potentialJSON.count)")
        }

        // Remove trailing semicolon and/or quote
        if potentialJSON.hasSuffix(";'") {
            potentialJSON = String(potentialJSON.dropLast(2))
            print("📝 Removed trailing ;', new length: \(potentialJSON.count)")
        } else if potentialJSON.hasSuffix("'") {
            potentialJSON = String(potentialJSON.dropLast())
            print("📝 Removed trailing ', new length: \(potentialJSON.count)")
        } else if potentialJSON.hasSuffix(";") {
            potentialJSON = String(potentialJSON.dropLast())
            print("📝 Removed trailing ;, new length: \(potentialJSON.count)")
        }

        // Check if the JSON is escaped with \x hex sequences
        var jsonString = potentialJSON
        if jsonString.hasPrefix("\\x") {
            print("📝 Detected hex-escaped JSON, unescaping...")
            jsonString = unescapeHexString(jsonString)
            print("📝 After unescaping, length: \(jsonString.count)")
        }

        // Trim any trailing whitespace, semicolons, or quotes
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any trailing semicolons or quotes (in case hex-unescaping revealed more)
        while jsonString.hasSuffix(";") || jsonString.hasSuffix("'") {
            jsonString = String(jsonString.dropLast())
        }

        // Try to parse it
        guard let data = jsonString.data(using: .utf8) else {
            print("❌ Could not convert JSON string to UTF-8 data")
            return nil
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ JSON is not a dictionary")
                return nil
            }

            print("✅ Successfully parsed ytInitialData JSON (\(jsonString.count) chars)")
            print("🔑 Top-level keys in JSON: \(json.keys.sorted().joined(separator: ", "))")

            // Try multiple paths to find the description
            if let description = extractDescriptionFromStructuredContent(json) {
                print("✅ Extracted description via structuredContent path")
                return description
            }
            if let description = extractDescriptionFromEngagementPanels(json) {
                print("✅ Extracted description via engagementPanels path")
                return description
            }
            if let description = extractDescriptionFromTwoColumn(json) {
                print("✅ Extracted description via twoColumn path")
                return description
            }

            print("❌ No description found in ytInitialData JSON with keys: \(json.keys.sorted().joined(separator: ", "))")
            return nil
        } catch {
            print("❌ Could not parse JSON")
            // Log samples and last character info
            let startSample = String(jsonString.prefix(200))
            let endSample = String(jsonString.suffix(200))
            let lastChar = jsonString.last.map { String($0) } ?? "none"
            print("📝 First 200 chars: \(startSample)")
            print("📝 Last 200 chars: \(endSample)")
            print("📝 Last character: '\(lastChar)' (should be '}')")
            print("📝 Total length: \(jsonString.count)")

            // Try to extract error position from NSCocoaErrorDomain error
            if let nsError = error as NSError?,
               let errorIndex = nsError.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                print("📝 Error at index: \(errorIndex)")

                // Show context around the error (200 chars before and after)
                let startIndex = max(0, errorIndex - 200)
                let endIndex = min(jsonString.count, errorIndex + 200)

                let startPos = jsonString.index(jsonString.startIndex, offsetBy: startIndex)
                let endPos = jsonString.index(jsonString.startIndex, offsetBy: endIndex)
                let errorContext = String(jsonString[startPos..<endPos])

                print("📝 Context around error (±200 chars):")
                print(errorContext)
            }

            // Check if there are still hex sequences
            let hexPattern = #"\\x[0-9A-Fa-f]{2}"#
            let hexRegex = try? NSRegularExpression(pattern: hexPattern)
            let hexMatches = hexRegex?.matches(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)) ?? []
            print("📝 Remaining \\x sequences: \(hexMatches.count)")

            // Try to write to temp file for inspection
            let tempPath = NSTemporaryDirectory() + "ytInitialData_debug.json"
            try? jsonString.write(toFile: tempPath, atomically: true, encoding: .utf8)
            print("📝 Written debug JSON to: \(tempPath)")

            // Log the actual error
            print("📝 JSON parse error: \(error)")

            return nil
        }
    }

    private func extractDescriptionFromEngagementPanels(_ json: [String: Any]) -> String? {
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

            // Try older format
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

    private func extractDescriptionFromTwoColumn(_ json: [String: Any]) -> String? {
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

    private func extractDescriptionFromStructuredContent(_ json: [String: Any]) -> String? {
        print("🔍 Checking for structuredDescriptionContentRenderer...")

        guard let engagementPanels = json["engagementPanels"] as? [[String: Any]] else {
            print("❌ No engagementPanels found")
            return nil
        }

        print("✅ Found \(engagementPanels.count) engagement panels")

        for (panelIndex, panel) in engagementPanels.enumerated() {
            guard let renderer = panel["engagementPanelSectionListRenderer"] as? [String: Any] else {
                continue
            }

            guard let content = renderer["content"] as? [String: Any] else {
                continue
            }

            print("  Panel \(panelIndex) content keys: \(content.keys.joined(separator: ", "))")

            guard let structured = content["structuredDescriptionContentRenderer"] as? [String: Any] else {
                continue
            }

            print("  ✅ Found structuredDescriptionContentRenderer in panel \(panelIndex)")

            guard let items = structured["items"] as? [[String: Any]] else {
                print("  ❌ No items in structuredDescriptionContentRenderer")
                continue
            }

            print("  ✅ Found \(items.count) items")

            var description = ""
            for (itemIndex, item) in items.enumerated() {
                print("    Item \(itemIndex) keys: \(item.keys.joined(separator: ", "))")

                // Try to get description from expandableVideoDescriptionBodyRenderer
                if let bodyRenderer = item["expandableVideoDescriptionBodyRenderer"] as? [String: Any] {
                    print("    ✅ Found expandableVideoDescriptionBodyRenderer")

                    // Check for attributedDescriptionBodyText with direct content string
                    if let attributedDescription = bodyRenderer["attributedDescriptionBodyText"] as? [String: Any] {
                        print("      ✅ Found attributedDescriptionBodyText")
                        if let textContent = attributedDescription["content"] as? String {
                            print("      ✅ Extracted content, length: \(textContent.count)")
                            description += textContent
                        } else {
                            print("      ❌ No 'content' field in attributedDescriptionBodyText")
                        }
                    }
                    // Also try descriptionBodyText with runs array (older format)
                    else if let descriptionBodyText = bodyRenderer["descriptionBodyText"] as? [String: Any],
                            let runs = descriptionBodyText["runs"] as? [[String: Any]] {
                        print("      ✅ Using descriptionBodyText with runs")
                        description += runs.compactMap { $0["text"] as? String }.joined()
                    }
                }

                // Also try videoDescriptionHeaderRenderer for any header content
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
                print("  ✅ Returning description, total length: \(description.count)")
                return description
            }
        }

        print("❌ No description found in any panel")
        return nil
    }

    /// Unescapes hex-encoded strings like \x7b -> {
    private func unescapeHexString(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if index < text.index(text.endIndex, offsetBy: -3),
               text[index] == "\\",
               text[text.index(after: index)] == "x" {
                // Found \x pattern
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

    /// Generic regex extraction helper
    private func extractWithRegex(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let captured = String(text[range])
        return HTMLEntityDecoder.decode(captured, stripTags: false)
    }

    /// Checks if description text looks like it contains a recipe
    private func descriptionLooksLikeRecipe(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Check for recipe-related keywords
        let recipeKeywords = [
            "ingredient", "cup", "tablespoon", "teaspoon", "tbsp", "tsp",
            "oven", "bake", "cook", "recipe", "mix", "stir", "add",
            "flour", "sugar", "salt", "pepper", "oil", "butter", "water",
            "onion", "garlic", "carrot", "celery", "beef", "chicken", "pork",
            "roast", "saute", "simmer", "boil", "chop", "slice", "dice"
        ]

        let keywordCount = recipeKeywords.filter { lowercased.contains($0) }.count

        // Require at least 2 recipe-related keywords (lowered from 3 to be more lenient)
        // This allows for shorter descriptions or descriptions with less common cooking terms
        return keywordCount >= 2
    }

    // Note: HTML entity decoding now handled by HTMLEntityDecoder utility
}
