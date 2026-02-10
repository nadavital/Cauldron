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
        guard isRecipeType(json["@type"]) else {
            return nil
        }

        let name = cleanedString(json["name"]) ?? cleanedString(json["headline"])
        guard let name, !name.isEmpty else { return nil }
        
        // Parse ingredients
        var ingredients: [Ingredient] = []
        if let recipeIngredients = json["recipeIngredient"] as? [String] {
            ingredients = recipeIngredients.compactMap { text in
                let cleaned = cleanText(text)
                guard !cleaned.isEmpty else { return nil }
                return parseIngredientText(cleaned)
            }
        }
        
        // Parse steps
        let rawInstructions = json["recipeInstructions"] ?? json["instructions"]
        let stepTexts = rawInstructions.map { extractInstructionTexts(from: $0) } ?? []
        let steps = stepTexts.enumerated().map { index, text in
            let timers = TimerExtractor.extractTimers(from: text)
            return CookStep(index: index, text: text, timers: timers)
        }
        
        guard !ingredients.isEmpty && !steps.isEmpty else { return nil }
        
        // Parse yields
        let yields = parseYield(json["recipeYield"])
        
        // Parse total time
        let totalTime = parseTotalTime(json["totalTime"] as? String, json["cookTime"] as? String, json["prepTime"] as? String)
        
        // Parse image URL
        let imageURL = parseImageURL(json["image"], baseURL: sourceURL)
        
        // Parse tags/category
        var tags: [Tag] = []
        if let category = json["recipeCategory"] as? String {
            let cleanedCategory = cleanText(category)
            if !cleanedCategory.isEmpty {
                tags.append(Tag(name: cleanedCategory))
            }
        }
        if let cuisine = json["recipeCuisine"] as? String {
            let cleanedCuisine = cleanText(cuisine)
            if !cleanedCuisine.isEmpty {
                tags.append(Tag(name: cleanedCuisine))
            }
        }
        if let keywords = json["keywords"] as? String {
            let keywordTags = cleanText(keywords)
                .split(separator: ",")
                .map { Tag(name: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.name.isEmpty }
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
            let cleaned = cleanText(yieldString)
            return cleaned.isEmpty ? "4 servings" : cleaned
        } else if let yieldNumber = yieldValue as? Int {
            return "\(yieldNumber) servings"
        } else if let yieldArray = yieldValue as? [Any], let first = yieldArray.first {
            return cleanText("\(first)")
        }
        return "4 servings"
    }
    
    private func parseImageURL(_ imageValue: Any?, baseURL: URL) -> URL? {
        // Image can be a string, array of strings, or object with @type and url
        if let imageString = imageValue as? String {
            return normalizeURL(from: imageString, relativeTo: baseURL)
        } else if let imageArray = imageValue as? [Any], let first = imageArray.first {
            if let imageString = first as? String {
                return normalizeURL(from: imageString, relativeTo: baseURL)
            } else if let imageDict = first as? [String: Any], let url = imageDict["url"] as? String {
                return normalizeURL(from: url, relativeTo: baseURL)
            }
        } else if let imageDict = imageValue as? [String: Any], let url = imageDict["url"] as? String {
            return normalizeURL(from: url, relativeTo: baseURL)
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
        // Use shared ingredient parser utility
        return IngredientParser.parseIngredientText(text)
    }

    private func extractInstructionTexts(from value: Any) -> [String] {
        if let text = value as? String {
            return splitInstructionString(text)
        }

        if let array = value as? [Any] {
            return array.flatMap { extractInstructionTexts(from: $0) }
        }

        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String {
                return splitInstructionString(text)
            }

            if let name = dict["name"] as? String {
                return splitInstructionString(name)
            }

            if let itemList = dict["itemListElement"] {
                return extractInstructionTexts(from: itemList)
            }
        }

        return []
    }

    private func splitInstructionString(_ text: String) -> [String] {
        let cleaned = cleanText(text)
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { cleanText($0) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return lines
        }

        return cleaned
            .components(separatedBy: ". ")
            .map { cleanText($0) }
            .filter { !$0.isEmpty }
    }
    
    // Note: Parsing methods have been extracted to shared utilities:
    // - IngredientParser.extractQuantityAndUnit()
    // - QuantityValueParser.parse()
    // - UnitParser.parse()

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
        // Use shared HTML entity decoder utility (which handles tags, entities, and unicode cleanup)
        return HTMLEntityDecoder.decode(text, stripTags: true)
    }

    private func cleanText(_ text: String) -> String {
        HTMLEntityDecoder.decode(text, stripTags: true)
            .replacingOccurrences(of: "[^\\S\\n]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let cleaned = cleanText(string)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func isRecipeType(_ typeValue: Any?) -> Bool {
        if let type = typeValue as? String {
            return type.lowercased().contains("recipe")
        }

        if let typeArray = typeValue as? [String] {
            return typeArray.contains { $0.lowercased().contains("recipe") }
        }

        return false
    }

    private func normalizeURL(from raw: String, relativeTo baseURL: URL) -> URL? {
        let cleaned = cleanText(raw)
        guard !cleaned.isEmpty else { return nil }

        if let absoluteURL = URL(string: cleaned),
           let scheme = absoluteURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return absoluteURL
        }

        if cleaned.hasPrefix("//"),
           let url = URL(string: "https:\(cleaned)") {
            return url
        }

        if cleaned.hasPrefix("/"),
           let relative = URL(string: cleaned, relativeTo: baseURL) {
            return relative.absoluteURL
        }

        return nil
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
