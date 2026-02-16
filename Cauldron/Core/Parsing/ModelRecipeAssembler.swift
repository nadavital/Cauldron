import Foundation

/// Swift port of the Python lab assembly logic (`_assemble_app_recipe`).
struct ModelRecipeAssembler: Sendable {
    struct Row: Sendable {
        let index: Int
        let text: String
        let label: RecipeLineLabel
    }

    struct SectionItems: Sendable {
        let name: String?
        let items: [String]
    }

    struct AssembledRecipe: Sendable {
        let title: String
        let sourceURL: URL?
        let sourceTitle: String?
        let yields: String
        let totalMinutes: Int?
        let ingredients: [Ingredient]
        let steps: [CookStep]
        let noteLines: [String]
        let notes: String?
        let ingredientSections: [SectionItems]
        let stepSections: [SectionItems]
    }

    private let ingredientHeaderPrefixes: Set<String> = [
        "ingredient", "ingredients", "for the ingredients", "what you'll need"
    ]
    private let stepHeaderPrefixes: Set<String> = [
        "instruction", "instructions", "direction", "directions", "method", "preparation", "steps"
    ]
    private let noteHeaderPrefixes: Set<String> = [
        "note", "notes", "tip", "tips", "variation", "variations", "chef's note", "storage", "substitution", "substitutions"
    ]
    private let instructionKeywords: Set<String> = [
        "add", "bake", "beat", "blend", "boil", "combine", "cook", "cool", "drain", "fold", "fry", "grill",
        "heat", "knead", "let", "marinate", "mash", "mix", "place", "pour", "preheat", "reduce", "rest", "roast",
        "saute", "season", "serve", "simmer", "stir", "transfer", "whisk", "chop", "dice", "slice", "toss"
    ]

    nonisolated func assemble(
        rows: [Row],
        sourceURL: URL? = nil,
        sourceTitle: String? = nil
    ) -> AssembledRecipe {
        var title = ""
        var currentSection = "unknown"
        var currentIngredientSection: String?
        var currentStepSection: String?

        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []
        var notes: [String] = []

        var extractedYields: String?
        var prepMinutes: Int?
        var cookMinutes: Int?
        var totalMinutes: Int?

        func addIngredient(_ text: String, sectionName: String?) {
            let ingredientText = stripStepNumberPrefix(text)
            guard !ingredientText.isEmpty else { return }

            var parsed = IngredientParser.parseIngredientText(ingredientText)
            let sanitized = sanitizeIngredientName(parsed.name)
            if shouldDropIngredientEntry(name: sanitized, quantity: parsed.quantity) {
                return
            }
            parsed = Ingredient(
                name: sanitized,
                quantity: parsed.quantity,
                additionalQuantities: parsed.additionalQuantities,
                note: parsed.note,
                section: sectionName
            )
            ingredients.append(parsed)
        }

        func addStep(_ text: String, sectionName: String?) {
            let stepText = stripStepNumberPrefix(text)
            guard !stepText.isEmpty else { return }
            guard !isOCRArtifactLine(stepText) else { return }

            steps.append(
                CookStep(
                    index: steps.count,
                    text: stepText,
                    timers: TimerExtractor.extractTimers(from: stepText),
                    section: sectionName
                )
            )
        }

        for row in rows.sorted(by: { $0.index < $1.index }) {
            let text = cleanText(row.text)
            if text.isEmpty { continue }

            if let metadata = extractMetadataLine(text) {
                if let yields = metadata.yields {
                    extractedYields = yields
                }
                if let value = metadata.totalMinutes {
                    totalMinutes = value
                }
                if let value = metadata.prepMinutes {
                    prepMinutes = value
                }
                if let value = metadata.cookMinutes {
                    cookMinutes = value
                }
                continue
            }

            if isOCRArtifactLine(text) {
                continue
            }

            if let tipsRemainder = extractTipsRemainder(text) {
                currentSection = "notes"
                let noteLine = normalizeNoteText(tipsRemainder)
                if !noteLine.isEmpty {
                    notes.append(noteLine)
                }
                continue
            }

            if let sectionType = headerSectionType(for: text) {
                if sectionType == "ingredients" {
                    currentSection = "ingredients"
                    currentIngredientSection = nil
                } else if sectionType == "steps" {
                    currentSection = "steps"
                    currentStepSection = nil
                } else {
                    currentSection = "notes"
                }
                continue
            }

            if currentSection == "notes", [.ingredient, .step, .note].contains(row.label) {
                if TextSectionParser.looksLikeNumberedStep(text) {
                    currentSection = "steps"
                    for stepLine in splitNumberedSteps(text) {
                        addStep(stepLine, sectionName: currentStepSection)
                    }
                } else {
                    let noteLine = normalizeNoteText(text)
                    if !noteLine.isEmpty {
                        notes.append(noteLine)
                    }
                }
                continue
            }

            if row.label == .title, title.isEmpty {
                if looksLikeRecipeTitle(text) {
                    title = text
                } else {
                    notes.append(text)
                }
                continue
            }

            if row.label == .header {
                if looksLikeSubsectionHeader(text) {
                    let subsection = cleanText(String(text.dropLast()))
                    if currentSection == "steps" {
                        currentStepSection = subsection
                    } else if currentSection == "notes" {
                        notes.append(text)
                    } else {
                        currentSection = "ingredients"
                        currentIngredientSection = subsection
                    }
                    continue
                }

                if currentSection == "ingredients" {
                    if looksLikeHeaderlessInstruction(text) {
                        currentSection = "steps"
                        addStep(text, sectionName: currentStepSection)
                    } else {
                        addIngredient(text, sectionName: currentIngredientSection)
                    }
                }
                continue
            }

            if row.label == .ingredient {
                if currentSection == "notes" && looksLikeNoteFragment(text) {
                    let noteLine = normalizeNoteText(text)
                    if !noteLine.isEmpty {
                        notes.append(noteLine)
                    }
                    continue
                }
                if currentSection == "notes" && looksLikeStepFragment(text) {
                    currentSection = "steps"
                    addStep(text, sectionName: currentStepSection)
                    continue
                }
                if currentSection == "ingredients" && looksLikeHeaderlessInstruction(text) {
                    currentSection = "steps"
                    addStep(text, sectionName: currentStepSection)
                } else if currentSection == "steps" {
                    if TextSectionParser.looksLikeNumberedStep(text) || looksLikeStepFragment(text) || !looksLikeIngredientLine(text) {
                        addStep(text, sectionName: currentStepSection)
                    } else {
                        currentSection = "ingredients"
                        addIngredient(text, sectionName: currentIngredientSection)
                    }
                } else {
                    currentSection = "ingredients"
                    addIngredient(text, sectionName: currentIngredientSection)
                }
                continue
            }

            if row.label == .step {
                if currentSection == "notes" && looksLikeNoteFragment(text) {
                    let noteLine = normalizeNoteText(text)
                    if !noteLine.isEmpty {
                        notes.append(noteLine)
                    }
                    continue
                }
                if currentSection == "ingredients" && !looksLikeStepFragment(text) {
                    addIngredient(text, sectionName: currentIngredientSection)
                    continue
                }
                currentSection = "steps"
                for stepLine in splitNumberedSteps(text) {
                    addStep(stepLine, sectionName: currentStepSection)
                }
                continue
            }

            if row.label == .note {
                if looksLikeStepFragment(text) {
                    currentSection = "steps"
                    addStep(text, sectionName: currentStepSection)
                } else {
                    currentSection = "notes"
                    let noteLine = normalizeNoteText(text)
                    if !noteLine.isEmpty {
                        notes.append(noteLine)
                    }
                }
                continue
            }

            if title.isEmpty && row.label != .junk && looksLikeRecipeTitle(text) {
                title = text
            }
        }

        if title.isEmpty || !looksLikeRecipeTitle(title) {
            for row in rows.sorted(by: { $0.index < $1.index }) {
                let text = cleanText(row.text)
                if !text.isEmpty && looksLikeRecipeTitle(text) {
                    title = text
                    break
                }
            }
        }

        if title.isEmpty || !looksLikeRecipeTitle(title) {
            if let noteIndex = notes.firstIndex(where: { looksLikeRecipeTitle($0) }) {
                title = cleanText(notes[noteIndex])
                notes.remove(at: noteIndex)
            }
        }

        if title.isEmpty {
            title = "Untitled Recipe"
        }

        ingredients = mergeWrappedIngredients(ingredients)
        steps = mergeWrappedSteps(steps)
        inferSauceSectionSplit(ingredients: &ingredients, steps: steps)

        let ingredientSections = groupedSections(
            names: ingredients.map(\.section),
            texts: ingredients.map(\.name)
        )
        let stepSections = groupedSections(
            names: steps.map(\.section),
            texts: steps.map(\.text)
        )

        let normalizedTitle = cleanText(title).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        notes = notes.filter {
            cleanText($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != normalizedTitle
        }
        let notesText = notes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedTotalMinutes: Int? = {
            if let totalMinutes { return totalMinutes }
            if let prepMinutes, let cookMinutes { return prepMinutes + cookMinutes }
            if let cookMinutes { return cookMinutes }
            return prepMinutes
        }()

        return AssembledRecipe(
            title: title,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle ?? sourceURL?.host,
            yields: extractedYields ?? "4 servings",
            totalMinutes: resolvedTotalMinutes,
            ingredients: ingredients,
            steps: steps,
            noteLines: notes,
            notes: notesText.isEmpty ? nil : notesText,
            ingredientSections: ingredientSections,
            stepSections: stepSections
        )
    }

    private func groupedSections(names: [String?], texts: [String]) -> [SectionItems] {
        var order: [String] = []
        var buckets: [String: [String]] = [:]

        for (index, text) in texts.enumerated() {
            let key = names.indices.contains(index) ? (names[index] ?? "Main") : "Main"
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key, default: []].append(text)
        }

        return order.map { key in
            SectionItems(name: key == "Main" ? nil : key, items: buckets[key] ?? [])
        }
    }

    private func headerSectionType(for line: String) -> String? {
        let key = headerKey(line)
        if ingredientHeaderPrefixes.contains(key) { return "ingredients" }
        if stepHeaderPrefixes.contains(key) { return "steps" }
        if noteHeaderPrefixes.contains(key) { return "notes" }
        return nil
    }

    private func headerKey(_ line: String) -> String {
        var lowered = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lowered = lowered.replacingOccurrences(of: #"^[\W_]+|[\W_]+$"#, with: "", options: .regularExpression)
        if lowered.hasSuffix(":") {
            lowered = String(lowered.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lowered
    }

    private func looksLikeSubsectionHeader(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasSuffix(":") else { return false }
        let words = text.dropLast().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty && words.count <= 7 else { return false }
        if text.count > 90 { return false }
        if text.contains(where: \.isNumber) { return false }
        return true
    }

    private func looksLikeIngredientLine(_ line: String) -> Bool {
        line.range(of: #"^[\d\s½¼¾⅓⅔⅛⅜⅝⅞/\.-]+"#, options: .regularExpression) != nil
    }

    private func looksLikeHeaderlessInstruction(_ line: String) -> Bool {
        if looksLikeIngredientLine(line) {
            return false
        }
        if splitNumberedSteps(line) != [cleanText(line)] {
            return true
        }
        let words = line.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return false }
        let tokens = line.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if instructionKeywords.contains(first) {
            return true
        }
        if ["in", "on", "to", "then", "meanwhile"].contains(first),
           tokens.contains(where: { instructionKeywords.contains($0) }) {
            return true
        }
        return false
    }

    private func isOCRArtifactLine(_ text: String) -> Bool {
        let cleaned = cleanText(text)
        if cleaned.isEmpty { return true }
        let lowered = cleaned.lowercased()
        if isBoilerplateNoiseLine(lowered) {
            return true
        }
        if lowered.contains("templatelab") || lowered.contains("created by") || lowered == "reated b" {
            return true
        }
        if lowered.range(of: #"^\s*(?:prep(?:ping)?|preparation|cook(?:ing)?|total)\s*tim(?:e)?\b"#, options: .regularExpression) != nil {
            return true
        }
        if cleaned.range(of: #"^[\W_]+$"#, options: .regularExpression) != nil {
            return true
        }
        let alphaCount = cleaned.filter(\.isLetter).count
        if alphaCount <= 1 {
            return true
        }
        if cleaned.range(of: #"^[A-Za-z]{1,2}$"#, options: .regularExpression) != nil {
            let keep = Set(["oil", "egg", "eggs"])
            if !keep.contains(lowered) {
                return true
            }
        }
        return false
    }

    private func isBoilerplateNoiseLine(_ loweredLine: String) -> Bool {
        switch loweredLine {
        case "ad", "ads", "advertisement", "sponsored":
            return true
        default:
            return false
        }
    }

    private func extractTipsRemainder(_ text: String) -> String? {
        let cleaned = cleanText(text)
        guard !cleaned.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(
            pattern: #"\btips?\s*(?:and|&)\s*variations?\b[:\-\s]*(.*)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let ns = cleaned as NSString
        if let match = regex.firstMatch(in: cleaned, range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges >= 2 {
            return cleanText(ns.substring(with: match.range(at: 1)))
        }
        if cleaned.range(of: #"^tips?(?:\s*(?:and|&)\s*variations?)?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return ""
        }
        return nil
    }

    private func normalizeNoteText(_ text: String) -> String {
        let cleaned = cleanText(text)
        let trimmed = cleaned.replacingOccurrences(of: #"^[,;:\-•\s]+"#, with: "", options: .regularExpression)
        return cleanText(trimmed)
    }

    private func hasExplicitNotePrefix(_ text: String) -> Bool {
        let cleaned = cleanText(text)
        return cleaned.range(
            of: #"^(?:note|notes|tip|tips|pro tip|variation|variations|chef's note|substitution|substitutions)\b[:\-\s]*"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func looksLikeNoteFragment(_ text: String) -> Bool {
        let cleaned = cleanText(text)
        guard !cleaned.isEmpty else { return false }
        if hasExplicitNotePrefix(cleaned) {
            return true
        }
        if looksLikeIngredientLine(cleaned) || looksLikeHeaderlessInstruction(cleaned) {
            return false
        }
        if [",", ";", ":"].contains(String(cleaned.first ?? " ")) {
            return cleaned.split(whereSeparator: \.isWhitespace).count >= 2
        }
        let lowered = cleaned.lowercased()
        if lowered.range(of: #"^(?:for|feel|use|optional|tip|tips|variation|variations|extra)\b"#, options: .regularExpression) != nil {
            return true
        }
        return lowered.range(of: #"\b(?:flavor|nutrition|twist|optional|variation|tip|wine)\b"#, options: .regularExpression) != nil
    }

    private func looksLikeStepFragment(_ text: String) -> Bool {
        let cleaned = cleanText(text)
        guard !cleaned.isEmpty else { return false }
        if hasExplicitNotePrefix(cleaned) { return false }
        if isOCRArtifactLine(cleaned) { return false }
        if extractTipsRemainder(cleaned) != nil { return false }
        if looksLikeIngredientLine(cleaned) { return false }
        if looksLikeNoteFragment(cleaned) { return false }
        if looksLikeHeaderlessInstruction(cleaned) { return true }
        let lowered = cleaned.lowercased()
        if lowered.range(of: #"\b(?:add|cook|drain|heat|mix|preheat|prepare|remove|rest|return|serve|simmer|sprinkle|stir|toss)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lowered.range(of: #"\b(?:bowl|broth|minutes?|oven|pot|sauce|set aside|skillet)\b"#, options: .regularExpression) != nil {
            return true
        }
        if cleaned.hasSuffix("."), cleaned.split(whereSeparator: \.isWhitespace).count >= 4 {
            return true
        }
        return false
    }

    private func sanitizeIngredientName(_ name: String) -> String {
        var cleaned = cleanText(name)
        guard !cleaned.isEmpty else { return "" }

        let replacements: [(String, String)] = [
            (#"\bpackage and\b"#, "and"),
            (#"\bpackage\b"#, ""),
            (#"\bto\s+taste\s+salt(?:\s+and)?\b.*$"#, "to taste"),
            (#"\bto\s+taste\b.*$"#, "to taste"),
            (#"\bfor serving\b.*$"#, "for serving"),
            (#"\bto\s+taste\s+and\s*$"#, "to taste")
        ]
        for (pattern, replacement) in replacements {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }

        let lowered = cleaned.lowercased()
        if lowered.range(of: #"\b(?:package instructions?|set aside|minutes?|minute)\b"#, options: .regularExpression) != nil {
            cleaned = cleaned.replacingOccurrences(of: #"\bpackage instructions?\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            cleaned = cleaned.replacingOccurrences(of: #"\bset aside\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            cleaned = cleaned.replacingOccurrences(of: #"\bminutes?\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            cleaned = cleaned.replacingOccurrences(of: #"\babout\s+\d+\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        }

        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        cleaned = cleaned.replacingOccurrences(of: #"\b[A-Za-z]$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        return cleanText(cleaned)
    }

    private func shouldDropIngredientEntry(name: String, quantity: Quantity?) -> Bool {
        let cleaned = cleanText(name)
        if cleaned.isEmpty { return true }
        if isOCRArtifactLine(cleaned) { return true }
        if extractTipsRemainder(cleaned) != nil { return true }

        let lowered = cleaned.lowercased()
        if quantity == nil {
            if looksLikeHeaderlessInstruction(cleaned) {
                return true
            }
            if lowered.range(of: #"\b(?:skillet|prepare|serve|sprinkle|immediately|return the|set aside|minutes?)\b"#, options: .regularExpression) != nil {
                return true
            }
            if cleaned.range(of: #"^[A-Za-z]+\s+\d+$"#, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private struct MetadataLine {
        let yields: String?
        let prepMinutes: Int?
        let cookMinutes: Int?
        let totalMinutes: Int?
    }

    private func extractMetadataLine(_ text: String) -> MetadataLine? {
        var yields: String?
        var prep: Int?
        var cook: Int?
        var total: Int?

        yields = extractYieldLine(text)
        total = extractMinutesByPattern(text, pattern: #"^\s*(?:total\s*time|total|ready\s*in)\s*:?\s*(.+)$"#)
            ?? extractMinutesByPattern(text, pattern: #"^\s*time\s*:\s*(.+)$"#)
        prep = extractMinutesByPattern(text, pattern: #"^\s*(?:prep\s*time|prepping\s*time|preparation\s*time)\s*:?\s*(.+)$"#)
        cook = extractMinutesByPattern(text, pattern: #"^\s*(?:cook\s*time|cooking\s*time|bake\s*time|roast\s*time)\s*:?\s*(.+)$"#)

        if yields == nil, prep == nil, cook == nil, total == nil {
            return nil
        }
        return MetadataLine(yields: yields, prepMinutes: prep, cookMinutes: cook, totalMinutes: total)
    }

    private func extractMinutesByPattern(_ text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        let tail = cleanText(ns.substring(with: match.range(at: 1)))
        guard !tail.isEmpty else { return nil }
        return TimeParser.parseTimeString(tail)
    }

    private func extractYieldLine(_ text: String) -> String? {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixes = ["serves", "serving", "servings", "yield", "yields", "makes", "portion", "portions"]
        let matches = prefixes.contains { key in
            lowered == key || lowered.hasPrefix(key + " ") || lowered.hasPrefix(key + ":")
        }
        guard matches else { return nil }

        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\s*(?:-|–|to)\s*\d+)?)"#, options: .caseInsensitive) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var number = ns.substring(with: match.range(at: 1))
        number = number.replacingOccurrences(of: " to ", with: "-").replacingOccurrences(of: "–", with: "-")
        number = cleanText(number)
        return "\(number) servings"
    }

    private func looksLikeRecipeTitle(_ text: String) -> Bool {
        let cleaned = cleanText(text)
        guard !cleaned.isEmpty else { return false }
        if extractTipsRemainder(cleaned) != nil { return false }
        if looksLikeIngredientLine(cleaned) { return false }
        if extractMetadataLine(cleaned) != nil { return false }
        if cleaned.range(of: #"\b(?:prep(?:ping)?|preparation|cook(?:ing)?|total)\s*tim(?:e)?\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        if headerSectionType(for: cleaned) != nil { return false }
        if cleaned.range(of: #"^\s*[-•*]\s+"#, options: .regularExpression) != nil { return false }
        if cleaned.hasSuffix(".") { return false }
        if cleaned.range(of: #"^(?:for|feel|use)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return false }
        if cleaned.contains(","), cleaned.split(whereSeparator: \.isWhitespace).count > 8 { return false }
        if cleaned.range(of: #"^(?:preheat|mix|add|bake|cook|stir|whisk|combine|toss|rest|serve|simmer|boil)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z'&-]*"#) else {
            return false
        }
        let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length))
        return matches.count >= 2 && matches.count <= 16
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

    private func stripStepNumberPrefix(_ text: String) -> String {
        var cleaned = cleanText(text)
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[•·▪◦●]+\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^\s*\d{1,2}\s*[.)]\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[•·▪◦●]+\s*"#, with: "", options: .regularExpression)
        return cleanText(cleaned)
    }

    private func mergeWrappedSteps(_ steps: [CookStep]) -> [CookStep] {
        var merged: [CookStep] = []
        for step in steps {
            let text = cleanText(step.text)
            guard !text.isEmpty else { continue }

            if let previous = merged.last,
               previous.section == step.section,
               looksLikeStepContinuation(previous: previous.text, current: text) {
                var updated = previous
                let mergedText = cleanText(previous.text + " " + text)
                updated = CookStep(
                    id: previous.id,
                    index: previous.index,
                    text: mergedText,
                    timers: TimerExtractor.extractTimers(from: mergedText),
                    mediaURL: previous.mediaURL,
                    section: previous.section
                )
                merged[merged.count - 1] = updated
                continue
            }

            merged.append(
                CookStep(
                    index: merged.count,
                    text: text,
                    timers: TimerExtractor.extractTimers(from: text),
                    section: step.section
                )
            )
        }
        return merged.enumerated().map { idx, step in
            CookStep(
                id: step.id,
                index: idx,
                text: step.text,
                timers: step.timers,
                mediaURL: step.mediaURL,
                section: step.section
            )
        }
    }

    private func looksLikeStepContinuation(previous: String, current: String) -> Bool {
        let prev = cleanText(previous)
        let curr = cleanText(current)
        guard !prev.isEmpty, !curr.isEmpty else { return false }
        if curr.range(of: #"^[-•*]\s+"#, options: .regularExpression) != nil { return false }
        if curr.range(of: #"^\d+\s*[.)]\s+"#, options: .regularExpression) != nil { return false }
        if looksLikeSubsectionHeader(curr) { return false }
        if [".", "!", "?"].contains(String(prev.last ?? " ")) { return false }
        if [",", ";", "-", "–", "—", "/"].contains(String(prev.last ?? " ")) { return true }
        if prev.filter({ $0 == "(" }).count > prev.filter({ $0 == ")" }).count { return true }
        if curr.range(of: #"^(?:and|or|then|plus|also)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if curr.range(of: #"^[a-z(\[\"'/-]"#, options: .regularExpression) != nil { return true }
        return false
    }

    private func mergeWrappedIngredients(_ ingredients: [Ingredient]) -> [Ingredient] {
        var merged: [Ingredient] = []
        for ingredient in ingredients {
            let name = cleanText(ingredient.name)
            guard !name.isEmpty else { continue }
            let normalized = Ingredient(
                id: ingredient.id,
                name: name,
                quantity: ingredient.quantity,
                additionalQuantities: ingredient.additionalQuantities,
                note: ingredient.note,
                section: ingredient.section
            )

            if let previous = merged.last,
               looksLikeIngredientContinuation(previous: previous, current: normalized) {
                let combinedName = cleanText(previous.name + " " + name)
                let updated = Ingredient(
                    id: previous.id,
                    name: combinedName,
                    quantity: previous.quantity,
                    additionalQuantities: previous.additionalQuantities,
                    note: previous.note,
                    section: previous.section
                )
                merged[merged.count - 1] = updated
            } else {
                merged.append(normalized)
            }
        }
        return merged
    }

    private func looksLikeIngredientContinuation(previous: Ingredient, current: Ingredient) -> Bool {
        if previous.section != current.section { return false }
        if current.quantity != nil { return false }
        if !current.additionalQuantities.isEmpty { return false }

        let prevName = cleanText(previous.name)
        let currName = cleanText(current.name)
        if prevName.isEmpty || currName.isEmpty { return false }

        if [",", ";", "-", "(", "/"].contains(String(prevName.last ?? " ")) { return true }
        if currName.range(of: #"^(?:and|or|to|for|of|with|plus)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if currName.range(of: #"^\d+-[A-Za-z]"#, options: .regularExpression) != nil {
            return true
        }
        if let first = currName.first, first.isLowercase {
            return true
        }
        return false
    }

    private func inferSauceSectionSplit(ingredients: inout [Ingredient], steps: [CookStep]) {
        if ingredients.count < 6 { return }
        if ingredients.contains(where: { $0.section != nil }) { return }

        let stepText = steps.map(\.text).joined(separator: " ").lowercased()
        if stepText.range(of: #"\bsauce\b"#, options: .regularExpression) == nil {
            return
        }

        var splitIndex: Int?
        var splitName = "Sauce"
        for idx in 0..<(ingredients.count - 2) {
            let name = cleanText(ingredients[idx].name.lowercased())
            if name.isEmpty { continue }
            var marker = name.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            marker = marker.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " :;,-"))
            if marker.isEmpty { continue }

            if marker.range(of: #"^(?:for (?:the )?sauce|sauce)$"#, options: .regularExpression) != nil {
                splitIndex = idx + 1
                splitName = "Sauce"
                break
            }
            if marker.range(of: #"^(?:for serving|to serve|for garnish)$"#, options: .regularExpression) != nil {
                splitIndex = idx + 1
                splitName = "For Serving"
                break
            }
        }

        guard let splitIndex else { return }
        if splitIndex < 2 || (ingredients.count - splitIndex) < 2 { return }

        ingredients = ingredients.enumerated().map { idx, ingredient in
            Ingredient(
                id: ingredient.id,
                name: ingredient.name,
                quantity: ingredient.quantity,
                additionalQuantities: ingredient.additionalQuantities,
                note: ingredient.note,
                section: idx < splitIndex ? nil : splitName
            )
        }
    }

    private func cleanText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
