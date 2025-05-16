import SwiftUI
import Foundation

// Helper for loading sample images for previews
struct SampleImageLoader {
    static func loadSampleImage(named: String) -> Data? {
        guard let image = UIImage(named: named) else { return nil }
        return image.jpegData(compressionQuality: 0.8)
    }
    
    // Load a random food image from included assets or a specific one
    static func randomFoodImage() -> Data? {
        let images = ["meal_breakfast", "meal_lunch", "meal_dinner", "meal_dessert"]
        let randomImage = images.randomElement() ?? "meal_breakfast"
        return loadSampleImage(named: randomImage)
    }
    
    // Generate a solid-color image for previews when assets aren't available
    static func generateColorImage(color: UIColor, size: CGSize = CGSize(width: 300, height: 300)) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 1.0)
    }
    
    // Sample breakfast image (orange-yellow)
    static var breakfastImage: Data? {
        return generateColorImage(color: UIColor(red: 1.0, green: 0.8, blue: 0.4, alpha: 1.0))
    }
    
    // Sample dinner image (deep red)
    static var dinnerImage: Data? {
        return generateColorImage(color: UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0))
    }
}