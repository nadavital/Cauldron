//
//  ProfileAvatar.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/28/25.
//

import SwiftUI

/// Reusable profile avatar component that displays either emoji + color or fallback initials
struct ProfileAvatar: View {
    let user: User
    let size: CGFloat

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
