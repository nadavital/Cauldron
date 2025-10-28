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
    @State private var isSavingReference = false
    @State private var showRemoveConfirmation = false
    @State private var showReferenceToast = false
    @State private var showCopyToast = false
    @State private var hasExistingReference = false
    @State private var hasOwnedCopy = false
    @State private var isCheckingDuplicates = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Image - Stretches to top
                if let imageURL = sharedRecipe.recipe.imageURL {
                    HeroRecipeImageView(imageURL: imageURL)
                        .ignoresSafeArea(edges: .top)
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
            }
        }
        .navigationTitle(sharedRecipe.recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Add to My Recipes (saves reference - always synced)
                    Button {
                        Task {
                            await saveRecipeReference()
                        }
                    } label: {
                        if hasExistingReference {
                            Label("Already in Your Recipes", systemImage: "checkmark.circle.fill")
                        } else {
                            Label("Add to My Recipes", systemImage: "bookmark.fill")
                        }
                    }
                    .disabled(isSavingReference || isPerformingAction || hasExistingReference || isCheckingDuplicates)

                    // Save a Copy (independent recipe)
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
                        if hasOwnedCopy {
                            Label("Copy Already Saved", systemImage: "checkmark.circle.fill")
                        } else {
                            Label("Save a Copy", systemImage: "doc.on.doc")
                        }
                    }
                    .disabled(isPerformingAction || isSavingReference || hasOwnedCopy || isCheckingDuplicates)
                } label: {
                    if isSavingReference || isPerformingAction {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
                .disabled(isCheckingDuplicates)
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
        .toast(isShowing: $showReferenceToast, icon: "bookmark.fill", message: "Added to your recipes!")
        .toast(isShowing: $showCopyToast, icon: "doc.on.doc.fill", message: "Recipe copied!")
        .task {
            await checkForDuplicates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeReferenceRemoved"))) { _ in
            // Re-check duplicates when a reference is removed
            Task {
                await checkForDuplicates()
            }
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
            
            Text("This is a read-only view. Add to your recipes to save a reference (always synced) or copy to edit independently.")
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
    

    private func saveRecipeReference() async {
        isSavingReference = true
        defer { isSavingReference = false }

        do {
            // Get current user
            let currentUser = await MainActor.run { CurrentUserSession.shared.currentUser }
            guard let currentUser = currentUser else {
                AppLogger.general.error("Cannot save recipe reference - no current user")
                return
            }

            // Create recipe reference
            let reference = RecipeReference.reference(userId: currentUser.id, recipe: sharedRecipe.recipe)

            // Save to CloudKit PUBLIC database
            try await dependencies.cloudKitService.saveRecipeReference(reference)

            AppLogger.general.info("Saved recipe reference: \(sharedRecipe.recipe.title)")

            // Update tracking state immediately
            await MainActor.run {
                hasExistingReference = true
            }

            // Notify other views that a recipe was added
            await MainActor.run {
                NotificationCenter.default.post(name: NSNotification.Name("RecipeAdded"), object: nil)
            }

            // Refresh the SharingTabViewModel's reference tracking
            await SharingTabViewModel.shared.loadSharedRecipes()

            // Show toast notification
            await MainActor.run {
                withAnimation {
                    showReferenceToast = true
                }
            }

            // Dismiss sheet after toast appears
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
            await MainActor.run {
                dismiss()
            }
        } catch {
            AppLogger.general.error("Failed to save recipe reference: \(error.localizedDescription)")
            // TODO: Show error alert
        }
    }

    private func checkForDuplicates() async {
        guard let userId = CurrentUserSession.shared.userId else {
            isCheckingDuplicates = false
            return
        }

        do {
            // Check for existing reference
            hasExistingReference = try await dependencies.recipeReferenceManager.hasReference(
                for: sharedRecipe.recipe.id,
                userId: userId
            )

            // Check for owned copy
            hasOwnedCopy = try await dependencies.recipeRepository.hasSimilarRecipe(
                title: sharedRecipe.recipe.title,
                ownerId: userId,
                ingredientCount: sharedRecipe.recipe.ingredients.count
            )

            isCheckingDuplicates = false
            AppLogger.general.info("Duplicate check complete - hasReference: \(hasExistingReference), hasOwnedCopy: \(hasOwnedCopy)")
        } catch {
            AppLogger.general.error("Failed to check for duplicates: \(error.localizedDescription)")
            isCheckingDuplicates = false
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
