import Foundation

nonisolated struct LibraryArchive: Codable, Sendable {
    nonisolated static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var recipes: [PortableRecipe]
    var collections: [PortableCollection]

    nonisolated init(
        version: Int = LibraryArchive.currentVersion,
        exportedAt: Date = Date(),
        recipes: [PortableRecipe],
        collections: [PortableCollection]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.recipes = recipes
        self.collections = collections
    }
}

nonisolated struct PortableRecipe: Codable, Sendable {
    var id: UUID
    var title: String
    var ingredients: [Ingredient]
    var steps: [CookStep]
    var yields: String
    var totalMinutes: Int?
    var tags: [Tag]
    var nutrition: Nutrition?
    var sourceURL: URL?
    var sourceTitle: String?
    var notes: String?
    var isFavorite: Bool
    var visibility: RecipeVisibility
    var originalCreatorName: String?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(recipe: Recipe) {
        id = recipe.id
        title = recipe.title
        ingredients = recipe.ingredients
        steps = recipe.steps
        yields = recipe.yields
        totalMinutes = recipe.totalMinutes
        tags = recipe.tags
        nutrition = recipe.nutrition
        sourceURL = recipe.sourceURL
        sourceTitle = recipe.sourceTitle
        notes = recipe.notes
        isFavorite = recipe.isFavorite
        visibility = recipe.visibility
        originalCreatorName = recipe.originalCreatorName
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
    }

}

nonisolated struct PortableCollection: Codable, Sendable {
    var id: UUID
    var name: String
    var description: String?
    var recipeIDs: [UUID]
    var visibility: RecipeVisibility
    var emoji: String?
    var symbolName: String?
    var color: String?
    var coverImageType: CoverImageType
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(collection: Collection) {
        id = collection.id
        name = collection.name
        description = collection.description
        recipeIDs = collection.recipeIds
        visibility = collection.visibility
        emoji = collection.emoji
        symbolName = collection.symbolName
        color = collection.color
        coverImageType = collection.coverImageType
        createdAt = collection.createdAt
        updatedAt = collection.updatedAt
    }

}

actor LibraryArchiveService {
    enum ArchiveError: Error, Equatable {
        case unsupportedVersion(Int)
        case invalidRecipe(UUID)
        case duplicateRecipeID(UUID)
        case duplicateCollectionID(UUID)
    }

    private let recipeRepository: RecipeRepository
    private let collectionRepository: CollectionRepository

    init(recipeRepository: RecipeRepository, collectionRepository: CollectionRepository) {
        self.recipeRepository = recipeRepository
        self.collectionRepository = collectionRepository
    }

    func export(ownerID: UUID, now: Date = Date()) async throws -> Data {
        async let recipes = recipeRepository.fetchLibraryRecipes(ownerId: ownerID)
        async let collections = collectionRepository.fetchUserCollections(ownerId: ownerID)
        let archive = LibraryArchive(
            exportedAt: now,
            recipes: try await recipes.map(PortableRecipe.init(recipe:)),
            collections: try await collections.map(PortableCollection.init(collection:))
        )
        return try JSONEncoder.cauldronArchive.encode(archive)
    }

    func decodeAndValidate(_ data: Data) throws -> LibraryArchive {
        let archive = try JSONDecoder.cauldronArchive.decode(LibraryArchive.self, from: data)
        guard archive.version == LibraryArchive.currentVersion else {
            throw ArchiveError.unsupportedVersion(archive.version)
        }
        var recipeIDs = Set<UUID>()
        for recipe in archive.recipes {
            guard !recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !recipe.ingredients.isEmpty,
                  !recipe.steps.isEmpty else {
                throw ArchiveError.invalidRecipe(recipe.id)
            }
            guard recipeIDs.insert(recipe.id).inserted else {
                throw ArchiveError.duplicateRecipeID(recipe.id)
            }
        }
        var collectionIDs = Set<UUID>()
        for collection in archive.collections {
            guard collectionIDs.insert(collection.id).inserted else {
                throw ArchiveError.duplicateCollectionID(collection.id)
            }
        }
        return archive
    }

}

private extension JSONEncoder {
    nonisolated static var cauldronArchive: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var cauldronArchive: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
