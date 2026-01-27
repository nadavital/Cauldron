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
    @State private var isLoadingImage = false
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

    /// Returns the current user from session if this is the current user's avatar, otherwise the passed user
    /// This ensures profile changes propagate immediately throughout the app
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
        .task {
            await loadProfileImage()
        }
        .onChange(of: displayUser.profileImageURL) { oldValue, newValue in
            // If user switched from image to emoji (profileImageURL became nil), clear local image
            if newValue == nil && oldValue != nil {
                profileImage = nil
            }
            // If profileImageURL changed, reload the image
            if newValue != oldValue {
                Task {
                    await loadProfileImage()
                }
            }
        }
    }

    private func loadProfileImage() async {
        let cacheKey = ImageCache.profileImageKey(userId: user.id)

        // Strategy 0: Check in-memory cache first (fastest)
        if let cachedImage = ImageCache.shared.get(cacheKey) {
            // CRITICAL: Always set profileImage if it's nil (initial load)
            // Only compare if we already have an image loaded
            if let currentImage = profileImage {
                // Only update UI if the image actually changed
                if !areImagesEqual(cachedImage, currentImage) {
                    profileImage = cachedImage
                }
            } else {
                // First load - always set the image
                profileImage = cachedImage
            }
            return
        }

        // Strategy 1: Try to load from local file
        if let imageURL = user.profileImageURL,
           let imageData = try? Data(contentsOf: imageURL),
           let image = UIImage(data: imageData) {
            // CRITICAL: Always set profileImage if it's nil (initial load)
            if let currentImage = profileImage {
                // Only update UI if the image actually changed
                if !areImagesEqual(image, currentImage) {
                    profileImage = image
                    ImageCache.shared.set(cacheKey, image: image)
                }
            } else {
                // First load - always set the image
                profileImage = image
                ImageCache.shared.set(cacheKey, image: image)
            }
            return
        }

        // Strategy 2: If local file is missing but we have a cloud record, try downloading
        // This handles the case where app was reinstalled or local storage was cleared
        if let dependencies = dependencies,
           user.cloudProfileImageRecordName != nil,
           user.profileImageURL == nil,
           !isLoadingImage {
            // Mark as loading to prevent duplicate downloads from this view instance
            isLoadingImage = true
            defer { isLoadingImage = false }

            do {
                if let downloadedURL = try await dependencies.profileImageManager.downloadImageFromCloud(userId: user.id),
                   let imageData = try? Data(contentsOf: downloadedURL),
                   let image = UIImage(data: imageData) {
                    // CRITICAL: Always set profileImage if it's nil (initial load)
                    if let currentImage = profileImage {
                        // Only update UI if the image actually changed
                        if !areImagesEqual(image, currentImage) {
                            profileImage = image
                            ImageCache.shared.set(cacheKey, image: image)
                        }
                    } else {
                        // First load - always set the image
                        profileImage = image
                        ImageCache.shared.set(cacheKey, image: image)
                    }

                    // Update CurrentUserSession with the downloaded image URL
                    if let currentUser = CurrentUserSession.shared.currentUser,
                       currentUser.id == user.id {
                        let updatedUser = currentUser.updatedProfile(
                            profileEmoji: currentUser.profileEmoji,
                            profileColor: currentUser.profileColor,
                            profileImageURL: downloadedURL,
                            cloudProfileImageRecordName: currentUser.cloudProfileImageRecordName,
                            profileImageModifiedAt: currentUser.profileImageModifiedAt
                        )
                        await MainActor.run {
                            CurrentUserSession.shared.currentUser = updatedUser
                        }
                    }

                    // Downloaded profile image from CloudKit (don't log routine operations)
                }
            } catch {
                AppLogger.general.warning("Failed to download profile image from CloudKit: \(error.localizedDescription)")
                // Fall back to emoji/initials display
            }
        }
    }

    /// Compare two images to see if they're visually identical
    /// This prevents UI updates when CloudKit sync returns the same image
    private func areImagesEqual(_ image1: UIImage, _ image2: UIImage) -> Bool {
        // Fast path: if they're literally the same object, they're equal
        if image1 === image2 {
            return true
        }

        // Compare image dimensions
        if image1.size != image2.size {
            return false
        }

        // Compare scale
        if image1.scale != image2.scale {
            return false
        }

        // Compare PNG data for accurate equality check
        // Profile images are typically small (< 200KB), so this is fast enough
        guard let data1 = image1.pngData(),
              let data2 = image2.pngData() else {
            // If we can't get PNG data, fall back to assuming they're different
            return false
        }

        return data1 == data2
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
