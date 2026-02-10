//
//  ProfileCacheManager.swift
//  Cauldron
//
//  Created by Nadav Avital on 11/4/25.
//

import Foundation
import os

/// Manages caching of profile data across navigation to avoid unnecessary reloads
final class ProfileCacheManager: @unchecked Sendable {
    private struct ProfileCache {
        var recipes: [SharedRecipe]
        var collections: [Collection]
        var lastRecipeLoadTime: Date
        var lastCollectionLoadTime: Date
        var connectionState: ConnectionRelationshipState
    }

    private var cache: [UUID: ProfileCache] = [:]
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    private let lock = NSLock()

    // MARK: - Recipe Caching

    func getCachedRecipes(
        for userId: UUID,
        connectionState: ConnectionRelationshipState
    ) -> [SharedRecipe]? {
        lock.lock()
        defer { lock.unlock() }

        guard let cached = cache[userId] else { return nil }

        // Check if cache is still valid
        let isCacheValid = Date().timeIntervalSince(cached.lastRecipeLoadTime) < cacheValidityDuration
        let connectionStateMatches = cached.connectionState == connectionState

        if isCacheValid && connectionStateMatches {
            AppLogger.general.info("📦 Using cached recipes for user \(userId.uuidString)")
            return cached.recipes
        }

        return nil
    }

    func cacheRecipes(
        _ recipes: [SharedRecipe],
        for userId: UUID,
        connectionState: ConnectionRelationshipState
    ) {
        lock.lock()
        defer { lock.unlock() }

        var cached = cache[userId] ?? ProfileCache(
            recipes: [],
            collections: [],
            lastRecipeLoadTime: Date(),
            lastCollectionLoadTime: Date.distantPast,
            connectionState: connectionState
        )

        cached.recipes = recipes
        cached.lastRecipeLoadTime = Date()
        cached.connectionState = connectionState

        cache[userId] = cached
        AppLogger.general.info("💾 Cached \(recipes.count) recipes for user \(userId.uuidString)")
    }

    // MARK: - Collection Caching

    func getCachedCollections(
        for userId: UUID,
        connectionState: ConnectionRelationshipState
    ) -> [Collection]? {
        lock.lock()
        defer { lock.unlock() }

        guard let cached = cache[userId] else { return nil }

        // Check if cache is still valid
        let isCacheValid = Date().timeIntervalSince(cached.lastCollectionLoadTime) < cacheValidityDuration
        let connectionStateMatches = cached.connectionState == connectionState

        if isCacheValid && connectionStateMatches {
            AppLogger.general.info("📦 Using cached collections for user \(userId.uuidString)")
            return cached.collections
        }

        return nil
    }

    func cacheCollections(
        _ collections: [Collection],
        for userId: UUID,
        connectionState: ConnectionRelationshipState
    ) {
        lock.lock()
        defer { lock.unlock() }

        var cached = cache[userId] ?? ProfileCache(
            recipes: [],
            collections: [],
            lastRecipeLoadTime: Date.distantPast,
            lastCollectionLoadTime: Date(),
            connectionState: connectionState
        )

        cached.collections = collections
        cached.lastCollectionLoadTime = Date()
        cached.connectionState = connectionState

        cache[userId] = cached
        AppLogger.general.info("💾 Cached \(collections.count) collections for user \(userId.uuidString)")
    }

    // MARK: - Cache Management

    /// Invalidate cache for a specific user (useful when connection state changes)
    func invalidateCache(for userId: UUID) {
        lock.lock()
        defer { lock.unlock() }

        cache.removeValue(forKey: userId)
        AppLogger.general.info("🗑️ Invalidated cache for user \(userId.uuidString)")
    }

    /// Clear all cached data
    func clearAllCache() {
        lock.lock()
        defer { lock.unlock() }

        cache.removeAll()
        AppLogger.general.info("🗑️ Cleared all profile cache")
    }

    /// Remove expired cache entries (called periodically)
    func cleanupExpiredCache() {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let expiredKeys = cache.filter { _, cached in
            let recipeExpired = now.timeIntervalSince(cached.lastRecipeLoadTime) >= cacheValidityDuration
            let collectionExpired = now.timeIntervalSince(cached.lastCollectionLoadTime) >= cacheValidityDuration
            return recipeExpired && collectionExpired
        }.map { $0.key }

        expiredKeys.forEach { cache.removeValue(forKey: $0) }

        if !expiredKeys.isEmpty {
            AppLogger.general.info("🗑️ Cleaned up \(expiredKeys.count) expired cache entries")
        }
    }
}
