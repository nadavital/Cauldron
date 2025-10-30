//
//  SettingsView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// View for editing user profile
struct EditProfileView: View {
    let dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userSession = CurrentUserSession.shared
    
    @State private var username = ""
    @State private var displayName = ""
    @State private var profileEmoji: String?
    @State private var profileColor: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingEmojiPicker = false

    // Preset food emojis for quick selection and random selection
    private let foodEmojis = ["🍕", "🍔", "🍜", "🍰", "🥗", "🍱", "🌮", "🍣", "🥘", "🍛", "🧁", "🥐",
                             "🍪", "🍩", "🥧", "🍦", "🍓", "🍌", "🍉", "🍇", "🍊", "🥑", "🥕", "🌽"]

    var hasChanges: Bool {
        guard let user = userSession.currentUser else { return false }
        return username != user.username ||
               displayName != user.displayName ||
               profileEmoji != user.profileEmoji ||
               profileColor != user.profileColor
    }

    var previewUser: User {
        User(
            username: username.isEmpty ? "username" : username,
            displayName: displayName.isEmpty ? "Display Name" : displayName,
            profileEmoji: profileEmoji,
            profileColor: profileColor
        )
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Profile preview
                Section {
                    HStack(spacing: 16) {
                        ProfileAvatar(user: previewUser, size: 60)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName.isEmpty ? "Display Name" : displayName)
                                .font(.headline)
                                .foregroundColor(displayName.isEmpty ? .secondary : .primary)
                            Text(username.isEmpty ? "@username" : "@\(username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Username")
                }

                Section {
                    TextField("Display Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Display Name")
                }

                // Emoji picker
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // Quick pick food emojis
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                            ForEach(foodEmojis, id: \.self) { emoji in
                                Button {
                                    profileEmoji = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(profileEmoji == emoji ? Color.cauldronOrange.opacity(0.2) : Color.clear)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Custom emoji picker and action buttons
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Button {
                                    showingEmojiPicker = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "face.smiling")
                                            .font(.body)
                                        Text("Choose")
                                            .font(.subheadline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    profileEmoji = foodEmojis.randomElement()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "shuffle")
                                            .font(.body)
                                        Text("Random")
                                            .font(.subheadline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                                .tint(.cauldronOrange)
                            }

                            if profileEmoji != nil {
                                Button {
                                    profileEmoji = nil
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle")
                                            .font(.body)
                                        Text("Clear Emoji")
                                            .font(.subheadline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                    }
                } header: {
                    Text("Profile Emoji")
                }

                // Color picker
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            ForEach(Color.allProfileColors, id: \.self) { color in
                                Button {
                                    profileColor = color.toHex()
                                } label: {
                                    Circle()
                                        .fill(color.opacity(0.3))
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: profileColor == color.toHex() ? 3 : 0)
                                        )
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .foregroundColor(color)
                                                .font(.headline)
                                                .fontWeight(.bold)
                                                .opacity(profileColor == color.toHex() ? 1 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            profileColor = Color.allProfileColors.randomElement()?.toHex()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "shuffle")
                                    .font(.body)
                                Text("Random Color")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cauldronOrange)
                    }
                } header: {
                    Text("Profile Color")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                }
            }
            .onAppear {
                if let user = userSession.currentUser {
                    username = user.username
                    displayName = user.displayName
                    profileEmoji = user.profileEmoji
                    // Default to orange if no color is set
                    profileColor = user.profileColor ?? Color.profileOrange.toHex()
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPickerView(selectedEmoji: $profileEmoji)
            }
        }
    }
    
    private func saveProfile() async {
        isSaving = true
        errorMessage = nil

        // Validate username
        if username.count < 3 || username.count > 20 {
            errorMessage = "Username must be between 3 and 20 characters"
            isSaving = false
            return
        }

        if !username.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
            errorMessage = "Username can only contain letters, numbers, and underscores"
            isSaving = false
            return
        }

        // Validate display name
        if displayName.count < 1 {
            errorMessage = "Display name cannot be empty"
            isSaving = false
            return
        }

        do {
            try await userSession.updateUser(
                username: username,
                displayName: displayName,
                profileEmoji: profileEmoji,
                profileColor: profileColor,
                dependencies: dependencies
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

#Preview {
    EditProfileView(dependencies: .preview())
}
