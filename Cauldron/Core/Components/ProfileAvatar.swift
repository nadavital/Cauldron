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
    @State private var loadedPhotoCacheKey: String?
    @ObservedObject private var currentUserSession = CurrentUserSession.shared

    init(user: User, size: CGFloat, dependencies: DependencyContainer? = nil) {
        self.user = user
        self.size = size
        self.dependencies = dependencies

        // CRITICAL: Initialize with cached image if available
        // This prevents showing emoji/color placeholder when navigating back
        if case .photo(let photo) = user.avatarRepresentation {
            let cacheKey = ImageCache.profileImageKey(for: photo)
            _profileImage = State(initialValue: ImageCache.shared.get(cacheKey))
            _loadedPhotoCacheKey = State(initialValue: cacheKey)
        } else {
            _profileImage = State(initialValue: nil)
            _loadedPhotoCacheKey = State(initialValue: nil)
        }
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

    private var fontSize: CGFloat {
        size * 0.5
    }

    var body: some View {
        avatarContent
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(displayUser.displayName), profile picture")
            .task(id: displayUser.avatarRepresentation) {
                await loadProfileImageIfNeeded()
            }
    }

    @ViewBuilder
    private var avatarContent: some View {
        switch displayUser.avatarRepresentation {
        case .photo(let photo):
            if let profileImage,
               loadedPhotoCacheKey == ImageCache.profileImageKey(for: photo) {
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
                Circle()
                    .fill(Color.cauldronSecondaryBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: fontSize))
                            .foregroundStyle(.tertiary)
                    )
            }
        case .emoji(let value, _):
            fallbackCircle(text: value, isEmoji: true)
        case .initials(let value, _):
            fallbackCircle(text: value, isEmoji: false)
        }
    }

    private func fallbackCircle(text: String, isEmoji: Bool) -> some View {
        Circle()
            .fill(backgroundColor.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                Text(text)
                    .font(.system(size: fontSize))
                    .fontWeight(isEmoji ? .regular : .bold)
                    .foregroundStyle(backgroundColor)
            )
    }

    private func loadProfileImageIfNeeded() async {
        let requestedUser = displayUser
        guard case .photo(let requestedPhoto) = requestedUser.avatarRepresentation else {
            profileImage = nil
            loadedPhotoCacheKey = nil
            return
        }

        let requestedCacheKey = ImageCache.profileImageKey(for: requestedPhoto)
        if loadedPhotoCacheKey != requestedCacheKey {
            profileImage = ImageCache.shared.get(requestedCacheKey)
            loadedPhotoCacheKey = requestedCacheKey
        }
        let loader = dependencies?.entityImageLoader ?? EntityImageLoader.shared
        let result = await loader.loadProfileImage(for: requestedUser, dependencies: dependencies)

        guard !Task.isCancelled,
              case .photo(let currentPhoto) = displayUser.avatarRepresentation,
              ImageCache.profileImageKey(for: currentPhoto) == requestedCacheKey else {
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
            loadedPhotoCacheKey = requestedCacheKey
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
