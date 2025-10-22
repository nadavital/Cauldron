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
            guard match.numberOfRanges >= 2 else { continue }

            let jsonRange = match.range(at: 1)
            let jsonString = nsString.substring(with: jsonRange)

            if let recipe = try? parseJSONLD(jsonString, sourceURL: sourceURL) {
                return recipe
            }
        }

        return nil
    }

    private func parseJSONLD(_ jsonString: String, sourceURL: URL) throws -> Recipe? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }

        let jsonObject = try? JSONSerialization.jsonObject(with: jsonData)
        guard let candidate = extractRecipeDictionary(from: jsonObject) else { return nil }

        return try parseRecipeFromJSON(candidate, sourceURL: sourceURL)
    }

    private func parseRecipeFromJSON(_ json: [String: Any], sourceURL: URL) throws -> Recipe? {
        guard let name = (json["name"] as? String) ?? (json["headline"] as? String) else { return nil }

        let ingredientEntries = extractIngredientEntries(from: json)
        let ingredients = ingredientEntries.compactMap { parseIngredientEntry($0) }

        let instructionEntries = extractInstructionEntries(from: json)
        let steps = instructionEntries.enumerated().map { index, text in
            let timers = TimerExtractor.extractTimers(from: text)
            return CookStep(index: index, text: text, timers: timers)
        }

        guard !ingredients.isEmpty, !steps.isEmpty else { return nil }

        // Parse yields
        let yields = parseYield(json["recipeYield"] ?? json["yield"]) // Some sites use "yield"

        // Parse total time
        let totalTime = parseTotalTime(from: json)

        // Parse image URL
        let imageURL = parseImageURL(json["image"])

        // Parse tags/category
        var tagNames: [String] = []
        var seenTags = Set<String>()

        appendTags(from: json["recipeCategory"], to: &tagNames, seen: &seenTags)
        appendTags(from: json["recipeCuisine"], to: &tagNames, seen: &seenTags)
        appendTags(from: json["keywords"], to: &tagNames, seen: &seenTags)

        let tags = tagNames.map { Tag(name: $0) }

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
        switch yieldValue {
        case let yieldString as String:
            return yieldString
        case let yieldNumber as Int:
            return "\(yieldNumber) servings"
        case let yieldNumber as Double:
            return "\(Int(yieldNumber)) servings"
        case let yieldArray as [Any]:
            if let first = yieldArray.first {
                return parseYield(first)
            }
        case let yieldDict as [String: Any]:
            if let text = yieldDict["text"] as? String { return text }
            if let value = yieldDict["value"] { return parseYield(value) }
        default:
            break
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
    
    private func parseTotalTime(from json: [String: Any]) -> Int? {
        if let total = parseDurationValue(json["totalTime"]) {
            return total
        }

        var minutes = 0
        minutes += parseDurationValue(json["prepTime"]) ?? 0
        minutes += parseDurationValue(json["cookTime"]) ?? 0
        minutes += parseDurationValue(json["performTime"]) ?? 0

        return minutes > 0 ? minutes : nil
    }

    private func extractRecipeDictionary(from object: Any?) -> [String: Any]? {
        guard let object = object else { return nil }

        if let dict = object as? [String: Any] {
            if isRecipeDictionary(dict) {
                return dict
            }

            if let mainEntity = extractRecipeDictionary(from: dict["mainEntity"]) {
                return mainEntity
            }

            if let mainEntityOfPage = extractRecipeDictionary(from: dict["mainEntityOfPage"]) {
                return mainEntityOfPage
            }

            if let graph = dict["@graph"] as? [Any] {
                for node in graph {
                    if let recipe = extractRecipeDictionary(from: node) {
                        return recipe
                    }
                }
            }

            if let potentialList = dict["@list"] as? [Any] {
                for node in potentialList {
                    if let recipe = extractRecipeDictionary(from: node) {
                        return recipe
                    }
                }
            }

            if let itemList = dict["itemListElement"] as? [Any] {
                for node in itemList {
                    if let recipe = extractRecipeDictionary(from: node) {
                        return recipe
                    }
                }
            }

            return nil
        }

        if let array = object as? [Any] {
            for element in array {
                if let recipe = extractRecipeDictionary(from: element) {
                    return recipe
                }
            }
        }

        return nil
    }

    private func isRecipeDictionary(_ dict: [String: Any]) -> Bool {
        if let type = dict["@type"] {
            if let typeString = type as? String,
               typeString.lowercased().contains("recipe") {
                return true
            }

            if let typeArray = type as? [String] {
                return typeArray.contains { $0.lowercased().contains("recipe") }
            }
        }

        if let type = dict["type"] as? String,
           type.lowercased().contains("recipe") {
            return true
        }

        // Some sites omit @type but still contain recipe-specific fields
        if dict["recipeIngredient"] != nil || dict["recipeInstructions"] != nil {
            return true
        }

        return false
    }

    private func extractIngredientEntries(from json: [String: Any]) -> [Any] {
        if let ingredients = json["recipeIngredient"] {
            return normalizeToArray(ingredients)
        }

        if let ingredients = json["ingredients"] {
            return normalizeToArray(ingredients)
        }

        if let section = json["ingredient"] {
            return normalizeToArray(section)
        }

        return []
    }

    private func normalizeToArray(_ value: Any) -> [Any] {
        if let array = value as? [Any] {
            return array
        } else {
            return [value]
        }
    }

    private func parseIngredientEntry(_ entry: Any) -> Ingredient? {
        if let string = entry as? String {
            return parseIngredientText(string)
        }

        if let dict = entry as? [String: Any] {
            if let text = dict["text"] as? String {
                return parseIngredientText(text)
            }

            var note: String? = nil
            var name: String? = dict["name"] as? String

            if name == nil, let item = dict["item"] as? [String: Any] {
                name = (item["name"] as? String) ?? (item["text"] as? String)
            } else if name == nil {
                name = dict["item"] as? String
            }

            if let description = dict["description"] as? String {
                note = description
            }

            let quantity = parseIngredientQuantity(from: dict)

            if let name = name {
                return Ingredient(name: name, quantity: quantity, note: note)
            }

            // Fallback - try to combine all string values
            let combined = dict.compactMap { key, value -> String? in
                guard key != "@type" else { return nil }
                if let string = value as? String { return string }
                return nil
            }.joined(separator: " ")

            if !combined.isEmpty {
                return parseIngredientText(combined)
            }
        }

        return nil
    }

    private func parseIngredientQuantity(from dict: [String: Any]) -> Quantity? {
        if let amount = dict["amount"] {
            if let quantity = parseQuantityComponent(amount, unitText: dict["unitText"] as? String) {
                return quantity
            }
        }

        if let value = dict["quantity"] {
            if let quantity = parseQuantityComponent(value, unitText: dict["unitText"] as? String) {
                return quantity
            }
        }

        if let amountDict = dict["amount"] as? [String: Any],
           let quantity = parseQuantityComponent(amountDict["value"], unitText: amountDict["unitText"] as? String ?? amountDict["unitCode"] as? String) {
            return quantity
        }

        if let valueDict = dict["value"] as? [String: Any],
           let quantity = parseQuantityComponent(valueDict["value"], unitText: valueDict["unitText"] as? String ?? valueDict["unitCode"] as? String) {
            return quantity
        }

        return nil
    }

    private func parseQuantityComponent(_ value: Any?, unitText: String?) -> Quantity? {
        guard let value = value else { return nil }

        if let string = value as? String, let numericValue = parseQuantityValue(string) {
            if let unitText = unitText, let unit = parseUnit(unitText) {
                return Quantity(value: numericValue, unit: unit)
            } else {
                return Quantity(value: numericValue, unit: .whole)
            }
        }

        if let number = value as? Double {
            if let unitText = unitText, let unit = parseUnit(unitText) {
                return Quantity(value: number, unit: unit)
            } else {
                return Quantity(value: number, unit: .whole)
            }
        }

        if let number = value as? Int {
            if let unitText = unitText, let unit = parseUnit(unitText) {
                return Quantity(value: Double(number), unit: unit)
            } else {
                return Quantity(value: Double(number), unit: .whole)
            }
        }

        if let dict = value as? [String: Any] {
            let unit = (dict["unitText"] as? String) ?? (dict["unitCode"] as? String) ?? unitText
            if let nestedValue = dict["value"] ?? dict["amount"] {
                return parseQuantityComponent(nestedValue, unitText: unit)
            }
        }

        return nil
    }

    private func extractInstructionEntries(from json: [String: Any]) -> [String] {
        let sources: [Any?] = [
            json["recipeInstructions"],
            json["instructions"],
            json["step"]
        ]

        for source in sources {
            if let source = source {
                let normalized = normalizeInstructions(from: source)
                if !normalized.isEmpty {
                    var seen = Set<String>()
                    var deduped: [String] = []
                    for text in normalized {
                        let key = text.lowercased()
                        if !seen.contains(key) {
                            seen.insert(key)
                            deduped.append(text)
                        }
                    }
                    if !deduped.isEmpty {
                        return deduped
                    }
                }
            }
        }

        return []
    }

    private func normalizeInstructions(from value: Any) -> [String] {
        if let string = value as? String {
            return string
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if let array = value as? [Any] {
            return array.flatMap { normalizeInstructions(from: $0) }
        }

        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String {
                return normalizeInstructions(from: text)
            }

            if let itemList = dict["itemListElement"] {
                return normalizeInstructions(from: itemList)
            }

            if let howToDirection = dict["recipeInstructions"] {
                return normalizeInstructions(from: howToDirection)
            }

            if let name = dict["name"] as? String, let stepText = dict["itemListElement"] as? [Any] {
                let steps = stepText.flatMap { normalizeInstructions(from: $0) }
                if steps.isEmpty {
                    return normalizeInstructions(from: name)
                } else {
                    return steps
                }
            }

            if let name = dict["name"] as? String,
               dict["itemListElement"] == nil,
               dict["recipeInstructions"] == nil {
                return normalizeInstructions(from: name)
            }

            return dict.values.compactMap { value -> [String]? in
                guard let nestedDict = value as? [String: Any] else { return nil }
                return normalizeInstructions(from: nestedDict)
            }.flatMap { $0 }
        }

        return []
    }

    private func appendTags(from value: Any?, to tags: inout [String], seen: inout Set<String>) {
        guard let value = value else { return }

        let tagStrings: [String]

        if let string = value as? String {
            tagStrings = string
                .split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { String($0) }
        } else if let array = value as? [String] {
            tagStrings = array
        } else if let array = value as? [Any] {
            tagStrings = array.compactMap { $0 as? String }
        } else {
            tagStrings = []
        }

        for tag in tagStrings {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                tags.append(trimmed)
            }
        }
    }

    private func parseDurationValue(_ value: Any?) -> Int? {
        guard let value = value else { return nil }

        if let string = value as? String {
            return parseDuration(string)
        }

        if let number = value as? Int {
            return number
        }

        if let number = value as? Double {
            return Int(number)
        }

        if let dict = value as? [String: Any] {
            if let minValue = dict["minValue"], let maxValue = dict["maxValue"] {
                let minMinutes = parseDurationValue(minValue) ?? 0
                let maxMinutes = parseDurationValue(maxValue) ?? 0
                if minMinutes > 0 && maxMinutes > 0 {
                    return (minMinutes + maxMinutes) / 2
                }
            }

            if let duration = dict["duration"] {
                return parseDurationValue(duration)
            }

            if let value = dict["value"] {
                return parseDurationValue(value)
            }
        }

        return nil
    }

    private func parseIngredientText(_ text: String) -> Ingredient {
        let collapsedWhitespace = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsedWhitespace.isEmpty else {
            return Ingredient(name: text.trimmingCharacters(in: .whitespacesAndNewlines), quantity: nil)
        }

        var quantity: Quantity? = nil
        var remainder = collapsedWhitespace

        if let (parsedQuantity, remainingText) = extractQuantityAndUnit(from: collapsedWhitespace) {
            quantity = parsedQuantity
            remainder = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var note: String? = nil
        var name = remainder

        let noteSeparators = [",", " - ", " – ", " — "]
        for separator in noteSeparators {
            if let range = name.range(of: separator) {
                let before = name[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let after = name[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty {
                    note = after
                }
                name = before
                break
            }
        }

        if note == nil,
           let parenRange = name.range(of: #"\(([^)]+)\)$"#, options: .regularExpression) {
            let inner = name[parenRange].dropFirst().dropLast()
            let cleanedNote = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedNote.isEmpty {
                note = cleanedNote
            }
            name.removeSubrange(parenRange)
        }

        if let parenRange = name.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
            let inner = name[parenRange].dropFirst().dropLast()
            let cleanedNote = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            let before = name[..<parenRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let after = name[parenRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedNote.isEmpty {
                if let existing = note {
                    note = existing + ", " + cleanedNote
                } else {
                    note = cleanedNote
                }
            }
            name = [before, after].filter { !$0.isEmpty }.joined(separator: " ")
        }

        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty {
            name = collapsedWhitespace
        }

        return Ingredient(name: name, quantity: quantity, note: note)
    }

    private func extractQuantityAndUnit(from text: String) -> (Quantity, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let (quantity, remainder) = extractWordBasedQuantity(from: trimmed) {
            return (quantity, remainder)
        }

        let scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = CharacterSet.whitespaces

        guard let quantityPart = scanner.scanCharacters(from: CharacterSet(charactersIn: "0123456789/ .½¼¾⅓⅔⅛⅜⅝⅞,-")) else {
            return nil
        }

        var normalizedQuantity = quantityPart
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedQuantity.isEmpty else { return nil }

        guard let value = parseQuantityValue(normalizedQuantity) else {
            return nil
        }

        let remainingSubstring = trimmed[scanner.currentIndex...]
        var remainder = remainingSubstring.trimmingCharacters(in: .whitespacesAndNewlines)

        var unit: UnitKind = .whole
        if !remainder.isEmpty {
            let components = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let firstWord = components.first {
                let sanitized = firstWord
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}.,"))
                if let parsedUnit = parseUnit(String(sanitized)) {
                    unit = parsedUnit
                    if components.count > 1 {
                        remainder = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        remainder = ""
                    }
                }
            }
        }

        return (Quantity(value: value, unit: unit), remainder)
    }

    private func extractWordBasedQuantity(from text: String) -> (Quantity, String)? {
        let lowercased = text.lowercased()
        let prefixes = ["a", "an", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "dozen", "half", "quarter", "couple", "few"]

        for prefix in prefixes {
            if lowercased.hasPrefix(prefix + " ") || lowercased == prefix {
                guard let value = parseQuantityValue(prefix) else { continue }
                let remaining = text.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)

                var unit: UnitKind = .whole
                var remainder = remaining
                if !remaining.isEmpty {
                    let components = remaining.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    if let first = components.first,
                       let parsedUnit = parseUnit(first.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}.,"))) {
                        unit = parsedUnit
                        if components.count > 1 {
                            remainder = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            remainder = ""
                        }
                    }
                }

                return (Quantity(value: value, unit: unit), remainder)
            }
        }

        return nil
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

        cleaned = cleaned.replacingOccurrences(of: "–", with: "-")
        cleaned = cleaned.replacingOccurrences(of: "—", with: "-")

        // Handle ranges like "1-2" - take the average
        if cleaned.contains("-") {
            let parts = cleaned.components(separatedBy: "-")
            if parts.count == 2,
               let first = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let second = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                return (first + second) / 2
            }
        }

        if cleaned.contains(" to ") {
            let parts = cleaned.components(separatedBy: " to ")
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
        let decimalConverted: String
        if cleaned.contains(",") {
            let commaParts = cleaned.split(separator: ",")
            if !cleaned.contains(".") && commaParts.count == 2 && commaParts[1].count <= 2 {
                decimalConverted = commaParts[0] + "." + commaParts[1]
            } else {
                decimalConverted = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else {
            decimalConverted = cleaned
        }

        if let direct = Double(decimalConverted) {
            return direct
        }

        let lowered = cleaned.lowercased()
        let numberWords: [String: Double] = [
            "a": 1,
            "an": 1,
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
            "seven": 7,
            "eight": 8,
            "nine": 9,
            "ten": 10,
            "eleven": 11,
            "twelve": 12,
            "dozen": 12,
            "half": 0.5,
            "quarter": 0.25,
            "third": 0.33,
            "couple": 2,
            "few": 3
        ]

        if let value = numberWords[lowered] {
            return value
        }

        let normalizedWords = lowered.replacingOccurrences(of: "-", with: " ")
        let tokens = normalizedWords.split(separator: " ")
        if !tokens.isEmpty {
            let values = tokens.compactMap { numberWords[String($0)] }
            if !values.isEmpty {
                return values.reduce(0, +)
            }
        }

        if lowered.contains(" and ") {
            let parts = lowered.components(separatedBy: " and ")
            let values = parts.compactMap { parseQuantityValue($0) }
            if !values.isEmpty {
                return values.reduce(0, +)
            }
        }

        return nil
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
        case "t", "tsp", "tsps", "tsp.", "teaspoons", "teaspoon": return .teaspoon
        case "tbsp", "tbsps", "tbsp.", "tbs.", "tablespoons", "tablespoon", "tbs": return .tablespoon
        case "c", "cups", "cup": return .cup
        case "oz", "oz.", "ounces", "ounce": return .ounce
        case "lb", "lbs", "lb.", "pounds", "pound": return .pound
        case "g", "grams", "gram": return .gram
        case "kg", "kgs", "kilograms", "kilogram": return .kilogram
        case "ml", "mls", "milliliters", "milliliter": return .milliliter
        case "l", "liters", "liter": return .liter
        case "pt", "pts", "pints", "pint": return .pint
        case "qt", "qts", "quarts", "quart": return .quart
        case "gal", "gals", "gallons", "gallon": return .gallon
        case "fl oz", "floz", "fluid ounce", "fluid ounces": return .fluidOunce
        case "pinch", "pinches": return .pinch
        case "dash", "dashes": return .dash
        case "piece", "pieces": return .piece
        case "clove", "cloves": return .clove
        case "bunch", "bunches": return .bunch
        case "can", "cans": return .can
        case "package", "packages", "pkg", "pkgs", "pack", "packs": return .package
        case "stick", "sticks": return .piece
        case "slice", "slices": return .piece
        case "fillet", "fillets", "filet", "filets": return .piece
        case "sprig", "sprigs": return .piece
        case "head", "heads": return .whole
        case "ear", "ears": return .piece
        case "sheet", "sheets": return .piece
        case "handful", "handfuls": return .bunch
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
            #"<p[^>]*class="[^"]*ingredient[^"]*"[^>]*>(.*?)</p>"#,
            #"<[^>]*itemprop=\"recipeIngredient\"[^>]*>(.*?)</[^>]+>"#
        ]
        
        for pattern in ingredientPatterns {
            ingredients = extractMatches(from: html, pattern: pattern)
                .map { stripHTML($0) }
                .flatMap { text -> [Ingredient] in
                    text
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { parseIngredientText($0) }
                }
                .filter { !$0.name.isEmpty }

            if !ingredients.isEmpty { break }
        }

        if ingredients.isEmpty {
            let listPattern = #"<ul[^>]*class="[^"]*(ingredient|ingredients)[^"]*"[^>]*>(.*?)</ul>"#
            let listMatches = extractMatches(from: html, pattern: listPattern)
            for list in listMatches {
                let items = extractMatches(from: list, pattern: #"<li[^>]*>(.*?)</li>"#)
                    .map { stripHTML($0) }
                    .map { parseIngredientText($0) }
                    .filter { !$0.name.isEmpty }
                if items.count >= 2 {
                    ingredients = items
                    break
                }
            }
        }

        if ingredients.isEmpty {
            let genericLists = extractMatches(from: html, pattern: #"<ul[^>]*>(.*?)</ul>"#)
            for list in genericLists {
                let rawItems = extractMatches(from: list, pattern: #"<li[^>]*>(.*?)</li>"#)
                    .map { stripHTML($0) }
                let parsed = rawItems
                    .map { parseIngredientText($0) }
                    .filter { !$0.name.isEmpty }

                let measurementMatches = rawItems.filter { raw in
                    let lower = raw.lowercased()
                    return lower.range(of: #"(\d|cup|tablespoon|teaspoon|ounce|gram|ml|lb|clove|pinch|dash|bunch|can|pkg|package)"#, options: .regularExpression) != nil
                }

                if parsed.count >= 2 && measurementMatches.count >= 2 {
                    ingredients = parsed
                    break
                }
            }
        }
        
        // Extract steps (try multiple patterns)
        var steps: [CookStep] = []
        let stepPatterns = [
            #"<li[^>]*class="[^"]*instruction[^"]*"[^>]*>(.*?)</li>"#,
            #"<li[^>]*class="[^"]*step[^"]*"[^>]*>(.*?)</li>"#,
            #"<li[^>]*data-step[^>]*>(.*?)</li>"#,
            #"<div[^>]*class="[^"]*instruction[^"]*"[^>]*>(.*?)</div>"#,
            #"<p[^>]*class="[^"]*step[^"]*"[^>]*>(.*?)</p>"#,
            #"<div[^>]*class="[^"]*step[^"]*"[^>]*>(.*?)</div>"#,
            #"<[^>]*itemprop=\"recipeInstructions\"[^>]*>(.*?)</[^>]+>"#
        ]
        
        for pattern in stepPatterns {
            let rawStepTexts = extractMatches(from: html, pattern: pattern)
                .map { stripHTML($0) }
                .filter { !$0.isEmpty }

            let expanded = rawStepTexts.flatMap { text -> [String] in
                text
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count > 5 }
            }

            steps = expanded.enumerated().map { index, text in
                let timers = TimerExtractor.extractTimers(from: text)
                return CookStep(index: index, text: text, timers: timers)
            }

            if !steps.isEmpty { break }
        }

        if steps.isEmpty {
            // Fallback: parse ordered list items without explicit classes
            let fallbackSteps = extractMatches(from: html, pattern: #"<ol[^>]*>(.*?)</ol>"#)
                .flatMap { extractMatches(from: $0, pattern: #"<li[^>]*>(.*?)</li>"#) }
                .map { stripHTML($0) }
                .flatMap { text in
                    text
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0.count > 5 }
                }

            steps = fallbackSteps.enumerated().map { index, text in
                let timers = TimerExtractor.extractTimers(from: text)
                return CookStep(index: index, text: text, timers: timers)
            }
        }

        if !steps.isEmpty {
            var seen = Set<String>()
            var deduped: [CookStep] = []
            for step in steps {
                let key = step.text.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    let normalizedStep = CookStep(index: deduped.count, text: step.text, timers: step.timers)
                    deduped.append(normalizedStep)
                }
            }
            steps = deduped
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

        // Convert line-breaking tags to newlines before stripping tags
        result = result.replacingOccurrences(of: #"(<br\s*/?>)+"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</(p|li|div)>"#, with: "\n", options: .regularExpression)

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
        
        // Normalize whitespace while preserving line breaks
        result = result.replacingOccurrences(of: "\r", with: "\n")
        result = result.replacingOccurrences(of: "[ \t\f]+", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: " \n", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n ", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
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

