import Foundation
import Vision
import CoreGraphics
import Darwin

private struct OCRLine {
    let text: String
    let box: CGRect
    let confidence: Float
}

private struct OCRQuality {
    let score: Double
    let lineCount: Int
    let ingredientLikeCount: Int
    let actionLikeCount: Int
    let noisyCount: Int
    let mixedIngredientActionCount: Int
}

private func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

private func sortRowMajor(_ lines: [OCRLine]) -> [OCRLine] {
    return lines.sorted { lhs, rhs in
        let lhsMidY = lhs.box.midY
        let rhsMidY = rhs.box.midY
        let rowThreshold = max(lhs.box.height, rhs.box.height) * 0.65
        if abs(lhsMidY - rhsMidY) > rowThreshold {
            // Vision coordinates use bottom-left origin, so larger Y appears first.
            return lhsMidY > rhsMidY
        }
        return lhs.box.minX < rhs.box.minX
    }
}

private func sortColumnTopToBottom(_ lines: [OCRLine]) -> [OCRLine] {
    return lines.sorted { lhs, rhs in
        if abs(lhs.box.midY - rhs.box.midY) > 0.006 {
            return lhs.box.midY > rhs.box.midY
        }
        return lhs.box.minX < rhs.box.minX
    }
}

private func normalizeLineKey(_ text: String) -> String {
    let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let collapsed = lowered.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    )
    return collapsed
}

private func dedupeLinesPreservingOrder(_ lines: [OCRLine]) -> [OCRLine] {
    var out: [OCRLine] = []
    var seen: Set<String> = []
    for line in lines {
        let key = normalizeLineKey(line.text)
        guard !key.isEmpty else {
            continue
        }
        if seen.contains(key) {
            continue
        }
        seen.insert(key)
        out.append(line)
    }
    return out
}

private func splitColumnsIfLikely(_ lines: [OCRLine]) -> (left: [OCRLine], right: [OCRLine])? {
    guard lines.count >= 8 else {
        return nil
    }

    let xPositions = lines.map { $0.box.minX }.sorted()
    guard xPositions.count >= 2 else {
        return nil
    }

    var bestGap: CGFloat = 0
    var pivot: CGFloat = 0
    for index in 1..<xPositions.count {
        let gap = xPositions[index] - xPositions[index - 1]
        if gap > bestGap {
            bestGap = gap
            pivot = (xPositions[index - 1] + xPositions[index]) / 2
        }
    }

    guard bestGap >= 0.18 else {
        return nil
    }

    let left = lines.filter { $0.box.midX <= pivot }
    let right = lines.filter { $0.box.midX > pivot }
    guard left.count >= 3, right.count >= 3 else {
        return nil
    }
    return (left: left, right: right)
}

private func orderedOCRLines(_ lines: [OCRLine]) -> [OCRLine] {
    guard !lines.isEmpty else {
        return []
    }
    if let columns = splitColumnsIfLikely(lines) {
        return sortColumnTopToBottom(columns.left) + sortColumnTopToBottom(columns.right)
    }
    return sortRowMajor(lines)
}

private func runVisionOCR(imageURL: URL, regionOfInterest: CGRect? = nil) throws -> [OCRLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.008
    request.recognitionLanguages = ["en-US"]
    if let regionOfInterest {
        request.regionOfInterest = regionOfInterest
    }

    let handler = VNImageRequestHandler(url: imageURL, options: [:])
    try handler.perform([request])

    guard let observations = request.results else {
        return []
    }
    return observations.compactMap { observation in
        guard let candidate = observation.topCandidates(1).first else {
            return nil
        }
        guard candidate.confidence >= 0.2 else {
            return nil
        }
        let cleaned = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return nil
        }
        return OCRLine(text: cleaned, box: observation.boundingBox, confidence: candidate.confidence)
    }
}

private func looksLikeIngredientLine(_ text: String) -> Bool {
    let lower = text.lowercased()
    let hasQuantityPrefix = lower.range(
        of: #"^(?:[•\-\*]\s*)?(?:\d+(?:\s+\d+/\d+)?(?:[./]\d+)?|\d+/\d+|[¼½¾⅓⅔⅛⅜⅝⅞])"#,
        options: .regularExpression
    ) != nil
    if !hasQuantityPrefix {
        return false
    }
    let hasUnit = lower.range(
        of: #"\b(?:tsp|tbsp|teaspoon|tablespoon|cup|cups|oz|ounce|ounces|lb|lbs|g|kg|ml|l|clove|cloves|can|cans|pinch|dash)\b"#,
        options: .regularExpression
    ) != nil
    return hasUnit || lower.contains("salt") || lower.contains("pepper") || lower.contains("for serving")
}

private func looksLikeActionLine(_ text: String) -> Bool {
    return text.lowercased().range(
        of: #"^(?:[•\-\*]\s*)?(?:\d+[.)]\s*)?(?:preheat|add|mix|stir|bake|cook|whisk|combine|simmer|serve|remove|heat|bring|toss|saute|sauté)\b"#,
        options: .regularExpression
    ) != nil
}

private func lineIsNoisy(_ text: String) -> Bool {
    let lower = text.lowercased()
    if lower.contains("templatelab") || lower.contains("created by") {
        return true
    }
    if lower.range(of: #"[{}<>_=]{2,}"#, options: .regularExpression) != nil {
        return true
    }
    let alphaCount = lower.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
    return alphaCount < 2
}

private func isLikelyClippedFragment(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return true
    }
    let lower = trimmed.lowercased()

    if lineIsNoisy(trimmed) {
        return true
    }
    if lower.hasPrefix("_") || lower.hasPrefix("-_") {
        return true
    }
    if lower == "se" || lower == "s" {
        return true
    }
    if lower.contains("templatelab") || lower == "created by" || lower == "created b" || lower == "templat" {
        return true
    }

    if lower.range(of: #"^[a-z]{1,6}$"#, options: .regularExpression) != nil {
        let keep = Set(["salt", "zest", "oil", "egg", "eggs", "rice"])
        if !keep.contains(lower) {
            return true
        }
    }

    // Truncated phrase tails/heads like "Add the", "Make the", "Cook the".
    let tokens = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    if tokens.count <= 3,
       lower.range(of: #"\b(?:the|and|of|to|for|with|in|on|a)$"#, options: .regularExpression) != nil,
       lower.range(of: #"\d"#, options: .regularExpression) == nil {
        return true
    }

    return false
}

private func sanitizeSplitLines(_ lines: [OCRLine]) -> [OCRLine] {
    let filtered = lines.filter { !isLikelyClippedFragment($0.text) }
    return dedupeLinesPreservingOrder(filtered)
}

private func evaluateOCRQuality(_ lines: [OCRLine]) -> OCRQuality {
    let texts = lines.map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !texts.isEmpty else {
        return OCRQuality(
            score: 0,
            lineCount: 0,
            ingredientLikeCount: 0,
            actionLikeCount: 0,
            noisyCount: 0,
            mixedIngredientActionCount: 0
        )
    }

    var ingredientLike = 0
    var actionLike = 0
    var noisy = 0
    var mixedIngredientAndAction = 0

    for text in texts {
        let ingredient = looksLikeIngredientLine(text)
        let action = looksLikeActionLine(text)
        if ingredient { ingredientLike += 1 }
        if action { actionLike += 1 }
        if ingredient && text.lowercased().range(
            of: #"\b(?:preheat|add|mix|stir|bake|cook|whisk|combine|simmer|serve|remove|heat|bring|toss|saute|sauté)\b"#,
            options: .regularExpression
        ) != nil {
            mixedIngredientAndAction += 1
        }
        if lineIsNoisy(text) { noisy += 1 }
    }

    let score = (Double(ingredientLike) * 1.6)
        + (Double(actionLike) * 1.2)
        + (Double(texts.count) * 0.25)
        - (Double(noisy) * 2.0)
        - (Double(mixedIngredientAndAction) * 1.4)

    return OCRQuality(
        score: score,
        lineCount: texts.count,
        ingredientLikeCount: ingredientLike,
        actionLikeCount: actionLike,
        noisyCount: noisy,
        mixedIngredientActionCount: mixedIngredientAndAction
    )
}

private func shouldPreferSplit(full: OCRQuality, split: OCRQuality) -> Bool {
    // Strong win for split.
    if split.score >= full.score + 1.5 {
        return true
    }

    // If full looks interwoven (ingredient+action collisions), prefer split
    // unless split quality is dramatically worse.
    if full.mixedIngredientActionCount >= 2,
       split.mixedIngredientActionCount <= max(0, full.mixedIngredientActionCount - 2),
       split.score >= full.score - 3.0 {
        return true
    }

    // Prefer split when it removes noise with similar score.
    if split.noisyCount < full.noisyCount,
       split.score >= full.score - 2.0 {
        return true
    }

    // Mild tie-breaker toward split when mixed lines improve.
    if split.score >= full.score - 0.5,
       split.mixedIngredientActionCount < full.mixedIngredientActionCount {
        return true
    }

    return false
}

private func splitColumnOCRLines(_ imageURL: URL) throws -> [OCRLine] {
    // Slight overlap helps recover lines near the gutter.
    let leftROI = CGRect(x: 0.0, y: 0.0, width: 0.56, height: 1.0)
    let rightROI = CGRect(x: 0.44, y: 0.0, width: 0.56, height: 1.0)

    let leftRaw = try runVisionOCR(imageURL: imageURL, regionOfInterest: leftROI)
    let rightRaw = try runVisionOCR(imageURL: imageURL, regionOfInterest: rightROI)

    // Do not filter by x; ROI coordinates can vary by Vision mode and filtering
    // here can accidentally drop valid lines.
    guard leftRaw.count >= 2, rightRaw.count >= 2 else {
        return []
    }

    let ordered = sortColumnTopToBottom(leftRaw) + sortColumnTopToBottom(rightRaw)
    return sanitizeSplitLines(ordered)
}

guard CommandLine.arguments.count >= 2 else {
    fail("Usage: apple_vision_ocr.swift <image_path>", code: 2)
}

let imagePath = CommandLine.arguments[1]
let imageURL = URL(fileURLWithPath: imagePath)
let modeOverride = (ProcessInfo.processInfo.environment["CAULDRON_LAB_APPLE_OCR_MODE"] ?? "auto")
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .lowercased()

do {
    let fullPassLines = try runVisionOCR(imageURL: imageURL)
    guard !fullPassLines.isEmpty else {
        fail("No text observations found", code: 3)
    }

    let orderedFull = orderedOCRLines(fullPassLines)
    let fullQuality = evaluateOCRQuality(orderedFull)

    let splitLines = try splitColumnOCRLines(imageURL)
    let chosenLines: [OCRLine]
    if modeOverride == "full" {
        chosenLines = orderedFull
    } else if modeOverride == "split" {
        chosenLines = splitLines.isEmpty ? orderedFull : splitLines
    } else if !splitLines.isEmpty {
        let splitQuality = evaluateOCRQuality(splitLines)
        chosenLines = shouldPreferSplit(full: fullQuality, split: splitQuality) ? splitLines : orderedFull
    } else {
        chosenLines = orderedFull
    }

    let text = chosenLines.map(\.text).joined(separator: "\n")
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        fail("Apple Vision OCR returned empty text", code: 4)
    }

    FileHandle.standardOutput.write(Data((trimmed + "\n").utf8))
} catch {
    fail("Apple Vision OCR failed: \(error.localizedDescription)", code: 1)
}
