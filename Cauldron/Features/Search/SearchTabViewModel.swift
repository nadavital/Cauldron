//
//  SearchTabViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import Combine
import os

@MainActor
class SearchTabViewModel: ObservableObject {
    @Published var allRecipes: [Recipe] = []
    @Published var recipesByTag: [String: [Recipe]] = [:]
    @Published var recipeSearchResults: [Recipe] = []
    @Published var peopleSearchResults: [User] = []
    @Published var isLoading = false
    @Published var isLoadingPeople = false
    
    let dependencies: DependencyContainer
    private var recipeSearchText: String = ""
    private var peopleSearchText: String = ""
    
    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }
    
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Load all recipes
            allRecipes = try await dependencies.recipeRepository.fetchAll()
            
            // Group recipes by tags
            groupRecipesByTags()
            
            // Load users for people search
            await loadUsers()
            
        } catch {
            AppLogger.general.error("Failed to load search tab data: \(error.localizedDescription)")
        }
    }
    
    func loadUsers() async {
        isLoadingPeople = true
        defer { isLoadingPeople = false }
        
        do {
            let allUsers = try await dependencies.sharingService.getAllUsers()
            peopleSearchResults = allUsers
        } catch {
            AppLogger.general.error("Failed to load users: \(error.localizedDescription)")
            peopleSearchResults = []
        }
    }
    
    func updateRecipeSearch(_ query: String) {
        recipeSearchText = query
        
        if query.isEmpty {
            recipeSearchResults = []
        } else {
            let lowercased = query.lowercased()
            recipeSearchResults = allRecipes.filter { recipe in
                recipe.title.lowercased().contains(lowercased) ||
                recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) }) ||
                recipe.ingredients.contains(where: { $0.name.lowercased().contains(lowercased) })
            }
        }
    }
    
    func updatePeopleSearch(_ query: String) {
        peopleSearchText = query
        
        Task {
            isLoadingPeople = true
            defer { isLoadingPeople = false }
            
            do {
                peopleSearchResults = try await dependencies.sharingService.searchUsers(query)
            } catch {
                AppLogger.general.error("Failed to search users: \(error.localizedDescription)")
                peopleSearchResults = []
            }
        }
    }
    
    private func groupRecipesByTags() {
        var grouped: [String: [Recipe]] = [:]
        
        for recipe in allRecipes {
            for tag in recipe.tags {
                if grouped[tag.name] == nil {
                    grouped[tag.name] = []
                }
                // Only add if not already in this tag's list
                if !(grouped[tag.name]?.contains(where: { $0.id == recipe.id }) ?? false) {
                    grouped[tag.name]?.append(recipe)
                }
            }
        }
        
        // Store all recipes per tag
        recipesByTag = grouped
    }
}
