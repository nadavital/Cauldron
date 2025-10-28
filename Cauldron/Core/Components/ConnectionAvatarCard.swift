//
//  ConnectionAvatarCard.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// Compact card showing a connection's avatar and name
struct ConnectionAvatarCard: View {
    let user: User
    let dependencies: DependencyContainer

    var body: some View {
        NavigationLink(destination: UserProfileView(user: user, dependencies: dependencies)) {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color.cauldronOrange.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(user.displayName.prefix(2).uppercased())
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.cauldronOrange)
                    )

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
