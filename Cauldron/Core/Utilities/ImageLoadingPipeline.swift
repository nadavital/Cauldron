//
//  ImageLoadingPipeline.swift
//  Cauldron
//
//  Lightweight helpers for moving image file IO and decode work off the main actor.
//

import Foundation
import UIKit
import ImageIO

enum ImageLoadingPipelineError: Error {
    case invalidImageData
}

enum ImageLoadingPipeline {
    static func loadImage(fromFileURL url: URL, maxPixelSize: CGFloat? = nil) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let image = decodeImage(from: imageSource, maxPixelSize: maxPixelSize) else {
                        throw ImageLoadingPipelineError.invalidImageData
                    }

                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func decodeImage(from data: Data, maxPixelSize: CGFloat? = nil) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = decodeImage(from: imageSource, maxPixelSize: maxPixelSize) else {
                    continuation.resume(throwing: ImageLoadingPipelineError.invalidImageData)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    private static func decodeImage(from imageSource: CGImageSource, maxPixelSize: CGFloat?) -> UIImage? {
        let options: CFDictionary

        if let maxPixelSize, maxPixelSize > 0 {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded(.up))
            ] as CFDictionary

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
                return nil
            }

            return UIImage(cgImage: cgImage)
        }

        options = [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, options) else {
            return nil
        }

        return UIImage(
            cgImage: cgImage,
            scale: 1,
            orientation: imageOrientation(from: imageSource)
        )
    }

    static func areImagesEqual(_ image1: UIImage, _ image2: UIImage) -> Bool {
        if image1 === image2 {
            return true
        }

        guard image1.size == image2.size,
              image1.scale == image2.scale,
              image1.imageOrientation == image2.imageOrientation else {
            return false
        }

        if let leftImage = image1.cgImage, let rightImage = image2.cgImage {
            guard leftImage.width == rightImage.width,
                  leftImage.height == rightImage.height,
                  leftImage.bitsPerComponent == rightImage.bitsPerComponent,
                  leftImage.bitsPerPixel == rightImage.bitsPerPixel,
                  leftImage.bytesPerRow == rightImage.bytesPerRow,
                  leftImage.bitmapInfo == rightImage.bitmapInfo else {
                return false
            }
        }

        guard let image1Data = pixelData(for: image1),
              let image2Data = pixelData(for: image2) else {
            return false
        }

        return image1Data == image2Data
    }

    private static func imageOrientation(from imageSource: CGImageSource) -> UIImage.Orientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation] as? NSNumber,
              let cgOrientation = CGImagePropertyOrientation(rawValue: rawOrientation.uint32Value) else {
            return .up
        }

        return uiImageOrientation(from: cgOrientation)
    }

    private static func uiImageOrientation(from orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch orientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }

    private static func pixelData(for image: UIImage) -> Data? {
        if let cgImage = image.cgImage,
           let rawData = cgImage.dataProvider?.data {
            return rawData as Data
        }

        return image.pngData()
    }
}
