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
    @State private var profileColor: String?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showingEmojiPicker = false

    // Preset food emojis for quick selection
    private let foodEmojis = ["🍕", "🍔", "🍜", "🍰", "🥗", "🍱", "🌮", "🍣", "🥘", "🍛", "🧁", "🥐"]

    var isValid: Bool {
        username.count >= 3 && username.count <= 20 &&
        displayName.count >= 1 &&
        username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    var previewUser: User {
        User(
            username: username.isEmpty ? "username" : username,
            displayName: displayName.isEmpty ? "Your Name" : displayName,
            profileEmoji: profileEmoji,
            profileColor: profileColor
        )
    }
    
    var body: some View {
        NavigationStack {
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

                    // Emoji picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile Emoji (Optional)")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                            ForEach(foodEmojis, id: \.self) { emoji in
                                Button {
                                    profileEmoji = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(profileEmoji == emoji ? Color.cauldronOrange.opacity(0.2) : Color.cauldronSecondaryBackground)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile Color (Optional)")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                            ForEach(Color.allProfileColors, id: \.self) { color in
                                Button {
                                    profileColor = color.toHex()
                                } label: {
                                    Circle()
                                        .fill(color.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: profileColor == color.toHex() ? 3 : 0)
                                        )
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .foregroundColor(color)
                                                .font(.headline)
                                                .opacity(profileColor == color.toHex() ? 1 : 0)
                                        )
                                }
                            }
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
            .navigationBarHidden(true)
        }
    }
    
    private func createUser() async {
        isCreating = true
        errorMessage = nil

        do {
            try await CurrentUserSession.shared.createUser(
                username: username,
                displayName: displayName,
                profileEmoji: profileEmoji,
                profileColor: profileColor,
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
