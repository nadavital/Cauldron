import SwiftUI

struct RecipeCardView: View {
    var recipe: Recipe
    @Environment(\.colorScheme) var colorScheme
    @State private var dominantColor: Color = Color(.systemGray6)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Display image or placeholder with GeometryReader
            GeometryReader { geometry in
                if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: 160)
                        .clipped()
                        .onAppear {
                            extractImageColor(from: uiImage)
                        }
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: geometry.size.width, height: 160)
                        .overlay(
                            Image(systemName: "fork.knife")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        )
                        .onAppear {
                            dominantColor = Color(.systemGray6)
                        }
                }
            }
            .frame(height: 160)
            
            // Content area with the dominant color background
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.name)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(recipe.prepTime + recipe.cookTime) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 2)
                    
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(recipe.servings)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(height: 80)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if colorScheme == .dark {
                        // Dark mode - match RecipeDetailView
                        ZStack {
                            // Base solid color with adjusted brightness
                            dominantColor
                                .opacity(0.25)
                            
                            // Subtle gradient overlay
                            LinearGradient(
                                colors: [.black.opacity(0.1), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .blendMode(.overlay)
                        }
                    } else {
                        // Light mode - dominant color with plain background
                        dominantColor.opacity(0.3)
                    }
                }
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thickMaterial)
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // Extract dominant color from image
    private func extractImageColor(from image: UIImage) {
        // Create thumbnail for faster processing
        let targetSize = CGSize(width: 40, height: 40)
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        guard let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return
        }
        UIGraphicsEndImageContext()
        
        // Extract color
        guard let cgImage = thumbnailImage.cgImage else { return }
        
        let pixelData = cgImage.dataProvider?.data
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        
        let pixelCount = targetSize.width * targetSize.height
        let bytesPerPixel = 4
        
        // Get average color from the bottom of the image
        for i in Int(pixelCount/2)..<Int(pixelCount) {
            let pixelIndex = i * Int(bytesPerPixel)
            red += CGFloat(data[pixelIndex])
            green += CGFloat(data[pixelIndex + 1])
            blue += CGFloat(data[pixelIndex + 2])
        }
        
        let sampleCount = pixelCount/2
        red /= sampleCount
        green /= sampleCount
        blue /= sampleCount
        
        // Adjust brightness and saturation
        let brightness = (red + green + blue) / (3 * 255)
        var colorAdjust: CGFloat = 1.0
        
        if brightness < 0.15 {
            colorAdjust = 3.0 // Lighten dark colors
        } else if brightness > 0.85 {
            colorAdjust = 0.7 // Darken light colors
        }
        
        DispatchQueue.main.async {
            dominantColor = Color(
                red: min(1.0, Double(red/255.0 * colorAdjust)),
                green: min(1.0, Double(green/255.0 * colorAdjust)),
                blue: min(1.0, Double(blue/255.0 * colorAdjust))
            )
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        RecipeCardView(
            recipe: Recipe(
                name: "Pancakes with Maple Syrup", 
                ingredients: [Ingredient(name: "Flour", quantity: 1.5, unit: .cups)], 
                instructions: ["Mix & Cook"], 
                prepTime: 10, 
                cookTime: 15, 
                servings: 4, 
                imageData: nil, 
                tags: ["meal_breakfast"]
            )
        )
        .frame(width: 180)
        
        RecipeCardView(
            recipe: Recipe(
                name: "Spaghetti Bolognese", 
                ingredients: [Ingredient(name: "Spaghetti", quantity: 500, unit: .grams)], 
                instructions: ["Cook & Eat"], 
                prepTime: 15, 
                cookTime: 30, 
                servings: 6, 
                imageData: UIImage(systemName: "photo")?.pngData(), 
                tags: ["cuisine_italian"]
            )
        )
        .frame(width: 180)
    }
    .padding()
    .background(Color(.systemBackground))
}