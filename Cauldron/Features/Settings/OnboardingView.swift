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

    // Avatar type selection
    enum AvatarType: String, CaseIterable {
        case emoji = "Emoji Avatar"
        case photo = "Upload Photo"
    }
    @State private var selectedAvatarType: AvatarType = .emoji

    var isValid: Bool {
        username.count >= 3 && username.count <= 20 &&
        displayName.count >= 1 &&
        username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    var previewUser: User {
        User(
            username: username.isEmpty ? "username" : username,
            displayName: displayName.isEmpty ? "Your Name" : displayName,
            profileEmoji: selectedAvatarType == .emoji ? profileEmoji : nil,
            profileColor: profileColor
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer()

                    // Welcome illustration
                    VStack(spacing: 16) {
                        // Profile preview with avatar
                        ProfileAvatar(user: previewUser, size: 100)

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

                        // Avatar type selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Profile Avatar")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            // Avatar type picker
                            Picker("Avatar Type", selection: $selectedAvatarType) {
                                ForEach(AvatarType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedAvatarType) { oldValue, newValue in
                                // Clear the other option when switching
                                if newValue == .photo {
                                    profileEmoji = nil
                                } else {
                                    profileImage = nil
                                }
                            }

                            // Avatar customization button
                            if selectedAvatarType == .emoji {
                                Button {
                                    showingAvatarCustomization = true
                                } label: {
                                    HStack {
                                        if let emoji = profileEmoji {
                                            Text(emoji)
                                                .font(.title2)
                                        } else {
                                            Image(systemName: "face.smiling")
                                        }
                                        Text(profileEmoji != nil ? "Change Avatar" : "Customize Avatar")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.cauldronSecondaryBackground)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Photo upload button
                                Button {
                                    showingImagePicker = true
                                } label: {
                                    HStack {
                                        if let image = profileImage {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 40, height: 40)
                                                .clipShape(Circle())
                                        } else {
                                            Image(systemName: "photo")
                                        }
                                        Text(profileImage != nil ? "Change Photo" : "Upload Photo")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.cauldronSecondaryBackground)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
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

                    // Continue button
                    Button {
                        Task {
                            await createUser()
                        }
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Get Started")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValid ? Color.cauldronOrange : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!isValid || isCreating)
                    .padding(.horizontal)
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
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $profileImage)
            }
        }
    }
    
    @MainActor
    private func createUser() async {
        isCreating = true
        errorMessage = nil

        do {
            try await CurrentUserSession.shared.createUser(
                username: username,
                displayName: displayName,
                profileEmoji: selectedAvatarType == .emoji ? profileEmoji : nil,
                profileColor: profileColor,
                profileImage: selectedAvatarType == .photo ? profileImage : nil,
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
