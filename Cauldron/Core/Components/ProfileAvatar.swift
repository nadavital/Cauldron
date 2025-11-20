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

    init(user: User, size: CGFloat, dependencies: DependencyContainer? = nil) {
        self.user = user
        self.size = size
        self.dependencies = dependencies
    }

    private var backgroundColor: Color {
        if let colorHex = user.profileColor, let color = Color.fromHex(colorHex) {
            return color
        }
        return .profileOrange // Default fallback
    }

    private var displayContent: String {
        if let emoji = user.profileEmoji, !emoji.isEmpty {
            return emoji
        }
        // Fallback to initials
        return String(user.displayName.prefix(2).uppercased())
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
            } else if isLoadingImage {
                // Show loading state
                Circle()
                    .fill(backgroundColor.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        ProgressView()
                            .tint(backgroundColor)
                    )
            } else {
                // Priority 2/3: Show emoji or initials
                Circle()
                    .fill(backgroundColor.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(displayContent)
                            .font(.system(size: fontSize))
                            .fontWeight(user.profileEmoji != nil ? .regular : .bold)
                            .foregroundColor(backgroundColor)
                    )
            }
        }
        .task {
            await loadProfileImage()
        }
    }

    private func loadProfileImage() async {
        isLoadingImage = true
        defer { isLoadingImage = false }

        // Strategy 1: Try to load from local URL if available
        if let imageURL = user.profileImageURL,
           let imageData = try? Data(contentsOf: imageURL),
           let image = UIImage(data: imageData) {
            profileImage = image
            return
        }

        // Strategy 2: If local file is missing but we have a cloud record, try downloading
        // This handles the case where app was reinstalled or local storage was cleared
        if let dependencies = dependencies,
           user.cloudProfileImageRecordName != nil,
           user.profileImageURL == nil {
            AppLogger.general.info("Local profile image missing, attempting download from CloudKit for user \(user.username)")

            do {
                if let downloadedURL = try await dependencies.profileImageManager.downloadImageFromCloud(userId: user.id),
                   let imageData = try? Data(contentsOf: downloadedURL),
                   let image = UIImage(data: imageData) {
                    profileImage = image

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

                    AppLogger.general.info("✅ Downloaded profile image from CloudKit for user \(user.username)")
                }
            } catch {
                AppLogger.general.warning("Failed to download profile image from CloudKit: \(error.localizedDescription)")
                // Fall back to emoji/initials display
            }
        }
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
