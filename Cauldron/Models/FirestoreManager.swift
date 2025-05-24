import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit

@MainActor
class FirestoreManager: ObservableObject {
    private let db = Firestore.firestore()
    
    // MARK: - Image Processing
    
    /// Compress and resize image data to fit within Firestore's 1MB limit
    private func processImageData(_ imageData: Data) -> Data? {
        guard let uiImage = UIImage(data: imageData) else { return nil }
        
        // Target size - must account for base64 encoding overhead (~33% increase)
        // Firestore limit is ~1MB, so target ~650KB to leave buffer after base64 encoding
        let maxFileSize = 650_000 // 650KB to account for base64 overhead
        
        // Start with more conservative dimensions
        let maxDimensions: [CGFloat] = [600, 500, 400, 300]
        
        for maxDimension in maxDimensions {
            let resizedImage = resizeImage(uiImage, maxDimension: maxDimension)
            
            // Try different compression qualities
            let qualities: [CGFloat] = [0.7, 0.5, 0.3, 0.2, 0.1]
            
            for quality in qualities {
                if let compressedData = resizedImage.jpegData(compressionQuality: quality),
                   compressedData.count <= maxFileSize {
                    print("Successfully compressed to \(compressedData.count) bytes at \(maxDimension)px with \(Int(quality * 100))% quality")
                    return compressedData
                }
            }
        }
        
        // If still too large, try extremely aggressive compression
        let tinyImage = resizeImage(uiImage, maxDimension: 200)
        if let finalAttempt = tinyImage.jpegData(compressionQuality: 0.1),
           finalAttempt.count <= maxFileSize {
            print("Used extremely aggressive compression: \(finalAttempt.count) bytes at 200px")
            return finalAttempt
        }
        
        print("Failed to compress image below \(maxFileSize) bytes, removing image")
        return nil
    }
    
    /// Resize image to fit within maximum dimension while maintaining aspect ratio
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        // Calculate the scaling factor
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        
        // If image is already smaller than max dimension, return original
        if scale >= 1.0 {
            return image
        }
        
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        // Create the resized image
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage
    }
    
    // MARK: - Recipe CRUD Operations
    
    /// Save a recipe to Firestore
    func saveRecipe(_ recipe: Recipe) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirestoreError.notAuthenticated
        }
        
        // Process the recipe to compress images if needed
        let processedRecipe = await processRecipeForFirestore(recipe)
        let recipeData = try processedRecipe.toFirestore()
        
        try await db.collection("users")
            .document(userId)
            .collection("recipes")
            .document(recipe.id.uuidString)
            .setData(recipeData)
    }
    
    /// Process recipe to compress images before saving
    private func processRecipeForFirestore(_ recipe: Recipe) async -> Recipe {
        var processedRecipe = recipe
        
        // Process image data if present
        if let imageData = recipe.imageData {
            if let compressedData = processImageData(imageData) {
                // Verify base64 size will be under limit
                let base64String = compressedData.base64EncodedString()
                let base64Size = base64String.count
                
                if base64Size <= 1_048_487 { // Firestore's actual limit
                    processedRecipe.imageData = compressedData
                    print("✅ Image compressed from \(imageData.count) bytes to \(compressedData.count) bytes (base64: \(base64Size) bytes)")
                } else {
                    print("❌ Base64 encoded image still too large (\(base64Size) bytes), removing image")
                    processedRecipe.imageData = nil
                }
            } else {
                print("❌ Failed to compress image, removing image data")
                processedRecipe.imageData = nil
            }
        }
        
        return processedRecipe
    }
    
    /// Load all recipes for the current user
    func loadRecipes() async throws -> [Recipe] {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirestoreError.notAuthenticated
        }
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("recipes")
            .getDocuments()
        
        return try snapshot.documents.compactMap { document in
            try Recipe.fromFirestore(document.data(), id: document.documentID)
        }
    }
    
    /// Delete a recipe from Firestore
    func deleteRecipe(id: UUID) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirestoreError.notAuthenticated
        }
        
        try await db.collection("users")
            .document(userId)
            .collection("recipes")
            .document(id.uuidString)
            .delete()
    }
    
    /// Update an existing recipe
    func updateRecipe(_ recipe: Recipe) async throws {
        // Same as saving - Firestore will overwrite existing document
        try await saveRecipe(recipe)
    }
}

// MARK: - Firestore Error Types
enum FirestoreError: LocalizedError {
    case notAuthenticated
    case dataCorrupted
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .dataCorrupted:
            return "Recipe data is corrupted"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Recipe Firestore Extensions
extension Recipe {
    /// Convert Recipe to Firestore data format
    func toFirestore() throws -> [String: Any] {
        var data: [String: Any] = [
            "name": name,
            "ingredients": ingredients.map { $0.toFirestore() },
            "instructions": instructions,
            "prepTime": prepTime,
            "cookTime": cookTime,
            "servings": servings,
            "tags": Array(tags),
            "description": description,
            "createdAt": Timestamp(),
            "updatedAt": Timestamp()
        ]
        
        // Convert image data to base64 string for Firestore storage
        if let imageData = imageData {
            data["imageData"] = imageData.base64EncodedString()
        }
        
        return data
    }
    
    /// Create Recipe from Firestore data
    static func fromFirestore(_ data: [String: Any], id: String) throws -> Recipe {
        guard let name = data["name"] as? String,
              let ingredientsData = data["ingredients"] as? [[String: Any]],
              let instructions = data["instructions"] as? [String],
              let prepTime = data["prepTime"] as? Int,
              let cookTime = data["cookTime"] as? Int,
              let servings = data["servings"] as? Int,
              let tagsArray = data["tags"] as? [String],
              let description = data["description"] as? String else {
            throw FirestoreError.dataCorrupted
        }
        
        let ingredients = try ingredientsData.map { try Ingredient.fromFirestore($0) }
        let tags = Set(tagsArray)
        
        // Convert base64 string back to Data if present
        var imageData: Data? = nil
        if let imageString = data["imageData"] as? String {
            imageData = Data(base64Encoded: imageString)
        }
        
        guard let recipeId = UUID(uuidString: id) else {
            throw FirestoreError.dataCorrupted
        }
        
        return Recipe(
            id: recipeId,
            name: name,
            ingredients: ingredients,
            instructions: instructions,
            prepTime: prepTime,
            cookTime: cookTime,
            servings: servings,
            imageData: imageData,
            tags: tags,
            description: description
        )
    }
}

// MARK: - Ingredient Firestore Extensions
extension Ingredient {
    /// Convert Ingredient to Firestore data format
    func toFirestore() -> [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "quantity": quantity,
            "unit": unit.rawValue
        ]
        
        // Add custom unit name if present
        if let customUnitName = customUnitName {
            data["customUnitName"] = customUnitName
        }
        
        return data
    }
    
    /// Create Ingredient from Firestore data
    static func fromFirestore(_ data: [String: Any]) throws -> Ingredient {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = data["name"] as? String,
              let quantity = data["quantity"] as? Double,
              let unitString = data["unit"] as? String,
              let unit = MeasurementUnit(rawValue: unitString) else {
            throw FirestoreError.dataCorrupted
        }
        
        // Get custom unit name if available
        let customUnitName = data["customUnitName"] as? String
        
        return Ingredient(id: id, name: name, quantity: quantity, unit: unit, customUnitName: customUnitName)
    }
}