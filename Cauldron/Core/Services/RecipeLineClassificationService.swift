//
//  RecipeLineClassificationService.swift
//  Cauldron
//
//  Created on February 10, 2026.
//

import Foundation

protocol RecipeLineClassifying: Sendable {
    nonisolated func classify(lines: [String]) -> [RecipeLineClassification]
}

enum RecipeLineLabel: String, Codable, Sendable, CaseIterable {
    case title
    case ingredient
    case step
    case note
    case header
    case junk
}

struct RecipeLineClassification: Sendable {
    let line: String
    let label: RecipeLineLabel
    let confidence: Double
}

private enum RuntimeSection: String {
    case ingredients
    case steps
    case notes
}

private struct RuntimePrediction {
    let label: RecipeLineLabel
    let confidence: Double
}

private enum FeatureTextUtils {
    nonisolated static func normalizeForFeatures(_ text: String) -> String {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        normalized = regexReplacing(pattern: #"^\d+[.):-]\s*"#, in: normalized, with: "")
        normalized = regexReplacing(pattern: #"^[•●○◦▪▫\-]+\s*"#, in: normalized, with: "")
        return normalized
    }

    nonisolated static func collapseWhitespace(_ value: String) -> String {
        regexReplacing(pattern: #"\s+"#, in: value, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func regexReplacing(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    nonisolated static func regexCaptures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match in
            guard let captureRange = Range(match.range, in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }
}

private struct NGramNaiveBayesRuntimeModel: Sendable {
    let labels: [RecipeLineLabel]
    let alpha: Double
    let docCountByLabel: [RecipeLineLabel: Int]
    let featureCountByLabel: [RecipeLineLabel: [String: Int]]
    let totalFeatureCountByLabel: [RecipeLineLabel: Int]
    let vocabularyCount: Int

    nonisolated init?(compiledModelURL: URL) {
        let manifestURL = compiledModelURL.appendingPathComponent("Manifest.json")
        let jsonURL: URL

        if let manifestData = try? Data(contentsOf: manifestURL),
           let manifestPayload = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           let jsonName = manifestPayload["modelJSONPayload"] as? String {
            jsonURL = compiledModelURL.appendingPathComponent(jsonName)
        } else {
            jsonURL = compiledModelURL.appendingPathComponent("line_classifier.json")
        }

        guard let payloadData = try? Data(contentsOf: jsonURL),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let payloadLabels = payload["labels"] as? [String],
              let payloadAlpha = payload["alpha"] as? Double,
              let payloadDocCounts = payload["doc_count_by_label"] as? [String: Int],
              let payloadFeatureCounts = payload["feature_count_by_label"] as? [String: [String: Int]],
              let payloadTotalFeatureCounts = payload["total_feature_count_by_label"] as? [String: Int],
              let payloadVocabulary = payload["vocabulary"] as? [String] else {
            return nil
        }

        let mappedLabels = payloadLabels.compactMap { RecipeLineLabel(rawValue: $0) }
        guard !mappedLabels.isEmpty else {
            return nil
        }

        var docCounts: [RecipeLineLabel: Int] = [:]
        var featureCounts: [RecipeLineLabel: [String: Int]] = [:]
        var totalFeatureCounts: [RecipeLineLabel: Int] = [:]

        for label in mappedLabels {
            docCounts[label] = payloadDocCounts[label.rawValue] ?? 0
            featureCounts[label] = payloadFeatureCounts[label.rawValue] ?? [:]
            totalFeatureCounts[label] = payloadTotalFeatureCounts[label.rawValue] ?? 0
        }

        self.labels = mappedLabels
        self.alpha = payloadAlpha
        self.docCountByLabel = docCounts
        self.featureCountByLabel = featureCounts
        self.totalFeatureCountByLabel = totalFeatureCounts
        self.vocabularyCount = max(1, payloadVocabulary.count)
    }

    nonisolated func predict(text: String) -> RuntimePrediction {
        if let heuristic = ruleBasedLabel(text) {
            return heuristic
        }

        let features = extractFeatures(from: text)
        let totalDocs = max(0, labels.reduce(0) { $0 + (docCountByLabel[$1] ?? 0) })

        var logScores: [RecipeLineLabel: Double] = [:]
        for label in labels {
            let docsForLabel = Double(docCountByLabel[label] ?? 0)
            let priorDenominator = Double(totalDocs) + alpha * Double(labels.count)
            let logPrior: Double
            if priorDenominator <= 0 {
                logPrior = -1_000_000_000
            } else {
                logPrior = log((docsForLabel + alpha) / priorDenominator)
            }

            let totalFeatureCount = Double(totalFeatureCountByLabel[label] ?? 0)
            let denominator = totalFeatureCount + alpha * Double(vocabularyCount)
            var likelihood = 0.0
            let labelFeatureCounts = featureCountByLabel[label] ?? [:]

            for (feature, count) in features {
                let numerator = Double(labelFeatureCounts[feature] ?? 0) + alpha
                likelihood += Double(count) * log(numerator / denominator)
            }

            logScores[label] = logPrior + likelihood
        }

        guard let bestLabel = logScores.max(by: { $0.value < $1.value })?.key else {
            return RuntimePrediction(label: .step, confidence: 0.60)
        }

        let maxLog = logScores.values.max() ?? 0
        var expScores: [RecipeLineLabel: Double] = [:]
        var normalizer = 0.0
        for (label, score) in logScores {
            let shifted = exp(score - maxLog)
            expScores[label] = shifted
            normalizer += shifted
        }

        let confidence = (expScores[bestLabel] ?? 0.0) / max(1e-12, normalizer)
        return RuntimePrediction(label: bestLabel, confidence: confidence)
    }

    nonisolated private func ruleBasedLabel(_ text: String) -> RuntimePrediction? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = FeatureTextUtils.normalizeForFeatures(text)
        let compact = FeatureTextUtils.collapseWhitespace(normalized)

        if compact.isEmpty {
            return RuntimePrediction(label: .junk, confidence: 0.99)
        }

        let words = compact.split(separator: " ")

        if compact.hasPrefix("<") && compact.hasSuffix(">") {
            return RuntimePrediction(label: .junk, confidence: 0.99)
        }

        if headerKeywords.contains(compact) {
            return RuntimePrediction(label: .header, confidence: 0.99)
        }

        if compact.hasPrefix("for the ") && compact.hasSuffix(":") {
            return RuntimePrediction(label: .header, confidence: 0.97)
        }

        if compact.hasSuffix(":") {
            let stem = String(compact.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            if notePrefixes.contains(where: { stem.hasPrefix($0) }) {
                return RuntimePrediction(label: .header, confidence: 0.98)
            }
            if headerKeywords.contains(stem) {
                return RuntimePrediction(label: .header, confidence: 0.98)
            }
            if words.count <= 5 {
                return RuntimePrediction(label: .header, confidence: 0.90)
            }
        }

        if notePrefixes.contains(where: { compact.hasPrefix($0 + ":") }) {
            return RuntimePrediction(label: .note, confidence: 0.97)
        }

        if notePrefixes.contains(where: { compact.hasPrefix($0 + " ") }) {
            return RuntimePrediction(label: .note, confidence: 0.95)
        }

        if compact.range(of: #"^[\d½¼¾⅓⅔⅛⅜⅝⅞/.\-]+\s+"#, options: .regularExpression) != nil {
            return RuntimePrediction(label: .ingredient, confidence: 0.95)
        }

        if compact.range(of: #"^\d+\s*[x×]\s+"#, options: .regularExpression) != nil {
            return RuntimePrediction(label: .ingredient, confidence: 0.92)
        }

        if actionPrefixes.contains(where: { compact.hasPrefix($0 + " ") }) {
            return RuntimePrediction(label: .step, confidence: 0.92)
        }

        if words.count >= 8 {
            return RuntimePrediction(label: .step, confidence: 0.88)
        }

        if ingredientHints.contains(where: { compact.contains($0) }) {
            return RuntimePrediction(label: .ingredient, confidence: 0.86)
        }

        let looksLikeTitle = {
            guard (2...6).contains(words.count),
                  !raw.contains(":"),
                  !raw.contains(where: { $0.isNumber }),
                  let first = raw.first,
                  first.isUppercase,
                  raw == raw.capitalized else {
                return false
            }
            return true
        }()

        if looksLikeTitle {
            return RuntimePrediction(label: .title, confidence: 0.78)
        }

        return nil
    }

    nonisolated private func extractFeatures(from text: String) -> [String: Int] {
        let normalized = FeatureTextUtils.normalizeForFeatures(text)
        let tokens = FeatureTextUtils.regexCaptures(pattern: #"[a-z0-9]+"#, in: normalized)

        var features: [String: Int] = [:]

        for token in tokens {
            features["tok:\(token)", default: 0] += 1
        }

        if tokens.count >= 2 {
            for index in 0..<(tokens.count - 1) {
                let key = "tok2:\(tokens[index])_\(tokens[index + 1])"
                features[key, default: 0] += 1
            }
        }

        let compact = FeatureTextUtils.collapseWhitespace(normalized)
        let chars = Array(compact)
        for n in 3...5 {
            guard chars.count >= n else {
                continue
            }
            for start in 0...(chars.count - n) {
                let gram = String(chars[start..<(start + n)])
                if gram.contains("  ") {
                    continue
                }
                features["chr\(n):\(gram)", default: 0] += 1
            }
        }

        if normalized.hasSuffix(":") {
            features["shape:ends_colon", default: 0] += 1
        }
        if normalized.contains(where: { $0.isNumber }) {
            features["shape:has_digit", default: 0] += 1
        }
        if normalized.hasPrefix("note") || normalized.hasPrefix("tip") {
            features["shape:starts_note", default: 0] += 1
        }
        if normalized.hasPrefix("<") && normalized.hasSuffix(">") {
            features["shape:tag_like", default: 0] += 1
        }

        return features
    }

    nonisolated private var actionPrefixes: [String] { [
        "add", "bake", "beat", "boil", "brown", "chop", "combine", "cook", "fold",
        "heat", "let", "marinate", "mash", "mix", "pat", "pour", "preheat", "refrigerate",
        "rest", "roast", "saute", "serve", "simmer", "spread", "stir", "toast", "toss", "whisk"
    ] }

    nonisolated private var notePrefixes: [String] { [
        "note", "notes", "tip", "tips", "chef's note", "variation", "variations", "storage"
    ] }

    nonisolated private var headerKeywords: Set<String> { [
        "ingredients", "ingredient", "instructions", "instruction", "directions", "direction", "steps", "step", "method"
    ] }

    nonisolated private var ingredientHints: [String] { [
        "to taste", "for garnish", "optional", "divided", "melted"
    ] }
}

/// Line classifier for recipe schema extraction.
/// Uses exported Naive Bayes parameters when available, and falls back to deterministic heuristics.
final class RecipeLineClassificationService: RecipeLineClassifying, @unchecked Sendable {

    private let runtimeModel: NGramNaiveBayesRuntimeModel?

    private let instructionKeywords: Set<String> = [
        "add", "bake", "beat", "blend", "boil", "brown", "chop", "combine", "cook", "fold",
        "heat", "knead", "let", "mash", "mix", "pat", "place", "pour", "preheat", "refrigerate",
        "rest", "roast", "saute", "season", "serve", "simmer", "spread", "stir", "toast", "toss", "whisk"
    ]

    private let ingredientHints: [String] = [
        "to taste", "for garnish", "optional", "divided", "room temperature", "melted"
    ]

    private let notePrefixes: [String] = [
        "note", "notes", "tip", "tips", "pro tip", "variation", "variations", "substitution",
        "substitutions", "storage", "make ahead", "make-ahead", "chef's note", "recipe note"
    ]

    private let actionPrefixes: [String] = [
        "add", "bake", "beat", "boil", "brown", "chop", "combine", "cook", "fold",
        "heat", "let", "marinate", "mash", "mix", "pat", "pour", "preheat", "refrigerate",
        "rest", "roast", "saute", "serve", "simmer", "spread", "stir", "toast", "toss", "whisk"
    ]

    private let ingredientHeaderKeywords: Set<String> = [
        "ingredient", "ingredients", "for the ingredients", "what you'll need"
    ]

    private let stepHeaderKeywords: Set<String> = [
        "instruction", "instructions", "direction", "directions", "step", "steps", "method", "preparation"
    ]

    nonisolated init(bundle: Bundle = .main, modelArtifactName: String = "RecipeLineClassifier") {
        if let compiledURL = bundle.url(forResource: modelArtifactName, withExtension: "mlmodelc") {
            self.runtimeModel = NGramNaiveBayesRuntimeModel(compiledModelURL: compiledURL)
        } else {
            self.runtimeModel = nil
        }
    }

    nonisolated func classify(lines: [String]) -> [RecipeLineClassification] {
        if let runtimeModel {
            return classifyWithRuntimeModel(lines: lines, model: runtimeModel)
        }
        return classifyWithHeuristicFallback(lines: lines)
    }

    nonisolated private func classifyWithRuntimeModel(
        lines: [String],
        model: NGramNaiveBayesRuntimeModel
    ) -> [RecipeLineClassification] {
        var results: [RecipeLineClassification] = []
        results.reserveCapacity(lines.count)

        var currentSection: RuntimeSection?

        for (index, line) in lines.enumerated() {
            var prediction = model.predict(text: line)
            let sectionFromHeader = headerSection(from: line)
            let looksLikeHeader = looksLikeStandaloneHeaderCandidate(line)

            if looksLikeTitleLine(line, index: index) {
                prediction = RuntimePrediction(label: .title, confidence: max(prediction.confidence, 0.96))
            }

            if let sectionFromHeader {
                prediction = RuntimePrediction(label: .header, confidence: max(prediction.confidence, 0.98))
                currentSection = sectionFromHeader
            } else if looksLikeHeader {
                prediction = RuntimePrediction(label: .header, confidence: max(prediction.confidence, 0.93))
            } else if currentSection == .notes, prediction.label != .header {
                prediction = RuntimePrediction(label: .note, confidence: max(prediction.confidence, 0.90))
            } else if currentSection == .ingredients, ![.header, .title].contains(prediction.label) {
                prediction = RuntimePrediction(label: .ingredient, confidence: max(prediction.confidence, 0.90))
            } else if currentSection == .steps, prediction.label != .header {
                prediction = RuntimePrediction(label: .step, confidence: max(prediction.confidence, 0.90))
            }

            results.append(
                RecipeLineClassification(
                    line: line,
                    label: prediction.label,
                    confidence: prediction.confidence
                )
            )
        }

        return results
    }

    nonisolated private func classifyWithHeuristicFallback(lines: [String]) -> [RecipeLineClassification] {
        var results: [RecipeLineClassification] = []
        results.reserveCapacity(lines.count)

        var previousWasNoteHeader = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                results.append(RecipeLineClassification(line: line, label: .junk, confidence: 0.99))
                previousWasNoteHeader = false
                continue
            }

            let classification = classifySingleHeuristic(trimmed, previousWasNoteHeader: previousWasNoteHeader)
            results.append(classification)
            previousWasNoteHeader = looksLikeStandaloneNoteHeader(trimmed)
        }

        return results
    }

    nonisolated private func classifySingleHeuristic(_ line: String, previousWasNoteHeader: Bool) -> RecipeLineClassification {
        let lowered = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if looksLikeHTMLArtifact(lowered) {
            return RecipeLineClassification(line: line, label: .junk, confidence: 0.99)
        }

        if isIngredientSectionHeader(line) || isStepsSectionHeader(line) || isNotesSectionHeader(line) {
            return RecipeLineClassification(line: line, label: .header, confidence: 0.99)
        }

        if looksLikeStandaloneHeader(line) {
            return RecipeLineClassification(line: line, label: .header, confidence: 0.93)
        }

        if previousWasNoteHeader {
            return RecipeLineClassification(line: line, label: .note, confidence: 0.90)
        }

        if looksLikeInlineNote(line) {
            return RecipeLineClassification(line: line, label: .note, confidence: 0.97)
        }

        if looksLikeIngredientLine(line) {
            return RecipeLineClassification(line: line, label: .ingredient, confidence: 0.94)
        }

        if looksLikeStepLine(line) {
            return RecipeLineClassification(line: line, label: .step, confidence: 0.92)
        }

        if looksLikeTitle(line) {
            return RecipeLineClassification(line: line, label: .title, confidence: 0.78)
        }

        if ingredientHints.contains(where: { lowered.contains($0) }) {
            return RecipeLineClassification(line: line, label: .ingredient, confidence: 0.70)
        }

        return RecipeLineClassification(line: line, label: .step, confidence: 0.60)
    }

    nonisolated private func headerSection(from text: String) -> RuntimeSection? {
        let key = runtimeHeaderKey(text)
        if ingredientHeaderKeywords.contains(key) {
            return .ingredients
        }
        if stepHeaderKeywords.contains(key) {
            return .steps
        }
        if notePrefixes.contains(where: { key == $0 }) {
            return .notes
        }
        return nil
    }

    nonisolated private func runtimeHeaderKey(_ text: String) -> String {
        var lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lowered = FeatureTextUtils.regexReplacing(pattern: #"^[\W_]+|[\W_]+$"#, in: lowered, with: "")
        if lowered.hasSuffix(":") {
            lowered = String(lowered.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lowered
    }

    nonisolated private func looksLikeNoteHeader(_ text: String) -> Bool {
        let normalized = runtimeHeaderKey(text)
        return notePrefixes.contains(where: { normalized == $0 })
    }

    nonisolated private func looksLikeStandaloneHeaderCandidate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":") else { return false }
        let withoutColon = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = withoutColon.split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.count <= 7 && trimmed.count <= 90
    }

    nonisolated private func looksLikeTitleLine(_ text: String, index: Int) -> Bool {
        guard index == 0 else { return false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasSuffix(":"), trimmed.count <= 110 else {
            return false
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...14).contains(words.count) else {
            return false
        }
        let lowered = trimmed.lowercased()
        for token in ["ingredient", "instruction", "direction", "method", "step"] where lowered.contains(token) {
            return false
        }
        if trimmed.contains(".") {
            return false
        }
        return true
    }

    nonisolated private func isActionPrefixed(_ normalized: String) -> Bool {
        actionPrefixes.contains(where: { normalized.hasPrefix($0 + " ") })
    }

    nonisolated private func isIngredientSectionHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("ingredient") && lowercased.count < 50
    }

    nonisolated private func isStepsSectionHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        if looksLikeNumberedStep(line) {
            return false
        }

        let keywords = ["instruction", "direction", "method", "how to", "preparation"]
        if keywords.contains(where: { lowercased.contains($0) }) {
            return true
        }
        if lowercased.contains("step") && lowercased.count < 50 {
            return true
        }
        return false
    }

    nonisolated private func isNotesSectionHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = lowercased.hasSuffix(":") ? String(lowercased.dropLast()) : lowercased
        return notePrefixes.contains(where: { normalized == $0 || normalized == $0 + "s" })
    }

    nonisolated private func looksLikeNumberedStep(_ line: String) -> Bool {
        let patterns = [
            #"^\d+\.\s+"#,
            #"^\d+\)\s+"#,
            #"^\d+\s+-\s+"#,
            #"^\d+:\s+"#,
            #"^Step\s+\d+[.):]\s+"#
        ]

        for pattern in patterns {
            if line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return line.count > 5
            }
        }

        return false
    }

    nonisolated private func looksLikeHTMLArtifact(_ lowercasedLine: String) -> Bool {
        if lowercasedLine.hasPrefix("<") && lowercasedLine.hasSuffix(">") {
            return true
        }
        return lowercasedLine.contains("<div") || lowercasedLine.contains("</") || lowercasedLine.contains("class=")
    }

    nonisolated private func looksLikeStandaloneHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(":"), trimmed.count <= 32 else {
            return false
        }

        let withoutColon = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutColon.isEmpty else {
            return false
        }

        if withoutColon.rangeOfCharacter(from: .decimalDigits) != nil {
            return false
        }

        return true
    }

    nonisolated private func looksLikeInlineNote(_ line: String) -> Bool {
        let lowercased = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return notePrefixes.contains { prefix in
            lowercased.hasPrefix(prefix + ":") || lowercased.hasPrefix(prefix + " ")
        }
    }

    nonisolated private func looksLikeStandaloneNoteHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = lowercased.hasSuffix(":") ? String(lowercased.dropLast()) : lowercased
        return notePrefixes.contains { normalized == $0 }
    }

    nonisolated private func looksLikeIngredientLine(_ line: String) -> Bool {
        let normalized = line
            .replacingOccurrences(of: #"^[•●○◦▪▫\-]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.range(of: #"^[\d½¼¾⅓⅔⅛⅜⅝⅞/.\-]+\s+"#, options: .regularExpression) != nil {
            return true
        }

        let lowercased = normalized.lowercased()
        if ingredientHints.contains(where: { lowercased.contains($0) }) {
            return true
        }

        return false
    }

    nonisolated private func looksLikeStepLine(_ line: String) -> Bool {
        if looksLikeNumberedStep(line) {
            return true
        }

        let lowercased = line.lowercased()
        let tokens = lowercased
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        if instructionKeywords.contains(where: { tokens.contains($0) }) {
            return true
        }

        let words = lowercased
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        return words.count >= 8
    }

    nonisolated private func looksLikeTitle(_ line: String) -> Bool {
        guard !line.contains(":"),
              line.rangeOfCharacter(from: .decimalDigits) == nil else {
            return false
        }

        let words = line
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard (2...6).contains(words.count) else {
            return false
        }

        return line == line.capitalized
    }
}
