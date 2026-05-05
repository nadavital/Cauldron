//
//  RecipeDiscoveryCache.swift
//  Cauldron
//
//  Shared read-through cache for public recipe browsing surfaces.
//

import Foundation

actor RecipeDiscoveryCache {
    private struct CacheEntry<Value> {
        let value: Value
        let fetchedAt: Date
    }

    private let recipeCloudService: RecipeCloudService
    private let userCloudService: UserCloudService
    private let cacheValidityDuration: TimeInterval

    private var publicRecipesById: [UUID: CacheEntry<Recipe>] = [:]
    private var publicRecipeQueries: [String: CacheEntry<[Recipe]>] = [:]
    private var publicRecipeSummaryQueries: [String: CacheEntry<[RecipeSummary]>] = [:]
    private var popularRecipesByLimit: [Int: CacheEntry<[Recipe]>] = [:]
    private var usersById: [UUID: CacheEntry<User>] = [:]
    private var publicRecipeCountsByOwnerId: [UUID: CacheEntry<Int>] = [:]

    init(
        recipeCloudService: RecipeCloudService,
        userCloudService: UserCloudService,
        cacheValidityDuration: TimeInterval = 5 * 60
    ) {
        self.recipeCloudService = recipeCloudService
        self.userCloudService = userCloudService
        self.cacheValidityDuration = cacheValidityDuration
    }

    func clear() {
        publicRecipesById.removeAll()
        publicRecipeQueries.removeAll()
        publicRecipeSummaryQueries.removeAll()
        popularRecipesByLimit.removeAll()
        usersById.removeAll()
        publicRecipeCountsByOwnerId.removeAll()
    }

    func fetchPublicRecipe(
        id: UUID,
        forceRefresh: Bool = false
    ) async throws -> Recipe? {
        if !forceRefresh, let cached = freshValue(publicRecipesById[id]) {
            return cached
        }

        guard let recipe = try await recipeCloudService.fetchPublicRecipe(id: id) else {
            return nil
        }

        store(recipe)
        return recipe
    }

    func fetchPublicRecipes(
        ids: [UUID],
        forceRefresh: Bool = false
    ) async throws -> [UUID: Recipe] {
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty else { return [:] }

        var recipesById: [UUID: Recipe] = [:]
        var missingIds: [UUID] = []

        for id in uniqueIds {
            if !forceRefresh, let cached = freshValue(publicRecipesById[id]) {
                recipesById[id] = cached
            } else {
                missingIds.append(id)
            }
        }

        if !missingIds.isEmpty {
            let fetchedRecipesById = try await recipeCloudService.fetchPublicRecipes(ids: missingIds)
            for (id, recipe) in fetchedRecipesById {
                store(recipe)
                recipesById[id] = recipe
            }
        }

        return recipesById
    }

    func querySharedRecipes(
        ownerIds: [UUID]?,
        visibility: RecipeVisibility,
        requiredTag: String? = nil,
        includeDerivedCopies: Bool = true,
        limit: Int = 100,
        forceRefresh: Bool = false
    ) async throws -> [Recipe] {
        if let ownerIds, ownerIds.isEmpty {
            return []
        }

        let key = queryKey(
            prefix: "recipes",
            ownerIds: ownerIds,
            visibility: visibility,
            requiredTag: requiredTag,
            includeDerivedCopies: includeDerivedCopies,
            limit: limit
        )

        if !forceRefresh, let cached = freshValue(publicRecipeQueries[key]) {
            return cached
        }

        let recipes = try await recipeCloudService.querySharedRecipes(
            ownerIds: ownerIds,
            visibility: visibility,
            requiredTag: requiredTag,
            includeDerivedCopies: includeDerivedCopies,
            limit: limit
        )

        store(recipes)
        publicRecipeQueries[key] = CacheEntry(value: recipes, fetchedAt: Date())
        return recipes
    }

    func querySharedRecipeSummaries(
        ownerIds: [UUID]?,
        visibility: RecipeVisibility,
        requiredTag: String? = nil,
        includeDerivedCopies: Bool = true,
        limit: Int = 100,
        forceRefresh: Bool = false
    ) async throws -> [RecipeSummary] {
        if let ownerIds, ownerIds.isEmpty {
            return []
        }

        let key = queryKey(
            prefix: "summaries",
            ownerIds: ownerIds,
            visibility: visibility,
            requiredTag: requiredTag,
            includeDerivedCopies: includeDerivedCopies,
            limit: limit
        )

        if !forceRefresh, let cached = freshValue(publicRecipeSummaryQueries[key]) {
            return cached
        }

        let summaries = try await recipeCloudService.querySharedRecipeSummaries(
            ownerIds: ownerIds,
            visibility: visibility,
            requiredTag: requiredTag,
            includeDerivedCopies: includeDerivedCopies,
            limit: limit
        )

        publicRecipeSummaryQueries[key] = CacheEntry(value: summaries, fetchedAt: Date())
        return summaries
    }

    func fetchPopularPublicRecipes(
        limit: Int = 20,
        forceRefresh: Bool = false
    ) async throws -> [Recipe] {
        if !forceRefresh, let cached = freshValue(popularRecipesByLimit[limit]) {
            return cached
        }

        let recipes = try await recipeCloudService.fetchPopularPublicRecipes(limit: limit)
        store(recipes)
        popularRecipesByLimit[limit] = CacheEntry(value: recipes, fetchedAt: Date())
        return recipes
    }

    func searchDiscoverablePublicRecipes(
        query: String,
        categories: [RecipeCategory],
        limit: Int = 50,
        forceRefresh: Bool = false
    ) async throws -> [Recipe] {
        let categoryKey = categories
            .map(\.tagValue)
            .map { normalizedKey($0) }
            .sorted()
            .joined(separator: ",")
        let key = [
            "search",
            "query=\(normalizedKey(query))",
            "categories=\(categoryKey)",
            "limit=\(limit)"
        ].joined(separator: "|")

        if !forceRefresh, let cached = freshValue(publicRecipeQueries[key]) {
            return cached
        }

        let recipes = try await recipeCloudService.searchDiscoverablePublicRecipes(
            query: query,
            categories: categories,
            limit: limit
        )
        store(recipes)
        publicRecipeQueries[key] = CacheEntry(value: recipes, fetchedAt: Date())
        return recipes
    }

    func fetchUsers(
        byUserIds userIds: [UUID],
        forceRefresh: Bool = false
    ) async throws -> [User] {
        let usersById = try await fetchUsersById(byUserIds: userIds, forceRefresh: forceRefresh)
        return userIds.compactMap { usersById[$0] }
    }

    func fetchUsersById(
        byUserIds userIds: [UUID],
        forceRefresh: Bool = false
    ) async throws -> [UUID: User] {
        let uniqueIds = Array(Set(userIds))
        guard !uniqueIds.isEmpty else { return [:] }

        var result: [UUID: User] = [:]
        var missingIds: [UUID] = []

        for id in uniqueIds {
            if !forceRefresh, let cached = freshValue(usersById[id]) {
                result[id] = cached
            } else {
                missingIds.append(id)
            }
        }

        if !missingIds.isEmpty {
            let fetchedUsers = try await userCloudService.fetchUsers(byUserIds: missingIds)
            for user in fetchedUsers {
                usersById[user.id] = CacheEntry(value: user, fetchedAt: Date())
                result[user.id] = user
            }
        }

        return result
    }

    func batchFetchPublicRecipeCounts(
        forOwnerIds ownerIds: [UUID],
        forceRefresh: Bool = false
    ) async throws -> [UUID: Int] {
        let uniqueOwnerIds = Array(Set(ownerIds))
        guard !uniqueOwnerIds.isEmpty else { return [:] }

        var counts: [UUID: Int] = [:]
        var missingOwnerIds: [UUID] = []

        for ownerId in uniqueOwnerIds {
            if !forceRefresh, let cached = freshValue(publicRecipeCountsByOwnerId[ownerId]) {
                counts[ownerId] = cached
            } else {
                missingOwnerIds.append(ownerId)
            }
        }

        if !missingOwnerIds.isEmpty {
            let fetchedCounts = try await recipeCloudService.batchFetchPublicRecipeCounts(
                forOwnerIds: missingOwnerIds
            )
            for ownerId in missingOwnerIds {
                let count = fetchedCounts[ownerId] ?? 0
                publicRecipeCountsByOwnerId[ownerId] = CacheEntry(value: count, fetchedAt: Date())
                counts[ownerId] = count
            }
        }

        return counts
    }

    private func freshValue<Value>(_ entry: CacheEntry<Value>?) -> Value? {
        guard let entry,
              Date().timeIntervalSince(entry.fetchedAt) < cacheValidityDuration else {
            return nil
        }

        return entry.value
    }

    private func store(_ recipe: Recipe) {
        publicRecipesById[recipe.id] = CacheEntry(value: recipe, fetchedAt: Date())
    }

    private func store(_ recipes: [Recipe]) {
        for recipe in recipes {
            store(recipe)
        }
    }

    private func queryKey(
        prefix: String,
        ownerIds: [UUID]?,
        visibility: RecipeVisibility,
        requiredTag: String?,
        includeDerivedCopies: Bool,
        limit: Int
    ) -> String {
        let ownerKey = ownerIds?
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",") ?? "*"
        let tagKey = normalizedKey(requiredTag ?? "")
        return [
            prefix,
            "owners=\(ownerKey)",
            "visibility=\(visibility.rawValue)",
            "tag=\(tagKey)",
            "derived=\(includeDerivedCopies)",
            "limit=\(limit)"
        ].joined(separator: "|")
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
