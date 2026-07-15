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
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa9")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa10")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11")!,
            UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa12")!
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
                title: "Pot Roast",
                ingredients: ["3 lb chuck roast", "3 carrots", "2 onions", "2 cups beef stock", "2 tbsp tomato paste", "Fresh thyme"],
                steps: ["Brown the roast deeply on all sides.", "Add vegetables, stock, tomato paste, and thyme.", "Braise until the meat is tender and the sauce is glossy."],
                tags: ["Dinner", "Slow Cooked", "Comfort"],
                ownerId: currentUser.id,
                visibility: .publicRecipe,
                updatedAt: now,
                imageURL: imageURLs.potRoast,
                totalMinutes: 210
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2",
                title: "Mac and Cheese",
                ingredients: ["1 lb macaroni", "3 cups sharp cheddar", "1 cup Gruyere", "3 cups milk", "3 tbsp butter", "Panko crumbs"],
                steps: ["Boil macaroni until just shy of tender.", "Whisk a creamy cheese sauce and fold in the pasta.", "Bake until bubbling with a browned top."],
                tags: ["Dinner", "Pasta", "Comfort"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-3_600),
                imageURL: imageURLs.macAndCheese,
                totalMinutes: 55
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3",
                title: "Chocolate Babka",
                ingredients: ["Enriched dough", "Chocolate filling", "Cocoa powder", "Butter", "Sugar syrup"],
                steps: ["Roll dough around the chocolate filling.", "Twist into loaves and let rise.", "Bake until glossy, then brush with syrup."],
                tags: ["Dessert", "Baking", "Shared"],
                ownerId: friendA.id,
                visibility: .publicRecipe,
                updatedAt: now.addingTimeInterval(-7_200),
                imageURL: imageURLs.babka,
                totalMinutes: 180,
                isPreview: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4",
                title: "Maya's Babka",
                ingredients: ["Enriched dough", "Chocolate filling", "Cocoa powder", "Butter", "Sugar syrup"],
                steps: ["Roll dough around the chocolate filling.", "Twist into loaves and let rise.", "Bake until glossy, then brush with syrup."],
                tags: ["Dessert", "Baking", "Saved"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-1_800),
                imageURL: imageURLs.babkaSaved,
                totalMinutes: 180,
                originalRecipeId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3"),
                originalCreatorId: friendA.id,
                originalCreatorName: friendA.displayName,
                followsSourceUpdates: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5",
                title: "Schnitzel Plate",
                ingredients: ["4 chicken cutlets", "1 cup breadcrumbs", "2 eggs", "Flour", "Lemon", "Mashed potatoes"],
                steps: ["Pound chicken cutlets thin.", "Dredge in flour, egg, and breadcrumbs.", "Fry until crisp and serve with lemon."],
                tags: ["Dinner", "Chicken", "Crispy"],
                ownerId: friendB.id,
                visibility: .publicRecipe,
                updatedAt: now.addingTimeInterval(-5_400),
                imageURL: imageURLs.schnitzel,
                isPreview: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6",
                title: "Mixed Salsas",
                ingredients: ["Tomatoes", "Corn", "Avocado", "Lime", "Cilantro", "Jalapeno"],
                steps: ["Dice vegetables into separate bowls.", "Season each salsa with lime, salt, and cilantro.", "Serve with chips or grilled meat."],
                tags: ["Snack", "Party", "Fresh"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-9_000),
                imageURL: imageURLs.mixedSalsas,
                totalMinutes: 25
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7",
                title: "Grilled Steak",
                ingredients: ["2 ribeye steaks", "Kosher salt", "Black pepper", "Garlic butter", "Rosemary"],
                steps: ["Season steaks generously.", "Sear over high heat until deeply browned.", "Rest with garlic butter before slicing."],
                tags: ["Dinner", "Grill", "Steak"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-10_800),
                imageURL: imageURLs.steak,
                totalMinutes: 35
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8",
                title: "Grandma's Challah",
                ingredients: ["Bread flour", "Eggs", "Honey", "Yeast", "Sesame seeds"],
                steps: ["Knead dough until smooth.", "Braid and proof until puffy.", "Brush with egg wash and bake."],
                tags: ["Bread", "Baking", "Family"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-12_600),
                imageURL: imageURLs.challah,
                totalMinutes: 165
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa9",
                title: "Apple Crisp",
                ingredients: ["Apples", "Brown sugar", "Oats", "Cinnamon", "Butter"],
                steps: ["Slice apples into a baking dish.", "Scatter oat crumble over the top.", "Bake until bubbling and golden."],
                tags: ["Dessert", "Fruit", "Baking"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-14_400),
                imageURL: imageURLs.appleCrisp,
                totalMinutes: 60
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa10",
                title: "Blood Orange Cake",
                ingredients: ["Blood oranges", "Flour", "Sugar", "Eggs", "Olive oil", "Vanilla"],
                steps: ["Layer sliced oranges in the pan.", "Pour olive oil cake batter over the fruit.", "Bake and invert while warm."],
                tags: ["Dessert", "Cake", "Citrus"],
                ownerId: friendA.id,
                visibility: .publicRecipe,
                updatedAt: now.addingTimeInterval(-16_200),
                imageURL: imageURLs.bloodOrangeCake,
                totalMinutes: 75,
                isPreview: true
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa11",
                title: "Friday Pizza",
                ingredients: ["Pizza dough", "Tomato sauce", "Mozzarella", "Basil", "Ricotta"],
                steps: ["Stretch dough onto a hot pan.", "Top with sauce, mozzarella, and basil.", "Bake until the crust is blistered."],
                tags: ["Dinner", "Pizza", "Weekend"],
                ownerId: currentUser.id,
                visibility: .privateRecipe,
                updatedAt: now.addingTimeInterval(-18_000),
                imageURL: imageURLs.pizza,
                totalMinutes: 40
            ),
            recipe(
                id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa12",
                title: "Moroccan Donuts",
                ingredients: ["Flour", "Yeast", "Sugar", "Warm water", "Cinnamon sugar"],
                steps: ["Mix a sticky dough and let it rise.", "Shape into rings with wet hands.", "Fry and toss in cinnamon sugar."],
                tags: ["Dessert", "Fried", "Holiday"],
                ownerId: friendB.id,
                visibility: .publicRecipe,
                updatedAt: now.addingTimeInterval(-19_800),
                imageURL: imageURLs.moroccanDonuts,
                totalMinutes: 90,
                isPreview: true
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
        let sharedRecipeIds = recipes
            .filter { $0.ownerId != currentUser.id }
            .map(\.id)
        let imageRecipeIds = [
            recipeByTitle["Pot Roast"],
            recipeByTitle["Mac and Cheese"],
            recipeByTitle["Maya's Babka"],
            recipeByTitle["Schnitzel Plate"]
        ].compactMap { $0 }

        let collections = [
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1")!,
                name: "Family Dinners",
                description: "Comfort food for slow Sundays and weeknights.",
                userId: currentUser.id,
                recipeIds: [
                    recipeByTitle["Pot Roast"],
                    recipeByTitle["Mac and Cheese"],
                    recipeByTitle["Grilled Steak"],
                    recipeByTitle["Friday Pizza"]
                ].compactMap { $0 },
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
                name: "Desserts",
                description: "Cakes, crisps, donuts, and bakes.",
                userId: currentUser.id,
                recipeIds: [
                    recipeByTitle["Maya's Babka"],
                    recipeByTitle["Apple Crisp"],
                    recipeByTitle["Blood Orange Cake"],
                    recipeByTitle["Moroccan Donuts"]
                ].compactMap { $0 },
                visibility: .privateRecipe,
                symbolName: "photo",
                color: "#F06449"
            ),
            Collection(
                id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4")!,
                name: "Bakes",
                description: "Breads and sweets worth sharing.",
                userId: currentUser.id,
                recipeIds: [
                    recipeByTitle["Grandma's Challah"],
                    recipeByTitle["Maya's Babka"],
                    recipeByTitle["Apple Crisp"]
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
                    recipeByTitle["Mixed Salsas"],
                    recipeByTitle["Pot Roast"],
                    recipeByTitle["Grilled Steak"],
                    recipeByTitle["Blood Orange Cake"]
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
                name: "Party Snacks",
                description: "Small plates for people hovering near the table.",
                userId: currentUser.id,
                recipeIds: [
                    recipeByTitle["Mixed Salsas"],
                    recipeByTitle["Friday Pizza"],
                    recipeByTitle["Moroccan Donuts"]
                ].compactMap { $0 },
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
        let appleCrisp: URL
        let babka: URL
        let babkaSaved: URL
        let bloodOrangeCake: URL
        let challah: URL
        let macAndCheese: URL
        let mixedSalsas: URL
        let moroccanDonuts: URL
        let pizza: URL
        let potRoast: URL
        let schnitzel: URL
        let steak: URL
    }

    private static func seedRecipeImages() throws -> SeededRecipeImageURLs {
        SeededRecipeImageURLs(
            appleCrisp: try copyBundledRecipeImage(
                resourceName: "apple crisp",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA9.jpg"
            ),
            babka: try copyBundledRecipeImage(
                resourceName: "babka",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA3.jpg"
            ),
            babkaSaved: try copyBundledRecipeImage(
                resourceName: "babka",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA4.jpg"
            ),
            bloodOrangeCake: try copyBundledRecipeImage(
                resourceName: "blood orange upside down cake",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA10.jpg"
            ),
            challah: try copyBundledRecipeImage(
                resourceName: "challah",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA8.jpg"
            ),
            macAndCheese: try copyBundledRecipeImage(
                resourceName: "mac n cheese",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA2.jpg"
            ),
            mixedSalsas: try copyBundledRecipeImage(
                resourceName: "mixed salsas",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA6.jpg"
            ),
            moroccanDonuts: try copyBundledRecipeImage(
                resourceName: "moroccan donuts",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA12.jpg"
            ),
            pizza: try copyBundledRecipeImage(
                resourceName: "pizza",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA11.jpg"
            ),
            potRoast: try copyBundledRecipeImage(
                resourceName: "pot roast",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1.jpg"
            ),
            schnitzel: try copyBundledRecipeImage(
                resourceName: "schnitzel",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA5.jpg"
            ),
            steak: try copyBundledRecipeImage(
                resourceName: "steak",
                filename: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA7.jpg"
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
            withExtension: "jpeg",
            subdirectory: "ScreenshotSeedImages"
        ) ?? Bundle.main.url(
            forResource: resourceName,
            withExtension: "jpg",
            subdirectory: "ScreenshotSeedImages"
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: "jpeg")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "jpg") else {
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
