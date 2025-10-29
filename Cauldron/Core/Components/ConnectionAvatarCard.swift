//
//  ConnectionAvatarCard.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// Compact card showing a friend's avatar and name
struct ConnectionAvatarCard: View {
    let user: User
    let dependencies: DependencyContainer

    var body: some View {
        NavigationLink(destination: UserProfileView(user: user, dependencies: dependencies)) {
            VStack(spacing: 6) {
                ProfileAvatar(user: user, size: 60)

                Text(user.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 70)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ConnectionAvatarCard(
        user: User(username: "chef_julia", displayName: "Julia Child"),
        dependencies: .preview()
    )
}
