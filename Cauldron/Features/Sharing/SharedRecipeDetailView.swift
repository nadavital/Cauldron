//
//  SharedRecipeDetailView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import os

struct SharedRecipeDetailView: View {
    let sharedRecipe: SharedRecipe
    let dependencies: DependencyContainer
    let onCopy: () async -> Void
    let onRemove: () async -> Void

    @State private var isPerformingAction = false
    @State private var showRemoveConfirmation = false
    @State private var showCopyToast = false
    @State private var hasOwnedCopy = false
    @State private var isCheckingDuplicates = true
    @State private var showSessionConflictAlert = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero Image - Card style
                    if let imageURL = sharedRecipe.recipe.imageURL {
                        HeroRecipeImageView(imageURL: imageURL, recipeImageService: dependencies.recipeImageService)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        // Header with shared info
                        sharedInfoSection

                        // Recipe details
                        recipeInfoSection

                        // Ingredients
                        ingredientsSection

                        // Steps
                        stepsSection

                        // Notes if available
                        if let notes = sharedRecipe.recipe.notes, !notes.isEmpty {
                            notesSection(notes)
                        }
                    }
                    .padding()
                    .padding(.bottom, 100) // Add padding for the button
                }
            }

            // Liquid Glass Cook Button
            HStack {
                Spacer()

                Button {
                    handleCookButtonTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.body)

                        Text("Cook")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.tint(.orange).interactive(), in: Capsule())
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle(sharedRecipe.recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Add to My Recipes (independent recipe)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        isPerformingAction = true
                        await onCopy()
                        isPerformingAction = false

                        // Notify other views that a recipe was added
                        NotificationCenter.default.post(name: NSNotification.Name("RecipeAdded"), object: nil)

                        // Show toast notification
                        withAnimation {
                            showCopyToast = true
                        }

                        // Dismiss sheet after toast appears
                        try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
                        dismiss()
                    }
                } label: {
                    if isPerformingAction {
                        ProgressView()
                    } else if hasOwnedCopy {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Add to My Recipes", systemImage: "bookmark")
                    }
                }
                .disabled(isPerformingAction || hasOwnedCopy || isCheckingDuplicates)
            }
        }
        .confirmationDialog("Remove Shared Recipe", isPresented: $showRemoveConfirmation) {
            Button("Remove from Shared", role: .destructive) {
                Task {
                    isPerformingAction = true
                    await onRemove()
                    isPerformingAction = false
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the recipe from your shared list. You can't undo this action.")
        }
        .alert("Recipe Already Cooking", isPresented: $showSessionConflictAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End & Start New") {
                Task {
                    await dependencies.cookModeCoordinator.startPendingRecipe()
                }
            }
        } message: {
            if let currentRecipe = dependencies.cookModeCoordinator.currentRecipe {
                Text("End '\(currentRecipe.title)' to start cooking '\(sharedRecipe.recipe.title)'?")
            }
        }
        .toast(isShowing: $showCopyToast, icon: "checkmark.circle.fill", message: "Recipe added")
        .task {
            await checkForDuplicates()
        }
    }
    
    private var sharedInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.cauldronOrange)
                Text("Shared by \(sharedRecipe.sharedBy.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.cauldronOrange)
                Text(sharedRecipe.sharedAt.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("This is a read-only view. Tap 'Add to My Recipes' to save it to your library where you can edit it independently.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(Color.cauldronOrange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var recipeInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !sharedRecipe.recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sharedRecipe.recipe.tags, id: \.name) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.cauldronOrange.opacity(0.2))
                                .foregroundColor(.cauldronOrange)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            HStack(spacing: 16) {
                if let time = sharedRecipe.recipe.displayTime {
                    Label(time, systemImage: "clock")
                        .font(.subheadline)
                }
                
                Label(sharedRecipe.recipe.yields, systemImage: "person.2")
                    .font(.subheadline)
            }
            .foregroundColor(.secondary)
        }
    }
    
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(Array(sharedRecipe.recipe.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                HStack(alignment: .top) {
                    Text("•")
                        .foregroundColor(.cauldronOrange)
                    
                    Text(ingredient.displayString)
                        .font(.body)
                    
                    Spacer()
                }
            }
        }
    }
    
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instructions")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(Array(sharedRecipe.recipe.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.cauldronOrange)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.text)
                            .font(.body)
                        
                        if let timer = step.timers.first {
                            Label(timer.displayDuration, systemImage: "timer")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(notes)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }


    private func checkForDuplicates() async {
        guard let userId = CurrentUserSession.shared.userId else {
            isCheckingDuplicates = false
            return
        }

        do {
            // Check for owned copy
            hasOwnedCopy = try await dependencies.recipeRepository.hasSimilarRecipe(
                title: sharedRecipe.recipe.title,
                ownerId: userId,
                ingredientCount: sharedRecipe.recipe.ingredients.count
            )

            isCheckingDuplicates = false
            AppLogger.general.info("Duplicate check complete - hasOwnedCopy: \(hasOwnedCopy)")
        } catch {
            AppLogger.general.error("Failed to check for duplicates: \(error.localizedDescription)")
            isCheckingDuplicates = false
        }
    }

    private func handleCookButtonTap() {
        // Check if different recipe is already cooking
        if dependencies.cookModeCoordinator.isActive,
           let currentRecipe = dependencies.cookModeCoordinator.currentRecipe,
           currentRecipe.id != sharedRecipe.recipe.id {
            // Show conflict alert
            dependencies.cookModeCoordinator.pendingRecipe = sharedRecipe.recipe
            showSessionConflictAlert = true
        } else {
            // Start cooking
            Task {
                await dependencies.cookModeCoordinator.startCooking(sharedRecipe.recipe)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SharedRecipeDetailView(
            sharedRecipe: SharedRecipe(
                recipe: Recipe(
                    title: "Chocolate Chip Cookies",
                    ingredients: [
                        Ingredient(name: "Flour", quantity: Quantity(value: 2, unit: .cup)),
                        Ingredient(name: "Sugar", quantity: Quantity(value: 1, unit: .cup))
                    ],
                    steps: [
                        CookStep(index: 0, text: "Mix ingredients"),
                        CookStep(index: 1, text: "Bake at 350°F")
                    ],
                    tags: [Tag(name: "Dessert"), Tag(name: "Baking")]
                ),
                sharedBy: User(username: "chef_julia", displayName: "Julia Child")
            ),
            dependencies: .preview(),
            onCopy: { },
            onRemove: { }
        )
    }
}
