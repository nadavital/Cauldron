//
//  RecipeOCRService.swift
//  Cauldron
//
//  OCR extraction for recipe imports from photos.
//

import Foundation
import UIKit
import Vision
import ImageIO

enum RecipeOCRError: LocalizedError {
    case unsupportedImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return "Could not read this image. Try a clearer photo."
        case .noTextFound:
            return "No readable recipe text was found in this image."
        }
    }
}

actor RecipeOCRService {
    private struct OCRLine {
        let text: String
        let box: CGRect
    }

    func extractText(from image: UIImage) async throws -> String {
        guard let (cgImage, orientation) = normalizedCGImage(from: image) else {
            throw RecipeOCRError.unsupportedImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Allow smaller text for ingredient lists photographed at a distance.
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            throw RecipeOCRError.noTextFound
        }

        let recognizedLines = observations.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            guard candidate.confidence >= 0.2 else { return nil }

            let cleaned = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return OCRLine(text: cleaned, box: observation.boundingBox)
        }
        let lines = orderedOCRLines(recognizedLines).map(\.text)
        let text = lines.filter { !$0.isEmpty }.joined(separator: "\n")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeOCRError.noTextFound
        }

        return text
    }

    private func orderedOCRLines(_ lines: [OCRLine]) -> [OCRLine] {
        guard !lines.isEmpty else { return [] }

        if let columns = splitColumnsIfLikely(lines) {
            // Read down the left column first, then down the right column.
            return sortColumnTopToBottom(columns.left) + sortColumnTopToBottom(columns.right)
        }

        return sortRowMajor(lines)
    }

    private func sortRowMajor(_ lines: [OCRLine]) -> [OCRLine] {
        return lines.sorted { lhs, rhs in
            let lhsMidY = lhs.box.midY
            let rhsMidY = rhs.box.midY
            let rowThreshold = max(lhs.box.height, rhs.box.height) * 0.65

            // Vision coordinates: origin is bottom-left; larger Y appears earlier.
            if abs(lhsMidY - rhsMidY) > rowThreshold {
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

        // Avoid splitting regular single-column captures.
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

    private func normalizedCGImage(from image: UIImage) -> (CGImage, CGImagePropertyOrientation)? {
        if let cgImage = image.cgImage {
            return (cgImage, CGImagePropertyOrientation(image.imageOrientation))
        }

        if let ciImage = image.ciImage {
            let context = CIContext(options: nil)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            return (cgImage, CGImagePropertyOrientation(image.imageOrientation))
        }

        guard let data = image.jpegData(compressionQuality: 1.0),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        return (cgImage, .up)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
