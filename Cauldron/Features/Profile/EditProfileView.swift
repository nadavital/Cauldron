//
//  EditProfileView.swift
//  Cauldron
//
//  Comprehensive profile editing view with account deletion
//

import SwiftUI

struct ProfileEditView: View {
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var displayName: String
    @State private var profileEmoji: String?
    @State private var profileColor: String?
    @State private var profileImage: UIImage?
    @State private var selectedAvatarType: AvatarType

    @State private var showingAvatarPicker = false
    @State private var showingImagePicker = false
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showError = false

    private let currentUser: User

    init(dependencies: DependencyContainer, previewUser: User? = nil) {
        self.dependencies = dependencies

        // Use preview user for SwiftUI previews, otherwise require current user
        let user: User
        if let previewUser = previewUser {
            user = previewUser
        } else if let currentUser = CurrentUserSession.shared.currentUser {
            user = currentUser
        } else {
            fatalError("EditProfileView requires a current user")
        }
        self.currentUser = user

        // Initialize state from current user
        _username = State(initialValue: user.username)
        _displayName = State(initialValue: user.displayName)
        _profileEmoji = State(initialValue: user.profileEmoji)
        _profileColor = State(initialValue: user.profileColor)

        // Determine avatar type
        if user.profileImageURL != nil {
            _selectedAvatarType = State(initialValue: .photo)
        } else {
            _selectedAvatarType = State(initialValue: .emoji)
        }
    }

    var isValid: Bool {
        username.count >= 3 && username.count <= 20 &&
        displayName.count >= 1 &&
        username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    var hasChanges: Bool {
        username != currentUser.username ||
        displayName != currentUser.displayName ||
        profileEmoji != currentUser.profileEmoji ||
        profileColor != currentUser.profileColor ||
        profileImage != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Profile Preview
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if selectedAvatarType == .photo {
                                if let profileImage = profileImage {
                                    Image(uiImage: profileImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 100, height: 100)
                                        .overlay(
                                            Image(systemName: "person.crop.circle")
                                                .font(.system(size: 50))
                                                .foregroundColor(.secondary)
                                        )
                                }
                            } else {
                                Circle()
                                    .fill((profileColor.flatMap { Color(hex: $0) } ?? .cauldronOrange).opacity(0.15))
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Group {
                                            if let emoji = profileEmoji {
                                                Text(emoji)
                                                    .font(.system(size: 50))
                                            } else {
                                                Text(displayName.isEmpty ? "?" : String(displayName.prefix(2)).uppercased())
                                                    .font(.title)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(profileColor.flatMap { Color(hex: $0) } ?? .cauldronOrange)
                                            }
                                        }
                                    )
                            }

                            Text(displayName.isEmpty ? "Your Name" : displayName)
                                .font(.headline)

                            Text("@\(username.isEmpty ? "username" : username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Preview")
                }

                // Display Name
                Section {
                    TextField("Display Name", text: $displayName)
                } header: {
                    Text("Display Name")
                } footer: {
                    Text("Your name as it appears to others")
                }

                // Username
                Section {
                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Username")
                } footer: {
                    Text("Must be 3-20 characters, letters, numbers, and underscores only. Used for searching and @mentions.")
                }

                // Avatar Settings
                Section {
                    Picker("Avatar Type", selection: $selectedAvatarType) {
                        Text("Emoji Avatar").tag(AvatarType.emoji)
                        Text("Upload Photo").tag(AvatarType.photo)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedAvatarType) { oldValue, newValue in
                        if newValue == .photo {
                            profileEmoji = nil
                        } else {
                            profileImage = nil
                        }
                    }

                    if selectedAvatarType == .emoji {
                        HStack {
                            Text("Emoji")
                            Spacer()
                            Button {
                                showingAvatarPicker = true
                            } label: {
                                if let emoji = profileEmoji {
                                    Text(emoji)
                                        .font(.title2)
                                } else {
                                    Text("Choose Emoji")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        HStack {
                            Text("Color")
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: {
                                    if let colorHex = profileColor {
                                        return Color(hex: colorHex) ?? .cauldronOrange
                                    }
                                    return .cauldronOrange
                                },
                                set: { newColor in
                                    profileColor = newColor.toHex()
                                }
                            ))
                            .labelsHidden()
                        }
                    } else {
                        Button {
                            showingImagePicker = true
                        } label: {
                            HStack {
                                if profileImage != nil {
                                    Text("Change Photo")
                                } else if currentUser.profileImageURL != nil {
                                    Text("Replace Photo")
                                } else {
                                    Text("Upload Photo")
                                }
                                Spacer()
                                Image(systemName: "photo.on.rectangle.angled")
                                    .foregroundColor(.cauldronOrange)
                            }
                        }
                    }
                } header: {
                    Text("Avatar")
                }

                // Delete Account
                Section {
                    NavigationLink {
                        DeleteAccountView(dependencies: dependencies)
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Delete Account")
                                .foregroundColor(.primary)
                        }
                    }
                } header: {
                    Text("Delete Account")
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
                    .disabled(!isValid || !hasChanges || isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingAvatarPicker) {
                AvatarCustomizationSheet(
                    selectedEmoji: $profileEmoji,
                    selectedColor: $profileColor
                )
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $profileImage)
            }
            .task {
                // Load existing profile image if available
                if selectedAvatarType == .photo,
                   currentUser.profileImageURL != nil,
                   profileImage == nil {
                    profileImage = await dependencies.profileImageManager.loadImage(userId: currentUser.id)
                }
            }
        }
    }

    // MARK: - Actions

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        do {
            // Handle avatar update
            if selectedAvatarType == .photo, let image = profileImage {
                // Save image locally
                let profileImageURL = try await dependencies.profileImageManager.saveImage(image, userId: currentUser.id)

                // Upload to CloudKit
                do {
                    let cloudProfileImageRecordName = try await dependencies.profileImageManager.uploadImageToCloud(userId: currentUser.id)

                    // Update user with image references
                    let updatedUser = currentUser.updatedProfile(
                        profileEmoji: nil,
                        profileColor: nil,
                        profileImageURL: profileImageURL,
                        cloudProfileImageRecordName: cloudProfileImageRecordName,
                        profileImageModifiedAt: Date()
                    )

                    // Save to CloudKit
                    try await dependencies.cloudKitService.saveUser(updatedUser)

                    // Update session
                    CurrentUserSession.shared.currentUser = updatedUser
                    saveUserToDefaults(updatedUser)

                    AppLogger.general.info("✅ Updated profile with photo")
                } catch {
                    AppLogger.general.warning("⚠️ Failed to upload profile image: \(error.localizedDescription)")
                    throw error
                }
            } else if selectedAvatarType == .emoji {
                // Clear existing profile image
                await dependencies.profileImageManager.deleteImage(userId: currentUser.id)

                // Update with emoji avatar
                try await CurrentUserSession.shared.updateUser(
                    username: username,
                    displayName: displayName,
                    profileEmoji: profileEmoji,
                    profileColor: profileColor,
                    dependencies: dependencies
                )

                AppLogger.general.info("✅ Updated profile with emoji")
            } else if username != currentUser.username || displayName != currentUser.displayName {
                // Just update basic info
                try await CurrentUserSession.shared.updateUser(
                    username: username,
                    displayName: displayName,
                    profileEmoji: currentUser.profileEmoji,
                    profileColor: currentUser.profileColor,
                    dependencies: dependencies
                )

                AppLogger.general.info("✅ Updated profile info")
            }

            dismiss()
        } catch {
            AppLogger.general.error("❌ Failed to save profile: \(error.localizedDescription)")
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
            showError = true
        }
    }

    private func saveUserToDefaults(_ user: User) {
        let defaults = UserDefaults.standard
        defaults.set(user.id.uuidString, forKey: "currentUserId")
        defaults.set(user.username, forKey: "currentUsername")
        defaults.set(user.displayName, forKey: "currentDisplayName")
        defaults.set(user.profileEmoji, forKey: "currentProfileEmoji")
        defaults.set(user.profileColor, forKey: "currentProfileColor")
    }
}

#Preview {
    let previewUser = User(username: "chef_julia", displayName: "Julia Child", profileEmoji: "👨‍🍳", profileColor: Color.cauldronOrange.toHex())
    return NavigationStack {
        ProfileEditView(dependencies: .preview(), previewUser: previewUser)
    }
}
