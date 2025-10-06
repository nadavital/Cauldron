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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with shared info
                sharedInfoSection
                
                // Recipe image if available
                if let imageURL = sharedRecipe.recipe.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
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
                
                // Action buttons
                actionButtons
            }
            .padding()
        }
        .navigationTitle(sharedRecipe.recipe.title)
        .navigationBarTitleDisplayMode(.large)
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
            
            Text("This is a read-only view. Copy to your recipes to edit.")
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
                            Label("\(TimerSpec.minutes) minutes", systemImage: "timer")
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
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    isPerformingAction = true
                    await onCopy()
                    isPerformingAction = false
                }
            } label: {
                HStack {
                    if isPerformingAction {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "doc.on.doc")
                        Text("Copy to My Recipes")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.cauldronOrange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isPerformingAction)
            
            Button {
                showRemoveConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Remove from Shared")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
            .disabled(isPerformingAction)
        }
        .padding(.top, 8)
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
