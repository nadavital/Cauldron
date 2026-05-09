//
//  SimulatorQASeed.swift
//  Cauldron
//
//  Debug-only seed data for repeatable simulator release smoke checks.
//

#if DEBUG
import Foundation
import SwiftData

@MainActor
enum SimulatorQASeed {
    static let currentUser = User(
        id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        username: "nadavqa",
        displayName: "Nadav QA",
        referralCode: "QA2026",
        profileEmoji: "🍳",
        profileColor: "#FF9933"
    )

    private static let friendA = User(
        id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        username: "maya_bakes",
        displayName: "Maya Bakes",
        profileEmoji: "🥐",
        profileColor: "#4ECDC4"
    )

    private static let friendB = User(
        id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
        username: "leo_supper",
        displayName: "Leo Supper",
        profileEmoji: "🍜",
        profileColor: "#6C63FF"
    )

    private static var didSeed = false

    static func configureUserSession(_ session: CurrentUserSession) {
        session.currentUser = currentUser
        session.cloudKitAccountStatus = .available
        session.isInitialized = true
        session.needsOnboarding = false
        session.needsiCloudSignIn = false

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "hasLaunchedBefore")
        defaults.set(true, forKey: "hasSeenWelcomeScreen")
        defaults.set("1.3", forKey: "whatsNewLastSeenContentVersion")
        defaults.set(currentUser.id.uuidString, forKey: "currentUserId")
        defaults.set(currentUser.username, forKey: "currentUsername")
        defaults.set(currentUser.displayName, forKey: "currentDisplayName")
        defaults.set(currentUser.profileEmoji, forKey: "currentProfileEmoji")
        defaults.set(currentUser.profileColor, forKey: "currentProfileColor")
        defaults.set(currentUser.referralCode, forKey: "currentReferralCode")
    }

    static func seedIfNeeded(dependencies: DependencyContainer) async {
        guard !didSeed else { return }
        didSeed = true

        let context = ModelContext(dependencies.modelContainer)

        do {
            try seedUsers(in: context)
            let recipes = try seedRecipes(in: context)
            try seedCollections(recipes: recipes, in: context)
            try seedConnections(in: context)
            try seedSharedRecipes(recipes: recipes, in: context)
            try context.save()
        } catch {
            AppLogger.general.error("Simulator QA seed failed: \(error.localizedDescription)")
        }
    }

    private static func seedUsers(in context: ModelContext) throws {
        for user in [currentUser, friendA, friendB] {
            context.insert(UserModel.from(user))
        }
    }

    private static func seedRecipes(in context: ModelContext) throws -> [Recipe] {
        let now = Date()
        let recipes = [
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
                title: "Lemon Herb Chicken",
                ingredients: ["2 chicken breasts", "1 lemon", "2 tbsp olive oil", "1 tsp thyme"],
                steps: ["Season chicken with salt and thyme.", "Sear until golden.", "Finish with lemon juice."],
                tags: ["Dinner", "Weeknight", "Chicken"],
                ownerId: currentUser.id,
                visibility: .publicRecipe,
                updatedAt: now
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
                title: "Offline Pantry Pasta",
                ingredients: ["8 oz pasta", "1 can tomatoes", "2 cloves garlic", "Parmesan"],
                steps: ["Boil pasta.", "Simmer tomatoes with garlic.", "Toss pasta with sauce."],
                tags: ["Dinner", "Pasta", "Offline"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-3_600)
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3",
                title: "Shared Cardamom Buns",
                ingredients: ["3 cups flour", "1 cup milk", "2 tsp cardamom", "1 packet yeast"],
                steps: ["Mix dough.", "Proof until doubled.", "Shape buns.", "Bake until golden."],
                tags: ["Baking", "Dessert", "Brunch"],
                ownerId: friendA.id,
                visibility: .publicRecipe,
                updatedAt: now.addingTimeInterval(-7_200),
                isPreview: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4",
                title: "Saved Cardamom Buns",
                ingredients: ["3 cups flour", "1 cup milk", "2 tsp cardamom", "1 packet yeast"],
                steps: ["Mix dough.", "Proof until doubled.", "Shape buns.", "Bake until golden."],
                tags: ["Baking", "Dessert", "Saved"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-1_800),
                originalRecipeId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3"),
                originalCreatorId: friendA.id,
                originalCreatorName: friendA.displayName,
                followsSourceUpdates: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5",
                title: "Miso Mushroom Ramen",
                ingredients: ["4 cups stock", "2 tbsp miso", "6 oz mushrooms", "2 packs noodles"],
                steps: ["Simmer mushrooms in stock.", "Whisk in miso.", "Cook noodles and assemble bowls."],
                tags: ["Dinner", "Soup", "Vegetarian"],
                ownerId: friendB.id,
                visibility: .publicRecipe,
                updatedAt: now.addingTimeInterval(-5_400),
                isPreview: true
            )
        ]

        for recipe in recipes {
            context.insert(try RecipeModel.from(recipe))
        }

        return recipes
    }

    private static func seedCollections(recipes: [Recipe], in context: ModelContext) throws {
        let ownRecipeIds = recipes
            .filter { $0.ownerId == currentUser.id && !$0.isPreview }
            .map(\.id)
        let sharedRecipeIds = recipes
            .filter { $0.ownerId != currentUser.id }
            .map(\.id)

        let collections = [
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1")!,
                name: "Weeknight Wins",
                description: "Fast dinners used for simulator layout checks.",
                userId: currentUser.id,
                recipeIds: ownRecipeIds,
                visibility: .privateRecipe,
                symbolName: "fork.knife",
                color: "#FF9933"
            ),
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2")!,
                name: "Friends' Favorites",
                description: "Shared recipes for wide-screen collection cards.",
                userId: friendA.id,
                recipeIds: sharedRecipeIds,
                visibility: .publicRecipe,
                symbolName: "person.2.fill",
                color: "#4ECDC4"
            )
        ]

        for collection in collections {
            context.insert(try CollectionModel.from(collection))
        }
    }

    private static func seedConnections(in context: ModelContext) throws {
        let now = Date()
        let connections = [
            Connection(
                id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-ccccccccccc1")!,
                fromUserId: currentUser.id,
                toUserId: friendA.id,
                status: .accepted,
                createdAt: now.addingTimeInterval(-86_400 * 8),
                updatedAt: now.addingTimeInterval(-86_400 * 8),
                fromUsername: currentUser.username,
                fromDisplayName: currentUser.displayName,
                toUsername: friendA.username,
                toDisplayName: friendA.displayName
            ),
            Connection(
                id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-ccccccccccc2")!,
                fromUserId: friendB.id,
                toUserId: currentUser.id,
                status: .pending,
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-86_400),
                fromUsername: friendB.username,
                fromDisplayName: friendB.displayName,
                toUsername: currentUser.username,
                toDisplayName: currentUser.displayName
            )
        ]

        for connection in connections {
            context.insert(ConnectionModel.from(connection))
        }
    }

    private static func seedSharedRecipes(recipes: [Recipe], in context: ModelContext) throws {
        let sharedRecipes = recipes
            .filter { $0.ownerId != currentUser.id }
            .map { recipe in
                SharedRecipe(
                    id: UUID(),
                    recipe: recipe,
                    sharedBy: recipe.ownerId == friendA.id ? friendA : friendB,
                    sharedAt: recipe.updatedAt
                )
            }

        for sharedRecipe in sharedRecipes {
            context.insert(try SharedRecipeModel.from(sharedRecipe))
        }
    }

    private static func recipe(
        id: String,
        title: String,
        ingredients: [String],
        steps: [String],
        tags: [String],
        ownerId: UUID,
        visibility: RecipeVisibility,
        updatedAt: Date,
        isPreview: Bool = false,
        originalRecipeId: UUID? = nil,
        originalCreatorId: UUID? = nil,
        originalCreatorName: String? = nil,
        followsSourceUpdates: Bool = false
    ) -> Recipe {
        Recipe(
            id: UUID(uuidString: id)!,
            title: title,
            ingredients: ingredients.map { Ingredient(name: $0) },
            steps: steps.enumerated().map { CookStep(index: $0.offset, text: $0.element) },
            yields: "4 servings",
            totalMinutes: 30,
            tags: tags.map { Tag(name: $0) },
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: id,
            createdAt: updatedAt.addingTimeInterval(-86_400 * 5),
            updatedAt: updatedAt,
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: originalRecipeId == nil ? nil : updatedAt,
            sourceRecipeUpdatedAt: originalRecipeId == nil ? nil : updatedAt.addingTimeInterval(-1_200),
            followsSourceUpdates: followsSourceUpdates,
            isPreview: isPreview
        )
    }
}
#endif
