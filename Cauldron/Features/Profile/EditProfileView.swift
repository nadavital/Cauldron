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
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
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
            ScrollView {
                VStack(spacing: 32) {
                    // Profile Preview (matching onboarding)
                    VStack(spacing: 16) {
                        // Avatar Display
                        if selectedAvatarType == .photo {
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else if let profileImageURL = currentUser.profileImageURL,
                                      let imageData = try? Data(contentsOf: profileImageURL),
                                      let image = UIImage(data: imageData) {
                                Image(uiImage: image)
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
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("@\(username.isEmpty ? "username" : username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Profile form (matching onboarding style)
                    VStack(spacing: 24) {
                        // Username field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            TextField("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textCase(.lowercase)
                                .padding()
                                .background(Color.cauldronSecondaryBackground)
                                .cornerRadius(12)

                            Text("3-20 characters, letters, numbers, and underscores only")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Display Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            TextField("Your Name", text: $displayName)
                                .textInputAutocapitalization(.words)
                                .padding()
                                .background(Color.cauldronSecondaryBackground)
                                .cornerRadius(12)

                            Text("This is how others will see you")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Avatar selection - capsule-style buttons matching onboarding
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Profile Avatar")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            // Horizontal button row for all avatar options
                            HStack(spacing: 10) {
                                // Emoji Avatar Button
                                Button {
                                    selectedAvatarType = .emoji
                                    profileImage = nil
                                    showingAvatarPicker = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "face.smiling")
                                        Text(profileEmoji != nil ? "Edit Emoji" : "Emoji")
                                        if selectedAvatarType == .emoji {
                                            Image(systemName: "checkmark")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                        }
                                    }
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(selectedAvatarType == .emoji ? Color.cauldronOrange.opacity(0.15) : Color.cauldronSecondaryBackground)
                                    .foregroundColor(selectedAvatarType == .emoji ? .cauldronOrange : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                // Photo Library Button
                                Button {
                                    selectedAvatarType = .photo
                                    imagePickerSourceType = .photoLibrary
                                    showingImagePicker = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo.on.rectangle")
                                        Text("Photos")
                                        if selectedAvatarType == .photo && (profileImage != nil || currentUser.profileImageURL != nil) {
                                            Image(systemName: "checkmark")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                        }
                                    }
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(selectedAvatarType == .photo ? Color.cauldronOrange.opacity(0.15) : Color.cauldronSecondaryBackground)
                                    .foregroundColor(selectedAvatarType == .photo ? .cauldronOrange : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                // Camera Button
                                Button {
                                    selectedAvatarType = .photo
                                    imagePickerSourceType = .camera
                                    showingImagePicker = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "camera")
                                        Text("Camera")
                                    }
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.cauldronSecondaryBackground)
                                    .foregroundColor(.primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            // Show selected photo preview with remove option
                            if let image = profileImage {
                                HStack(spacing: 12) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Photo selected")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Tap × to remove")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        profileImage = nil
                                        selectedAvatarType = .emoji
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(Color.cauldronOrange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            // Show selected emoji preview
                            if let emoji = profileEmoji, selectedAvatarType == .emoji {
                                HStack(spacing: 12) {
                                    Text(emoji)
                                        .font(.system(size: 32))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Emoji avatar selected")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Tap Edit Emoji to change")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(12)
                                .background(Color.cauldronOrange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        // Delete Account Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Account")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            NavigationLink {
                                DeleteAccountView(dependencies: dependencies)
                            } label: {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Delete Account")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.cauldronSecondaryBackground)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
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
            // Use fullScreenCover for camera to prevent white bar at bottom of viewfinder
            .fullScreenCover(isPresented: $showingImagePicker) {
                ImagePicker(image: $profileImage, sourceType: imagePickerSourceType)
                    .ignoresSafeArea()
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
            // Normalize inputs: trim whitespace and lowercase username
            let normalizedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
            let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespaces)

            // Handle avatar update
            if selectedAvatarType == .photo, let image = profileImage {
                // OPTIMISTIC UI: Save image locally and update UI immediately
                let profileImageURL = try await dependencies.profileImageManager.saveImage(image, userId: currentUser.id)

                // Create optimistic user update (without cloud sync yet)
                let optimisticUser = currentUser.updatedProfile(
                    profileEmoji: nil,
                    profileColor: nil,
                    profileImageURL: profileImageURL,
                    cloudProfileImageRecordName: currentUser.cloudProfileImageRecordName, // Keep existing for now
                    profileImageModifiedAt: currentUser.profileImageModifiedAt
                )

                // Update UI immediately
                CurrentUserSession.shared.currentUser = optimisticUser
                Self.saveUserToDefaults(optimisticUser)
                AppLogger.general.info("✅ Updated profile locally (optimistic)")

                // Dismiss sheet immediately for snappy UX
                dismiss()

                // Background sync to CloudKit
                Task.detached { [dependencies, currentUser] in
                    do {
                        let localModified = await dependencies.profileImageManager.getImageModificationDate(userId: currentUser.id)
                        let needsUpload = currentUser.needsProfileImageUpload(localImageModified: localModified)

                        var cloudProfileImageRecordName = currentUser.cloudProfileImageRecordName
                        var profileImageModifiedAt = currentUser.profileImageModifiedAt

                        if needsUpload {
                            cloudProfileImageRecordName = try await dependencies.profileImageManager.uploadImageToCloud(userId: currentUser.id)
                            profileImageModifiedAt = Date()
                            AppLogger.general.info("☁️ Uploaded profile image to CloudKit in background")

                            // Update with cloud record name after successful upload
                            let finalUser = optimisticUser.updatedProfile(
                                profileEmoji: nil,
                                profileColor: nil,
                                profileImageURL: profileImageURL,
                                cloudProfileImageRecordName: cloudProfileImageRecordName,
                                profileImageModifiedAt: profileImageModifiedAt
                            )

                            try await dependencies.cloudKitService.saveUser(finalUser)

                            // Update session with cloud-synced version
                            await MainActor.run {
                                CurrentUserSession.shared.currentUser = finalUser
                                Self.saveUserToDefaults(finalUser)
                            }
                        } else {
                            // Still save user record to CloudKit even if image didn't need upload
                            try await dependencies.cloudKitService.saveUser(optimisticUser)
                            AppLogger.general.info("☁️ Synced user profile to CloudKit (image already up-to-date)")
                        }
                    } catch {
                        AppLogger.general.error("❌ Background CloudKit sync failed: \(error.localizedDescription)")
                        // Note: UI already updated optimistically, so user doesn't see this error
                        // Could add a notification or retry mechanism here
                    }
                }

            } else if selectedAvatarType == .emoji {
                // OPTIMISTIC UI: Update locally first
                let updatedUser = User(
                    id: currentUser.id,
                    username: normalizedUsername,
                    displayName: normalizedDisplayName,
                    email: currentUser.email,
                    cloudRecordName: currentUser.cloudRecordName,
                    createdAt: currentUser.createdAt,
                    profileEmoji: profileEmoji,
                    profileColor: profileColor,
                    profileImageURL: nil,
                    cloudProfileImageRecordName: nil,
                    profileImageModifiedAt: nil
                )

                // Update UI immediately
                CurrentUserSession.shared.currentUser = updatedUser
                Self.saveUserToDefaults(updatedUser)
                AppLogger.general.info("✅ Updated profile locally with emoji (optimistic)")

                // Dismiss immediately
                dismiss()

                // Background sync
                Task.detached { [dependencies, currentUser] in
                    // Clear existing profile image
                    await dependencies.profileImageManager.deleteImage(userId: currentUser.id)

                    do {
                        // Delete from CloudKit if exists
                        if currentUser.cloudProfileImageRecordName != nil {
                            try await dependencies.profileImageManager.deleteImageFromCloud(userId: currentUser.id)
                        }

                        // Save updated user to CloudKit
                        try await dependencies.cloudKitService.saveUser(updatedUser)
                        AppLogger.general.info("☁️ Synced emoji profile to CloudKit in background")
                    } catch {
                        AppLogger.general.error("❌ Background CloudKit sync failed: \(error.localizedDescription)")
                    }
                }

            } else if normalizedUsername != currentUser.username || normalizedDisplayName != currentUser.displayName {
                // OPTIMISTIC UI: Update basic info immediately
                let updatedUser = User(
                    id: currentUser.id,
                    username: normalizedUsername,
                    displayName: normalizedDisplayName,
                    email: currentUser.email,
                    cloudRecordName: currentUser.cloudRecordName,
                    createdAt: currentUser.createdAt,
                    profileEmoji: currentUser.profileEmoji,
                    profileColor: currentUser.profileColor,
                    profileImageURL: currentUser.profileImageURL,
                    cloudProfileImageRecordName: currentUser.cloudProfileImageRecordName,
                    profileImageModifiedAt: currentUser.profileImageModifiedAt
                )

                CurrentUserSession.shared.currentUser = updatedUser
                Self.saveUserToDefaults(updatedUser)
                AppLogger.general.info("✅ Updated basic profile info locally (optimistic)")

                dismiss()

                // Background sync
                Task.detached { [dependencies] in
                    do {
                        try await dependencies.cloudKitService.saveUser(updatedUser)
                        AppLogger.general.info("☁️ Synced basic profile to CloudKit in background")
                    } catch {
                        AppLogger.general.error("❌ Background CloudKit sync failed: \(error.localizedDescription)")
                    }
                }
            }

        } catch {
            AppLogger.general.error("❌ Failed to save profile locally: \(error.localizedDescription)")
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
            showError = true
        }
    }

    private static func saveUserToDefaults(_ user: User) {
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
