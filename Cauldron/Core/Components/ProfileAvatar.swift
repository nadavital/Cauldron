//
//  ProfileAvatar.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/28/25.
//

import SwiftUI

/// Reusable profile avatar component that displays profile image, emoji + color, or fallback initials
struct ProfileAvatar: View {
    let user: User
    let size: CGFloat
    let dependencies: DependencyContainer?
    @State private var profileImage: UIImage?
    @ObservedObject private var currentUserSession = CurrentUserSession.shared

    init(user: User, size: CGFloat, dependencies: DependencyContainer? = nil) {
        self.user = user
        self.size = size
        self.dependencies = dependencies

        // CRITICAL: Initialize with cached image if available
        // This prevents showing emoji/color placeholder when navigating back
        let cacheKey = ImageCache.profileImageKey(userId: user.id)
        _profileImage = State(initialValue: ImageCache.shared.get(cacheKey))
    }

    /// Use the live session user when rendering the signed-in user's avatar so profile edits
    /// propagate immediately without waiting for parent views to reload their `User` snapshots.
    private var displayUser: User {
        if let currentUser = currentUserSession.currentUser, currentUser.id == user.id {
            return currentUser
        }
        return user
    }

    private var backgroundColor: Color {
        if let colorHex = displayUser.profileColor, let color = Color.fromHex(colorHex) {
            return color
        }
        return .profileOrange // Default fallback
    }

    private var displayContent: String {
        if let emoji = displayUser.profileEmoji, !emoji.isEmpty {
            return emoji
        }
        // Fallback to initials
        return String(displayUser.displayName.prefix(2).uppercased())
    }

    private var fontSize: CGFloat {
        size * 0.5
    }

    var body: some View {
        Group {
            if let profileImage = profileImage {
                // Priority 1: Show profile image if available
                Circle()
                    .fill(Color.cauldronSecondaryBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(uiImage: profileImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    )
            } else {
                // Show emoji or initials (no loading spinner)
                // Images load silently in background and update when ready
                Circle()
                    .fill(backgroundColor.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(displayContent)
                            .font(.system(size: fontSize))
                            .fontWeight(displayUser.profileEmoji != nil ? .regular : .bold)
                            .foregroundColor(backgroundColor)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayUser.displayName), profile picture")
        .task(id: ProfileAvatarState(user: displayUser)) {
            if displayUser.profileImageURL == nil {
                profileImage = nil
            }
            await loadProfileImage()
        }
    }

    private func loadProfileImage() async {
        let requestedUser = displayUser
        let loader = dependencies?.entityImageLoader ?? EntityImageLoader.shared
        let result = await loader.loadProfileImage(for: requestedUser, dependencies: dependencies)

        guard !Task.isCancelled,
              displayUser.id == requestedUser.id,
              displayUser.profileEmoji == requestedUser.profileEmoji,
              displayUser.profileColor == requestedUser.profileColor,
              displayUser.profileImageURL == requestedUser.profileImageURL,
              displayUser.cloudProfileImageRecordName == requestedUser.cloudProfileImageRecordName,
              displayUser.profileImageModifiedAt == requestedUser.profileImageModifiedAt else {
            return
        }

        if let image = result.image {
            if let currentImage = profileImage {
                // Loading is keyed by the user's image metadata; reference identity
                // is sufficient to suppress cache hits without comparing pixels.
                if image !== currentImage {
                    profileImage = image
                }
            } else {
                profileImage = image
            }
        }

        // Session metadata is owned by CurrentUserSession's verified download
        // merge. A reusable avatar view must never mutate account state.
    }
}

#Preview {
    VStack(spacing: 20) {
        // With emoji and color
        ProfileAvatar(
            user: User(
                username: "chef_julia",
                displayName: "Julia Child",
                profileEmoji: "🍕",
                profileColor: Color.profilePink.toHex()
            ),
            size: 100
        )

        // Fallback to initials
        ProfileAvatar(
            user: User(
                username: "gordon_ramsay",
                displayName: "Gordon Ramsay"
            ),
            size: 100
        )

        // Different sizes
        HStack(spacing: 16) {
            ProfileAvatar(
                user: User(
                    username: "test",
                    displayName: "Test User",
                    profileEmoji: "🍜",
                    profileColor: Color.profileBlue.toHex()
                ),
                size: 20
            )

            ProfileAvatar(
                user: User(
                    username: "test",
                    displayName: "Test User",
                    profileEmoji: "🍜",
                    profileColor: Color.profileBlue.toHex()
                ),
                size: 50
            )

            ProfileAvatar(
                user: User(
                    username: "test",
                    displayName: "Test User",
                    profileEmoji: "🍜",
                    profileColor: Color.profileBlue.toHex()
                ),
                size: 60
            )
        }
    }
    .padding()
}
