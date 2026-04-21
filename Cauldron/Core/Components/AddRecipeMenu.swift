//
//  AddRecipeMenu.swift
//  Cauldron
//
//  Reusable "Add Recipe" menu component for consistent UI across views
//

import SwiftUI

/// Reusable menu component for adding new recipes
/// Provides consistent ordering, icons, and AI availability checking
struct AddRecipeMenu: View {
    let dependencies: DependencyContainer
    @Binding var showingEditor: Bool
    @Binding var showingAIGenerator: Bool
    @Binding var showingImporter: Bool
    @Binding var showingCollectionForm: Bool

    @State private var isAIAvailable = false

    var body: some View {
        Menu {
            // AI Generation option (only show if available)
            if isAIAvailable {
                Button {
                    showingAIGenerator = true
                } label: {
                    Label("Generate with AI", systemImage: "apple.intelligence")
                }
            }

            Button {
                showingEditor = true
            } label: {
                Label("Create Manually", systemImage: "square.and.pencil")
            }

            Button {
                showingImporter = true
            } label: {
                Label("Import", systemImage: "arrow.down.doc")
            }

            Divider()

            Button {
                showingCollectionForm = true
            } label: {
                Label("Create Collection", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .imageScale(.medium)
        }
        .task {
            // Check AI availability on appear
            isAIAvailable = await dependencies.foundationModelsService.isAvailable
        }
    }
}
