//
//  OnboardingView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// Onboarding view for first-time users to set up their profile
struct OnboardingView: View {
    let dependencies: DependencyContainer
    let onComplete: () -> Void

    @State private var username = ""
    @State private var displayName = ""
    @State private var profileEmoji: String?
    @State private var profileColor: String? = Color.profileOrange.toHex()
    @State private var profileImage: UIImage?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showingAvatarCustomization = false
    @State private var showingImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary

    // Track if user has selected a photo (to show different preview)
    private var hasPhoto: Bool { profileImage != nil }
    private var hasEmoji: Bool { profileEmoji != nil }

    var isValid: Bool {
        username.count >= 3 && username.count <= 20 &&
        displayName.count >= 1 &&
        username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer()

                    // Welcome illustration
                    VStack(spacing: 16) {
                        // App logo instead of profile preview
                        Image("CauldronIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)

                        Text("Welcome to Cauldron")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Let's set up your profile")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }

                    // Profile form
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            TextField("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding()
                                .background(Color.cauldronSecondaryBackground)
                                .cornerRadius(12)

                            Text("3-20 characters, letters, numbers, and underscores only")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

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

                        // Avatar selection - capsule-style buttons matching RecipeDetailView
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Profile Avatar")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            // Horizontal button row for all avatar options
                            HStack(spacing: 10) {
                                // Emoji Avatar Button
                                Button {
                                    showingAvatarCustomization = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "face.smiling")
                                        Text(hasEmoji ? "Edit Emoji" : "Emoji")
                                        if hasEmoji && !hasPhoto {
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
                                    .background(hasEmoji && !hasPhoto ? Color.cauldronOrange.opacity(0.15) : Color.cauldronSecondaryBackground)
                                    .foregroundColor(hasEmoji && !hasPhoto ? .cauldronOrange : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                // Photo Library Button
                                Button {
                                    imagePickerSourceType = .photoLibrary
                                    showingImagePicker = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo.on.rectangle")
                                        Text("Photos")
                                        if hasPhoto {
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
                                    .background(hasPhoto ? Color.cauldronOrange.opacity(0.15) : Color.cauldronSecondaryBackground)
                                    .foregroundColor(hasPhoto ? .cauldronOrange : .primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                // Camera Button
                                Button {
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
                            if let emoji = profileEmoji, !hasPhoto {
                                HStack(spacing: 12) {
                                    Text(emoji)
                                        .font(.system(size: 32))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Emoji avatar selected")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("Tap Emoji to change")
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

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()

                    // Continue button with glass effect like Cook button
                    Button {
                        Task {
                            await createUser()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.body)
                                Text("Get Started")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.tint(isValid ? .orange : .gray).interactive(), in: Capsule())
                    }
                    .disabled(!isValid || isCreating)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAvatarCustomization) {
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
        }
    }
    
    @MainActor
    private func createUser() async {
        isCreating = true
        errorMessage = nil

        do {
            // Photo takes precedence over emoji - if user selected a photo, use it
            // Otherwise, use the emoji they selected
            try await CurrentUserSession.shared.createUser(
                username: username,
                displayName: displayName,
                profileEmoji: profileImage == nil ? profileEmoji : nil,
                profileColor: profileColor,
                profileImage: profileImage,
                dependencies: dependencies
            )
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}

#Preview {
    OnboardingView(dependencies: .preview()) {
        // Onboarding completed
    }
}
