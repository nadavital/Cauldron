//
//  CollectionFormView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI
import os

struct CollectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies

    // Edit mode
    let collectionToEdit: Collection?

    // Form state
    @State private var name: String
    @State private var emoji: String?
    @State private var color: String?
    @State private var visibility: RecipeVisibility
    @State private var showingEmojiPicker = false
    @State private var isSaving = false

    init(collectionToEdit: Collection? = nil) {
        self.collectionToEdit = collectionToEdit

        // Initialize state
        _name = State(initialValue: collectionToEdit?.name ?? "")
        _emoji = State(initialValue: collectionToEdit?.emoji)
        _color = State(initialValue: collectionToEdit?.color)
        _visibility = State(initialValue: collectionToEdit?.visibility ?? .privateRecipe)
    }

    var isEditing: Bool {
        collectionToEdit != nil
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info Section
                Section {
                    TextField("Collection Name", text: $name)
                        .font(.body)

                    // Emoji picker
                    HStack {
                        Text("Icon")
                            .foregroundColor(.primary)

                        Spacer()

                        Button {
                            showingEmojiPicker = true
                        } label: {
                            if let emoji = emoji {
                                Text(emoji)
                                    .font(.title2)
                            } else {
                                Text("Add Emoji")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Color picker
                    HStack {
                        Text("Color")
                            .foregroundColor(.primary)

                        Spacer()

                        ColorPicker("", selection: Binding(
                            get: {
                                if let colorHex = color {
                                    return Color(hex: colorHex) ?? .cauldronOrange
                                }
                                return .cauldronOrange
                            },
                            set: { newColor in
                                color = newColor.toHex()
                            }
                        ))
                        .labelsHidden()
                    }
                } header: {
                    Text("Details")
                }

                // Visibility Section
                Section {
                    Picker("Visibility", selection: $visibility) {
                        Label("Private", systemImage: "lock.fill")
                            .tag(RecipeVisibility.privateRecipe)

                        Label("Friends", systemImage: "person.2.fill")
                            .tag(RecipeVisibility.friendsOnly)

                        Label("Public", systemImage: "globe")
                            .tag(RecipeVisibility.publicRecipe)
                    }
                    .pickerStyle(.menu)

                    // Visibility explanation
                    switch visibility {
                    case .privateRecipe:
                        Text("Only you can see this collection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .friendsOnly:
                        Text("Your friends can see and save this collection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .publicRecipe:
                        Text("Everyone can see and save this collection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Sharing")
                }

                // Preview Section
                if canSave {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                if let emoji = emoji {
                                    ZStack {
                                        Circle()
                                            .fill(selectedColor.opacity(0.15))
                                            .frame(width: 80, height: 80)

                                        Text(emoji)
                                            .font(.system(size: 50))
                                    }
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(selectedColor.opacity(0.15))
                                            .frame(width: 80, height: 80)

                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(selectedColor)
                                    }
                                }

                                Text(name.isEmpty ? "Collection Name" : name)
                                    .font(.headline)
                                    .foregroundColor(name.isEmpty ? .secondary : .primary)
                            }
                            .padding(.vertical, 8)
                            Spacer()
                        }
                    } header: {
                        Text("Preview")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Collection" : "New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        Task {
                            await saveCollection()
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPickerView(selectedEmoji: $emoji)
            }
        }
    }

    // MARK: - Actions

    private func saveCollection() async {
        isSaving = true
        defer { isSaving = false }

        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("No user ID - cannot save collection")
            return
        }

        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

            if let existingCollection = collectionToEdit {
                // Update existing collection
                let updated = existingCollection.updated(
                    name: trimmedName,
                    visibility: visibility,
                    emoji: emoji,
                    color: color
                )
                try await dependencies.collectionRepository.update(updated)
                AppLogger.general.info("✅ Updated collection: \(trimmedName)")
            } else {
                // Create new collection
                let newCollection = Collection(
                    name: trimmedName,
                    userId: userId,
                    visibility: visibility,
                    emoji: emoji,
                    color: color
                )
                try await dependencies.collectionRepository.create(newCollection)
                AppLogger.general.info("✅ Created collection: \(trimmedName)")
            }

            dismiss()
        } catch {
            AppLogger.general.error("❌ Failed to save collection: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private var selectedColor: Color {
        if let colorHex = color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }
}

#Preview {
    CollectionFormView()
        .dependencies(DependencyContainer.preview())
}
