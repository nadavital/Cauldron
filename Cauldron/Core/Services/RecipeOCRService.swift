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

        let sortedObservations = observations.sorted { lhs, rhs in
            let lhsMidY = lhs.boundingBox.midY
            let rhsMidY = rhs.boundingBox.midY
            let rowThreshold = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.65

            // Vision's coordinate system has origin at bottom-left; higher Y appears earlier.
            if abs(lhsMidY - rhsMidY) > rowThreshold {
                return lhsMidY > rhsMidY
            }

            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        let lines = sortedObservations.compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            guard candidate.confidence >= 0.2 else { return nil }

            let cleaned = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        let text = lines.filter { !$0.isEmpty }.joined(separator: "\n")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeOCRError.noTextFound
        }

        return text
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
