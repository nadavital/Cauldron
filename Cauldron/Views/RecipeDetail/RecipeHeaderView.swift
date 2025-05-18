import SwiftUI

struct RecipeHeaderView: View {
    var name: String
    var imageData: Data?
    var height: CGFloat = 450
    @Binding var dominantColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: height)
                    .clipped()
                    .onAppear {
                        extractImageColors(from: uiImage)
                    }
            } else {
                // Enhanced placeholder that matches app style
                VStack(spacing: 16) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text(name.isEmpty ? "Untitled Recipe" : name)
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(width: geometry.size.width, height: height)
                .background(Color.accentColor.opacity(0.3))
                .onAppear {
                    dominantColor = Color.accentColor.opacity(0.3)
                }
            }
        }
        .frame(height: height)
    }
    
    // Improved function to extract colors from image
    private func extractImageColors(from image: UIImage) {
        // Create a thumbnail for faster processing
        let targetSize = CGSize(width: 100, height: 100)
        
        // Create the thumbnail
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        guard let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return
        }
        UIGraphicsEndImageContext()
        
        // Get the CIImage
        guard let ciImage = CIImage(image: thumbnailImage) else {
            return
        }
        
        // Create a color analyzer
        let extractor = ColorExtractor()
        
        // Extract colors
        Task {
            let extractedColor = await extractor.extractDominantColor(from: ciImage)
            
            // Update UI on main thread with more pronounced opacity
            DispatchQueue.main.async {
                dominantColor = extractedColor.opacity(0.35)
            }
        }
    }
}

// Color extraction helper class
class ColorExtractor {
    func extractDominantColor(from ciImage: CIImage) async -> Color {
        // Default fallback color
        var resultColor = Color.accentColor
        
        // Bottom half of the image often has better colors for background
        let cropRect = CGRect(
            x: 0,
            y: ciImage.extent.height / 2,
            width: ciImage.extent.width,
            height: ciImage.extent.height / 2
        )
        let croppedImage = ciImage.cropped(to: cropRect)
        
        // Use Core Image to get the average color
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(croppedImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: croppedImage.extent), forKey: "inputExtent")
        
        guard let outputImage = filter?.outputImage else {
            return resultColor
        }
        
        // Convert to CGImage
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return resultColor
        }
        
        // Get pixel data
        guard let imageData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(imageData) else {
            return resultColor
        }
        
        // Convert to RGB
        let red = CGFloat(data[0]) / 255.0
        let green = CGFloat(data[1]) / 255.0
        let blue = CGFloat(data[2]) / 255.0
        
        // Adjust color brightness and boost saturation
        let brightness = (red + green + blue) / 3.0
        
        if brightness < 0.1 {
            // Too dark, lighten it
            resultColor = Color(red: min(red * 3.5, 1.0),
                             green: min(green * 3.5, 1.0),
                             blue: min(blue * 3.5, 1.0))
        } else if brightness > 0.85 {
            // Too light, add more saturation and darken slightly
            resultColor = Color(red: red * 0.7,
                             green: green * 0.7,
                             blue: blue * 0.7)
        } else {
            // Good brightness, enhance saturation
            // Find the average color value
            let avg = (red + green + blue) / 3.0
            
            // Calculate saturation boost for each channel
            let enhancedRed = boostSaturation(red, average: avg, factor: 1.5)
            let enhancedGreen = boostSaturation(green, average: avg, factor: 1.5)
            let enhancedBlue = boostSaturation(blue, average: avg, factor: 1.5)
            
            resultColor = Color(red: Double(enhancedRed),
                             green: Double(enhancedGreen),
                             blue: Double(enhancedBlue))
        }
        
        return resultColor
    }
    
    // Helper function to boost saturation
    private func boostSaturation(_ value: CGFloat, average: CGFloat, factor: CGFloat) -> CGFloat {
        // Move the value away from the average to increase saturation
        let distance = value - average
        let enhanced = average + (distance * factor)
        // Clamp to valid range
        return max(0, min(enhanced, 1.0))
    }
}

// Preview with binding
#Preview {
    struct PreviewWrapper: View {
        @State var dominantColor: Color = .clear
        
        var body: some View {
            VStack(spacing: 20) {
                RecipeHeaderView(
                    name: "Chocolate Cake",
                    imageData: UIImage(systemName: "photo.fill")?.pngData(),
                    dominantColor: $dominantColor
                )
                .frame(height: 300)
                
                RecipeHeaderView(
                    name: "Recipe without image",
                    imageData: nil,
                    height: 250,
                    dominantColor: $dominantColor
                )
            }
            .background(dominantColor)
        }
    }
    
    return PreviewWrapper()
}