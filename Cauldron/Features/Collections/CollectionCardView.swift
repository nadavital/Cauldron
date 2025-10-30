//
//  CollectionCardView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI

struct CollectionCardView: View {
    let collection: Collection
    let recipeImages: [URL?]  // Up to 4 recipe image URLs for the grid

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image/grid
            ZStack {
                if collection.coverImageType == .emoji, let emoji = collection.emoji {
                    // Show emoji
                    collectionColor
                        .frame(width: 160, height: 160)
                        .overlay(
                            Text(emoji)
                                .font(.system(size: 60))
                        )
                } else if collection.coverImageType == .color {
                    // Show solid color
                    collectionColor
                        .frame(width: 160, height: 160)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.8))
                                Text(collection.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                        )
                } else {
                    // Default: Show 2x2 grid of recipe images
                    recipeGridView
                        .frame(width: 160, height: 160)
                }
            }
            .cornerRadius(12)
            .clipped()

            // Collection name and count
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if let emoji = collection.emoji, collection.coverImageType != .emoji {
                        Text(emoji)
                            .font(.caption)
                    }
                    Text(collection.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 160, alignment: .leading)
            .padding(.top, 8)
        }
        .frame(width: 160)
    }

    // MARK: - Recipe Grid View

    private var recipeGridView: some View {
        Group {
            let size: CGFloat = 80  // 160 / 2 for the 2x2 grid

            if recipeImages.isEmpty || recipeImages.allSatisfy({ $0 == nil }) {
                // Empty state - show placeholder
                collectionColor
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.6))
                            Text("No recipes")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )
            } else {
                // Show 2x2 grid of recipe images
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        recipeImageTile(at: 0, size: size)
                        recipeImageTile(at: 1, size: size)
                    }
                    HStack(spacing: 0) {
                        recipeImageTile(at: 2, size: size)
                        recipeImageTile(at: 3, size: size)
                    }
                }
            }
        }
    }

    private func recipeImageTile(at index: Int, size: CGFloat) -> some View {
        Group {
            if index < recipeImages.count, let imageURL = recipeImages[index] {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        placeholderTile(size: size)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipped()
                    case .failure:
                        placeholderTile(size: size)
                    @unknown default:
                        placeholderTile(size: size)
                    }
                }
            } else {
                placeholderTile(size: size)
            }
        }
    }

    private func placeholderTile(size: CGFloat) -> some View {
        Rectangle()
            .fill(collectionColor.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.3))
                    .foregroundColor(.white.opacity(0.5))
            )
    }

    // MARK: - Color

    private var collectionColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }
}

// MARK: - Collection Reference Card

struct CollectionReferenceCardView: View {
    let reference: CollectionReference
    let recipeImages: [URL?]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover - show placeholder for referenced collections
            ZStack {
                Color.gray.opacity(0.2)
                    .aspectRatio(1, contentMode: .fill)

                VStack(spacing: 8) {
                    if let emoji = reference.collectionEmoji {
                        Text(emoji)
                            .font(.system(size: 50))
                    } else {
                        Image(systemName: "folder.badge.person.crop")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .cornerRadius(12)
            .overlay(
                // "Shared" badge
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .padding(8),
                alignment: .topTrailing
            )

            // Collection name and count
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if let emoji = reference.collectionEmoji {
                        Text(emoji)
                            .font(.caption)
                    }
                    Text(reference.collectionName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                Text("\(reference.recipeCount) recipe\(reference.recipeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }
}
