//
//  HTMLRecipeParser.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Parser for extracting recipes from HTML
actor HTMLRecipeParser: RecipeParser {
    
    func parse(from urlString: String) async throws -> Recipe {
        guard let url = URL(string: urlString) else {
            throw ParsingError.invalidSource
        }
        
        // Fetch HTML
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParsingError.invalidSource
        }
        
        // Try schema.org JSON-LD first
        if let recipe = try? parseSchemaOrg(html, sourceURL: url) {
            return recipe
        }
        
        // Fallback to heuristic parsing
        return try parseHeuristic(html, sourceURL: url)
    }
    
    // MARK: - Schema.org Parsing
    
    private func parseSchemaOrg(_ html: String, sourceURL: URL) throws -> Recipe? {
        // Look for JSON-LD script tags (there may be multiple)
        let jsonLDPattern = #"<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>"#
        let regex = try? NSRegularExpression(pattern: jsonLDPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        
        guard let regex = regex else { return nil }
        
        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
        
        // Try each JSON-LD block
        for match in matches {
            if match.numberOfRanges >= 2 {
                let jsonRange = match.range(at: 1)
                let jsonString = nsString.substring(with: jsonRange)
                
                if let recipe = try? parseJSONLD(jsonString, sourceURL: sourceURL) {
                    return recipe
                }
            }
        }
        
        return nil
    }
    
    private func parseJSONLD(_ jsonString: String, sourceURL: URL) throws -> Recipe? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        
        let json = try? JSONSerialization.jsonObject(with: jsonData)
        
        // Handle array of JSON-LD objects
        if let jsonArray = json as? [[String: Any]] {
            for item in jsonArray {
                if let recipe = try? parseRecipeFromJSON(item, sourceURL: sourceURL) {
                    return recipe
                }
            }
        }
        
        // Handle single JSON-LD object
        if let jsonDict = json as? [String: Any] {
            return try? parseRecipeFromJSON(jsonDict, sourceURL: sourceURL)
        }
        
        return nil
    }
    
    private func parseRecipeFromJSON(_ json: [String: Any], sourceURL: URL) throws -> Recipe? {
        // Check if this is a Recipe type
        guard let type = json["@type"] as? String,
              type.lowercased().contains("recipe") else {
            return nil
        }
        
        guard let name = json["name"] as? String else { return nil }
        
        // Parse ingredients
        var ingredients: [Ingredient] = []
        if let recipeIngredients = json["recipeIngredient"] as? [String] {
            ingredients = recipeIngredients.enumerated().map { index, text in
                parseIngredientText(text)
            }
        }
        
        // Parse steps
        var steps: [CookStep] = []
        if let instructionsArray = json["recipeInstructions"] as? [[String: Any]] {
            // HowToStep format (common in schema.org)
            steps = instructionsArray.enumerated().compactMap { index, instruction in
                if let text = instruction["text"] as? String {
                    let timers = TimerExtractor.extractTimers(from: text)
                    return CookStep(index: index, text: text, timers: timers)
                }
                return nil
            }
        } else if let instructionsArray = json["recipeInstructions"] as? [String] {
            // Simple string array
            steps = instructionsArray.enumerated().map { index, text in
                let timers = TimerExtractor.extractTimers(from: text)
                return CookStep(index: index, text: text, timers: timers)
            }
        } else if let instructionText = json["recipeInstructions"] as? String {
            // Single text block
            let lines = instructionText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            steps = lines.enumerated().map { index, text in
                let timers = TimerExtractor.extractTimers(from: text)
                return CookStep(index: index, text: text, timers: timers)
            }
        }
        
        guard !ingredients.isEmpty && !steps.isEmpty else { return nil }
        
        // Parse yields
        let yields = parseYield(json["recipeYield"])
        
        // Parse total time
        let totalTime = parseTotalTime(json["totalTime"] as? String, json["cookTime"] as? String, json["prepTime"] as? String)
        
        // Parse image URL
        let imageURL = parseImageURL(json["image"])
        
        // Parse tags/category
        var tags: [Tag] = []
        if let category = json["recipeCategory"] as? String {
            tags.append(Tag(name: category))
        }
        if let cuisine = json["recipeCuisine"] as? String {
            tags.append(Tag(name: cuisine))
        }
        if let keywords = json["keywords"] as? String {
            let keywordTags = keywords.split(separator: ",").map { Tag(name: $0.trimmingCharacters(in: .whitespaces)) }
            tags.append(contentsOf: keywordTags)
        }
        
        return Recipe(
            title: name,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalTime,
            tags: tags,
            sourceURL: sourceURL,
            sourceTitle: extractDomain(from: sourceURL),
            imageURL: imageURL
        )
    }
    
    private func parseYield(_ yieldValue: Any?) -> String {
        if let yieldString = yieldValue as? String {
            return yieldString
        } else if let yieldNumber = yieldValue as? Int {
            return "\(yieldNumber) servings"
        } else if let yieldArray = yieldValue as? [Any], let first = yieldArray.first {
            return "\(first)"
        }
        return "4 servings"
    }
    
    private func parseImageURL(_ imageValue: Any?) -> URL? {
        // Image can be a string, array of strings, or object with @type and url
        if let imageString = imageValue as? String {
            return URL(string: imageString)
        } else if let imageArray = imageValue as? [Any], let first = imageArray.first {
            if let imageString = first as? String {
                return URL(string: imageString)
            } else if let imageDict = first as? [String: Any], let url = imageDict["url"] as? String {
                return URL(string: url)
            }
        } else if let imageDict = imageValue as? [String: Any], let url = imageDict["url"] as? String {
            return URL(string: url)
        }
        return nil
    }
    
    private func parseTotalTime(_ totalTime: String?, _ cookTime: String?, _ prepTime: String?) -> Int? {
        // Try total time first
        if let total = totalTime {
            return parseDuration(total)
        }
        
        // Combine cook + prep time
        var minutes = 0
        if let cook = cookTime {
            minutes += parseDuration(cook) ?? 0
        }
        if let prep = prepTime {
            minutes += parseDuration(prep) ?? 0
        }
        
        return minutes > 0 ? minutes : nil
    }
    
    private func parseIngredientText(_ text: String) -> Ingredient {
        // Clean the text first
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        
        // Try to parse quantity and unit from the beginning of the string
        if let (quantity, remainingText) = extractQuantityAndUnit(from: cleaned) {
            let ingredientName = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
            return Ingredient(name: ingredientName.isEmpty ? cleaned : ingredientName, quantity: quantity)
        }
        
        // If parsing fails, return the whole text as ingredient name
        return Ingredient(name: cleaned, quantity: nil)
    }
    
    private func extractQuantityAndUnit(from text: String) -> (Quantity, String)? {
        // Pattern to match quantity at the start: number (possibly with fraction or unicode fraction) followed by optional unit
        // Examples: "2 cups", "1/2 cup", "1 ½ cups", "2½ tablespoons", "200g", "1-2 teaspoons"
        
        let pattern = #"^([\d\s½¼¾⅓⅔⅛⅜⅝⅞/-]+)\s*([a-zA-Z]+)?\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        
        let quantityRange = match.range(at: 1)
        let quantityText = nsString.substring(with: quantityRange).trimmingCharacters(in: .whitespaces)
        
        // Parse the value
        guard let value = parseQuantityValue(quantityText) else {
            return nil
        }
        
        // Parse the unit if present
        var unit: UnitKind? = nil
        var remainingStartIndex = quantityRange.upperBound
        
        if match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound {
            let unitRange = match.range(at: 2)
            let unitText = nsString.substring(with: unitRange)
            unit = parseUnit(unitText)
            remainingStartIndex = unitRange.upperBound
        }
        
        let remainingText = nsString.substring(from: remainingStartIndex)
        // Default to `.whole` when no explicit unit is parsed (e.g., "2 eggs")
        let quantity = Quantity(value: value, unit: unit ?? .whole)
        
        return (quantity, remainingText)
    }
    
    private func parseQuantityValue(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        
        // Convert unicode fractions to decimal
        cleaned = cleaned.replacingOccurrences(of: "½", with: "0.5")
        cleaned = cleaned.replacingOccurrences(of: "¼", with: "0.25")
        cleaned = cleaned.replacingOccurrences(of: "¾", with: "0.75")
        cleaned = cleaned.replacingOccurrences(of: "⅓", with: "0.333")
        cleaned = cleaned.replacingOccurrences(of: "⅔", with: "0.667")
        cleaned = cleaned.replacingOccurrences(of: "⅛", with: "0.125")
        cleaned = cleaned.replacingOccurrences(of: "⅜", with: "0.375")
        cleaned = cleaned.replacingOccurrences(of: "⅝", with: "0.625")
        cleaned = cleaned.replacingOccurrences(of: "⅞", with: "0.875")
        
        // Handle ranges like "1-2" - take the average
        if cleaned.contains("-") {
            let parts = cleaned.components(separatedBy: "-")
            if parts.count == 2,
               let first = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let second = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                return (first + second) / 2
            }
        }
        
        // Handle fractions like "1/2"
        if cleaned.contains("/") {
            let parts = cleaned.components(separatedBy: "/")
            if parts.count == 2,
               let numerator = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let denominator = Double(parts[1].trimmingCharacters(in: .whitespaces)),
               denominator != 0 {
                return numerator / denominator
            }
        }
        
        // Handle mixed numbers like "1 1/2" or "1.5"
        let components = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if components.count == 2 {
            if let whole = Double(components[0]),
               let fraction = parseQuantityValue(components[1]) {
                return whole + fraction
            }
        }
        
        // Try direct conversion
        return Double(cleaned)
    }
    
    private func parseUnit(_ text: String) -> UnitKind? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try exact matches first
        for unit in UnitKind.allCases {
            if normalized == unit.rawValue ||
               normalized == unit.displayName ||
               normalized == unit.pluralName {
                return unit
            }
        }
        
        // Try common abbreviations and variations
        switch normalized {
        case "t", "tsp", "tsps", "teaspoons", "teaspoon": return .teaspoon
        case "T", "tbsp", "tbsps", "tablespoons", "tablespoon": return .tablespoon
        case "c", "cups", "cup": return .cup
        case "oz", "ounces", "ounce": return .ounce
        case "lb", "lbs", "pounds", "pound": return .pound
        case "g", "grams", "gram": return .gram
        case "kg", "kgs", "kilograms", "kilogram": return .kilogram
        case "ml", "mls", "milliliters", "milliliter": return .milliliter
        case "l", "liters", "liter": return .liter
        case "pt", "pts", "pints", "pint": return .pint
        case "qt", "qts", "quarts", "quart": return .quart
        case "gal", "gals", "gallons", "gallon": return .gallon
        case "fl oz", "floz", "fluid ounce", "fluid ounces": return .fluidOunce
        default: return nil
        }
    }
    
    // MARK: - Heuristic Parsing
    
    private func parseHeuristic(_ html: String, sourceURL: URL) throws -> Recipe {
        // Extract title from <title> tag or <h1>
        var title = "Untitled Recipe"
        
        // Try <h1> first (more accurate)
        if let h1Range = html.range(of: #"<h1[^>]*>(.*?)</h1>"#, options: [.regularExpression, .caseInsensitive]) {
            let h1Text = String(html[h1Range])
            if let contentStart = h1Text.range(of: ">"),
               let contentEnd = h1Text.range(of: "</h1>", options: [.backwards, .caseInsensitive]) {
                let extracted = String(h1Text[contentStart.upperBound..<contentEnd.lowerBound])
                let cleaned = stripHTML(extracted)
                if !cleaned.isEmpty && cleaned.count < 100 {
                    title = cleaned
                }
            }
        }
        
        // Fallback to <title> tag
        if title == "Untitled Recipe",
           let titleRange = html.range(of: #"<title>(.*?)</title>"#, options: [.regularExpression, .caseInsensitive]) {
            let titleText = String(html[titleRange])
            if let contentStart = titleText.range(of: ">"),
               let contentEnd = titleText.range(of: "</title>", options: [.backwards, .caseInsensitive]) {
                let extracted = String(titleText[contentStart.upperBound..<contentEnd.lowerBound])
                title = stripHTML(extracted)
                    .replacingOccurrences(of: #" [|–-] .*$"#, with: "", options: .regularExpression) // Remove site suffix
            }
        }
        
        // Extract ingredients (try multiple patterns)
        var ingredients: [Ingredient] = []
        let ingredientPatterns = [
            #"<li[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</li>"#,
            #"<li[^>]*data-ingredient[^>]*>(.*?)</li>"#,
            #"<div[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</div>"#,
            #"<span[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</span>"#,
            #"<p[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</p>"#
        ]
        
        for pattern in ingredientPatterns {
            ingredients = extractMatches(from: html, pattern: pattern)
                .map { parseIngredientText(stripHTML($0)) }
                .filter { !$0.name.isEmpty }
            
            if !ingredients.isEmpty { break }
        }
        
        // Extract steps (try multiple patterns)
        var steps: [CookStep] = []
        let stepPatterns = [
            #"<li[^>]*class="[^"]*instruction[^"]*"[^>]*>(.*?)</li>"#,
            #"<li[^>]*class="[^"]*step[^"]*"[^>]*>(.*?)</li>"#,
            #"<li[^>]*data-step[^>]*>(.*?)</li>"#,
            #"<div[^>]*class="[^"]*instruction[^"]*"[^>]*>(.*?)</div>"#,
            #"<p[^>]*class="[^"]*step[^"]*"[^>]*>(.*?)</p>"#,
            #"<div[^>]*class="[^"]*step[^"]*"[^>]*>(.*?)</div>"#
        ]
        
        for pattern in stepPatterns {
            let stepTexts = extractMatches(from: html, pattern: pattern)
                .map { stripHTML($0) }
                .filter { !$0.isEmpty && $0.count > 10 } // Filter out very short text
            
            steps = stepTexts.enumerated().map { index, text in
                let timers = TimerExtractor.extractTimers(from: text)
                return CookStep(index: index, text: text, timers: timers)
            }
            
            if !steps.isEmpty { break }
        }
        
        guard !ingredients.isEmpty else {
            throw ParsingError.noIngredientsFound
        }
        
        guard !steps.isEmpty else {
            throw ParsingError.noStepsFound
        }
        
        // Extract image URL - try og:image meta tag first, then recipe images
        var imageURL: URL? = nil
        
        // Try Open Graph image
        let ogImagePattern = #"<meta[^>]*property="og:image"[^>]*content="([^"]*)"[^>]*>"#
        if let regex = try? NSRegularExpression(pattern: ogImagePattern, options: .caseInsensitive) {
            let nsString = html as NSString
            if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsString.length)),
               match.numberOfRanges >= 2 {
                let urlString = nsString.substring(with: match.range(at: 1))
                imageURL = URL(string: urlString)
            }
        }
        
        // Fallback to recipe image patterns
        if imageURL == nil {
            let imagePatterns = [
                #"<img[^>]*class="[^"]*recipe[^"]*image[^"]*"[^>]*src="([^"]*)"[^>]*>"#,
                #"<img[^>]*src="([^"]*)"[^>]*class="[^"]*recipe[^"]*image[^"]*"[^>]*>"#,
                #"<img[^>]*data-src="([^"]*)"[^>]*class="[^"]*recipe[^"]*"[^>]*>"#
            ]
            
            for pattern in imagePatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
                   match.numberOfRanges >= 2 {
                    let urlString = (html as NSString).substring(with: match.range(at: 1))
                    imageURL = URL(string: urlString)
                    if imageURL != nil { break }
                }
            }
        }
        
        return Recipe(
            title: title,
            ingredients: ingredients,
            steps: steps,
            sourceURL: sourceURL,
            sourceTitle: extractDomain(from: sourceURL),
            imageURL: imageURL
        )
    }
    
    private func extractMatches(from html: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        
        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
        
        return matches.compactMap { match in
            if match.numberOfRanges >= 2 {
                let range = match.range(at: 1)
                return nsString.substring(with: range)
            }
            return nil
        }
    }
    
    // MARK: - Helpers
    
    private func stripHTML(_ text: String) -> String {
        var result = text
        
        // Remove HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Decode numeric HTML entities (&#xHEX; and &#DECIMAL;)
        // Hex entities like &#x25a;
        result = decodeNumericEntities(result, pattern: "&#x([0-9A-Fa-f]+);") { hex in
            if let value = Int(hex, radix: 16), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
            return nil
        }
        
        // Decimal entities like &#32;
        result = decodeNumericEntities(result, pattern: "&#(\\d+);") { decimal in
            if let value = Int(decimal), let scalar = UnicodeScalar(value) {
                return String(Character(scalar))
            }
            return nil
        }
        
        // Decode named HTML entities
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&rsquo;", with: "'")
        result = result.replacingOccurrences(of: "&ldquo;", with: "\"")
        result = result.replacingOccurrences(of: "&rdquo;", with: "\"")
        result = result.replacingOccurrences(of: "&mdash;", with: "—")
        result = result.replacingOccurrences(of: "&ndash;", with: "–")
        result = result.replacingOccurrences(of: "&frac14;", with: "¼")
        result = result.replacingOccurrences(of: "&frac12;", with: "½")
        result = result.replacingOccurrences(of: "&frac34;", with: "¾")
        
        // Remove checkbox and other unwanted unicode characters
        // U+2610 ☐ (ballot box), U+2611 ☑ (ballot box with check), U+2612 ☒ (ballot box with X)
        // U+25A1 □ (white square), U+25A0 ■ (black square), U+25AB ▫ (white small square)
        result = result.replacingOccurrences(of: "[☐☑☒□■▫▪]", with: "", options: .regularExpression)
        
        // Remove leading bullet points and list markers
        result = result.replacingOccurrences(of: "^[•●○◦▪▫-]\\s*", with: "", options: .regularExpression)
        
        // Clean whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
    
    private func extractDomain(from url: URL) -> String {
        url.host ?? url.absoluteString
    }
    
    private func parseDuration(_ duration: String?) -> Int? {
        guard let duration = duration else { return nil }
        
        // Parse ISO 8601 duration like "PT45M" (45 minutes)
        var minutes = 0
        
        if let hourMatch = duration.range(of: #"(\d+)H"#, options: .regularExpression) {
            if let value = Int(String(duration[hourMatch]).filter { $0.isNumber }) {
                minutes += value * 60
            }
        }
        
        if let minMatch = duration.range(of: #"(\d+)M"#, options: .regularExpression) {
            if let value = Int(String(duration[minMatch]).filter { $0.isNumber }) {
                minutes += value
            }
        }
        
        return minutes > 0 ? minutes : nil
    }
}

extension String {
    func matches(of pattern: String, options: NSString.CompareOptions = []) -> [String] {
        var matches: [String] = []
        var searchRange = self.startIndex..<self.endIndex
        
        while let range = self.range(of: pattern, options: options, range: searchRange) {
            matches.append(String(self[range]))
            searchRange = range.upperBound..<self.endIndex
        }
        
        return matches
    }
}

