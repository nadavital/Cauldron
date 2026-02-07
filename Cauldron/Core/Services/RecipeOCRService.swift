//
//  RecipeOCRService.swift
//  Cauldron
//
//  OCR extraction for recipe imports from photos.
//

import Foundation
import UIKit
import Vision

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
        guard let cgImage = image.cgImage else {
            throw RecipeOCRError.unsupportedImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.015

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            throw RecipeOCRError.noTextFound
        }

        let lines = observations.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        let text = lines.filter { !$0.isEmpty }.joined(separator: "\n")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeOCRError.noTextFound
        }

        return text
    }
}
