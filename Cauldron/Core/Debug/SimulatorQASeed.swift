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
        username: "nadav_cooks",
        displayName: "Nadav Avital",
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
            ImageCache.shared.clear()
            try clearSeededState(in: context)
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

    private static func clearSeededState(in context: ModelContext) throws {
        let userIds = [currentUser.id, friendA.id, friendB.id]
        let recipeIds = [
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6")!
        ]
        let collectionIds = [
            UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1")!,
            UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2")!,
            UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3")!,
            UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4")!,
            UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5")!,
            UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb6")!,
            UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7")!
        ]
        let connectionIds = [
            UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-ccccccccccc1")!,
            UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-ccccccccccc2")!
        ]

        for model in try context.fetch(FetchDescriptor<UserModel>())
            where userIds.contains(model.id) {
            context.delete(model)
        }

        for model in try context.fetch(FetchDescriptor<RecipeModel>())
            where recipeIds.contains(model.id) || model.ownerId.map(userIds.contains) == true {
            context.delete(model)
        }

        for model in try context.fetch(FetchDescriptor<CollectionModel>())
            where collectionIds.contains(model.id) || userIds.contains(model.userId) {
            context.delete(model)
        }

        for model in try context.fetch(FetchDescriptor<CollectionMembershipModel>())
            where collectionIds.contains(model.collectionId) || userIds.contains(model.ownerId) {
            context.delete(model)
        }

        for model in try context.fetch(FetchDescriptor<ConnectionModel>())
            where connectionIds.contains(model.id) ||
                userIds.contains(model.fromUserId) ||
                userIds.contains(model.toUserId) {
            context.delete(model)
        }

        for model in try context.fetch(FetchDescriptor<SharedRecipeModel>()) {
            context.delete(model)
        }
    }

    private static func seedUsers(in context: ModelContext) throws {
        for user in [currentUser, friendA, friendB] {
            context.insert(UserModel.from(user))
        }
    }

    private static func seedRecipes(in context: ModelContext) throws -> [Recipe] {
        let now = Date()
        let imageURLs = try seedRecipeImages()
        let recipes = [
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
                title: "Lemon Chicken",
                ingredients: ["6 chicken thighs", "1 lb baby potatoes", "1 pint cherry tomatoes", "1 red onion", "1 lemon", "2 tsp oregano"],
                steps: ["Toss potatoes, tomatoes, onion, and lemon with olive oil.", "Nestle chicken on top and season generously.", "Roast until the chicken is golden and the potatoes are tender."],
                tags: ["Dinner", "Chicken", "One Pan"],
                ownerId: currentUser.id,
                visibility: .publicRecipe,
                updatedAt: now,
                imageURL: imageURLs.lemonChicken
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
                title: "Broccoli Pasta",
                ingredients: ["12 oz penne", "2 cups broccoli florets", "1 cup cooked chicken", "1/2 cup cream", "1/3 cup Parmesan", "1 lemon"],
                steps: ["Boil penne and add broccoli for the last two minutes.", "Warm chicken with cream, Parmesan, and lemon zest.", "Toss everything together with a splash of pasta water."],
                tags: ["Dinner", "Pasta", "Weeknight"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-3_600),
                imageURL: imageURLs.pantryPasta
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3",
                title: "Brown Butter Cookies",
                ingredients: ["1 cup browned butter", "1 cup brown sugar", "2 eggs", "2 cups flour", "1 tsp vanilla", "1 cup dark chocolate"],
                steps: ["Brown the butter and let it cool slightly.", "Mix dough and fold in chopped chocolate.", "Chill, scoop, and bake until the edges are set."],
                tags: ["Dessert", "Baking", "Cookies"],
                ownerId: friendA.id,
                visibility: .publicRecipe,
                updatedAt: now.addingTimeInterval(-7_200),
                imageURL: imageURLs.cardamomBuns,
                isPreview: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4",
                title: "Maya's Cookies",
                ingredients: ["1 cup browned butter", "1 cup brown sugar", "2 eggs", "2 cups flour", "1 tsp vanilla", "1 cup dark chocolate"],
                steps: ["Brown the butter and let it cool slightly.", "Mix dough and fold in chopped chocolate.", "Chill, scoop, and bake until the edges are set."],
                tags: ["Dessert", "Baking", "Saved"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-1_800),
                imageURL: imageURLs.savedBuns,
                originalRecipeId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3"),
                originalCreatorId: friendA.id,
                originalCreatorName: friendA.displayName,
                followsSourceUpdates: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5",
                title: "Roast Chicken",
                ingredients: ["1 roast chicken", "2 cups herbed rice", "1 cucumber salad", "1 pan roasted vegetables", "Fresh herbs"],
                steps: ["Carve the roast chicken and spoon pan juices over the top.", "Pile rice and vegetables onto a large serving platter.", "Finish with herbs and serve family style."],
                tags: ["Dinner", "Roast", "Hosting"],
                ownerId: friendB.id,
                visibility: .publicRecipe,
                updatedAt: now.addingTimeInterval(-5_400),
                imageURL: imageURLs.ramen,
                isPreview: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6",
                title: "Market Picnic Board",
                ingredients: ["1 baguette", "Seasonal fruit", "Soft cheese", "Olives", "Marcona almonds"],
                steps: ["Pack everything cold.", "Slice bread at the table.", "Serve family style."],
                tags: ["Snack", "Picnic", "Weekend"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-9_000),
                totalMinutes: 45
            )
        ]

        for recipe in recipes {
            context.insert(try RecipeModel.from(recipe))
        }

        return recipes
    }

    private static func seedCollections(recipes: [Recipe], in context: ModelContext) throws {
        let recipeByTitle = recipes.reduce(into: [String: UUID]()) { result, recipe in
            result[recipe.title] = recipe.id
        }
        let ownRecipeIds = recipes
            .filter { $0.ownerId == currentUser.id && !$0.isPreview }
            .map(\.id)
        let sharedRecipeIds = recipes
            .filter { $0.ownerId != currentUser.id }
            .map(\.id)
        let imageRecipeIds = [
            recipeByTitle["Lemon Chicken"],
            recipeByTitle["Broccoli Pasta"],
            recipeByTitle["Maya's Cookies"],
            recipeByTitle["Roast Chicken"]
        ].compactMap { $0 }

        let collections = [
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1")!,
                name: "Weeknight Dinners",
                description: "Easy dinners that still feel cooked with care.",
                userId: currentUser.id,
                recipeIds: Array(ownRecipeIds.prefix(3)),
                visibility: .privateRecipe,
                symbolName: "fork.knife",
                color: "#FF9933"
            ),
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2")!,
                name: "Saved From Friends",
                description: "Go-to dishes shared by friends.",
                userId: friendA.id,
                recipeIds: sharedRecipeIds,
                visibility: .publicRecipe,
                symbolName: "person.2.fill",
                color: "#4ECDC4"
            ),
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3")!,
                name: "Just Desserts",
                description: "Cookies, cakes, and weeknight sweets.",
                userId: currentUser.id,
                recipeIds: [recipeByTitle["Maya's Cookies"]].compactMap { $0 },
                visibility: .privateRecipe,
                symbolName: "photo",
                color: "#F06449"
            ),
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4")!,
                name: "Pasta Nights",
                description: "Fast bowls for late work nights.",
                userId: currentUser.id,
                recipeIds: [
                    recipeByTitle["Broccoli Pasta"],
                    recipeByTitle["Lemon Chicken"]
                ].compactMap { $0 },
                visibility: .privateRecipe,
                symbolName: "rectangle.split.2x1",
                color: "#5B8DEF"
            ),
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5")!,
                name: "Dinner Party",
                description: "Low-stress dishes for feeding friends.",
                userId: currentUser.id,
                recipeIds: [
                    recipeByTitle["Roast Chicken"],
                    recipeByTitle["Lemon Chicken"],
                    recipeByTitle["Broccoli Pasta"]
                ].compactMap { $0 },
                visibility: .privateRecipe,
                symbolName: "rectangle.split.3x1",
                color: "#7B61FF"
            ),
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb6")!,
                name: "Family Favorites",
                description: "Recipes everyone asks for again.",
                userId: currentUser.id,
                recipeIds: Array(imageRecipeIds.prefix(4)),
                visibility: .privateRecipe,
                symbolName: "square.grid.2x2",
                color: "#7B61FF"
            ),
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7")!,
                name: "Picnic Ideas",
                description: "Packable snacks for weekends outside.",
                userId: currentUser.id,
                recipeIds: [recipeByTitle["Market Picnic Board"]].compactMap { $0 },
                visibility: .privateRecipe,
                symbolName: "sparkles",
                color: "#2E8B57"
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
        imageURL: URL? = nil,
        totalMinutes: Int = 30,
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
            totalMinutes: totalMinutes,
            tags: tags.map { Tag(name: $0) },
            imageURL: imageURL,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: id,
            cloudImageRecordName: imageURL == nil ? nil : id,
            imageModifiedAt: imageURL == nil ? nil : updatedAt,
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

    private struct SeededRecipeImageURLs {
        let lemonChicken: URL
        let pantryPasta: URL
        let cardamomBuns: URL
        let savedBuns: URL
        let ramen: URL
    }

    private static func seedRecipeImages() throws -> SeededRecipeImageURLs {
        SeededRecipeImageURLs(
            lemonChicken: try copyBundledRecipeImage(
                resourceName: "skillet-chicken",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1.jpg"
            ),
            pantryPasta: try copyBundledRecipeImage(
                resourceName: "pantry-pasta",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA2.jpg"
            ),
            cardamomBuns: try copyBundledRecipeImage(
                resourceName: "chocolate-chip-cookie",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA3.jpg"
            ),
            savedBuns: try copyBundledRecipeImage(
                resourceName: "chocolate-chip-cookie",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA4.jpg"
            ),
            ramen: try copyBundledRecipeImage(
                resourceName: "table-dinner",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA5.jpg"
            )
        )
    }

    private static func copyBundledRecipeImage(resourceName: String, filename: String) throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecipeImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)

        guard let sourceURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "jpg",
            subdirectory: "ScreenshotSeedImages"
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: "jpg") else {
            throw CocoaError(.fileNoSuchFile)
        }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.copyItem(at: sourceURL, to: url)
        return url
    }
}
#endif
