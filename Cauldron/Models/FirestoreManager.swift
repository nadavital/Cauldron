import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class FirestoreManager: ObservableObject {
    private let db = Firestore.firestore()
    
    // MARK: - Recipe CRUD Operations
    
    /// Save a recipe to Firestore
    func saveRecipe(_ recipe: Recipe) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirestoreError.notAuthenticated
        }
        
        let recipeData = try recipe.toFirestore()
        
        try await db.collection("users")
            .document(userId)
            .collection("recipes")
            .document(recipe.id.uuidString)
            .setData(recipeData)
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