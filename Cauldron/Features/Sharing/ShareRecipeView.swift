//
//  ShareRecipeView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import os

/// View explaining the new visibility-based sharing model
struct ShareRecipeView: View {
    let recipe: Recipe
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss

    init(recipe: Recipe, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.dependencies = dependencies
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Current visibility status
                    currentVisibilitySection

                    // How sharing works explanation
                    howSharingWorksSection
                }
                .padding()
            }
            .navigationTitle("Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var currentVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current Visibility", systemImage: recipe.visibility.icon)
                .font(.title3)
                .fontWeight(.semibold)

            HStack {
                Image(systemName: recipe.visibility.icon)
                    .font(.title)
                    .foregroundColor(.cauldronOrange)
                    .frame(width: 50, height: 50)
                    .background(Color.cauldronOrange.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.visibility.displayName)
                        .font(.headline)
                    Text(recipe.visibility.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)

            Text("Edit visibility in the recipe editor")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var howSharingWorksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How Sharing Works")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                sharingOptionRow(
                    icon: "lock.fill",
                    title: "Private",
                    description: "Only you can see this recipe. It syncs to your iCloud for backup."
                )

                Divider()

                sharingOptionRow(
                    icon: "person.2.fill",
                    title: "Friends Only",
                    description: "Your friends can discover this recipe in their Shared tab. They can save a reference (always synced with your updates) or make their own copy."
                )

                Divider()

                sharingOptionRow(
                    icon: "globe",
                    title: "Public",
                    description: "Anyone can discover this recipe. Perfect for sharing your favorites with the world!"
                )
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)

            // Info box
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("No Links Needed!")
                        .font(.headline)
                }

                Text("With the new sharing system, you don't need to send links. Just set your recipe's visibility, and your friends will automatically see it in their Shared Recipes tab.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private func sharingOptionRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cauldronOrange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    ShareRecipeView(
        recipe: Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [],
            visibility: .friendsOnly
        ),
        dependencies: .preview()
    )
}
