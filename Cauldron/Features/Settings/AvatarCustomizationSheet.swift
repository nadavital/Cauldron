//
//  AvatarCustomizationSheet.swift
//  Cauldron
//
//  Sheet for customizing user avatar with emoji and color
//

import SwiftUI

struct AvatarCustomizationSheet: View {
    @Binding var selectedEmoji: String?
    @Binding var selectedColor: String?
    @Environment(\.dismiss) private var dismiss
    @State private var showingEmojiPicker = false

    // Food-themed emojis for profile customization
    private let foodEmojis = [
        "🍕", "🍔", "🍟", "🌭", "🍿", "🥓",
        "🥖", "🥐", "🥯", "🧀", "🥞", "🧇",
        "🍳", "🥗", "🥘", "🍲", "🍜", "🍝",
        "🍛", "🍣", "🍱", "🍤", "🍙", "🍚"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Preview
                    previewSection

                    // Emoji picker
                    emojiSection

                    // Color picker
                    colorSection
                }
                .padding()
            }
            .navigationTitle("Customize Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPickerView(selectedEmoji: $selectedEmoji)
            }
        }
    }

    private var previewSection: some View {
        VStack(spacing: 12) {
            // Avatar preview
            Circle()
                .fill(backgroundColor.opacity(0.3))
                .frame(width: 100, height: 100)
                .overlay(
                    Text(displayContent)
                        .font(.system(size: 50))
                        .fontWeight(selectedEmoji != nil ? .regular : .bold)
                        .foregroundColor(backgroundColor)
                )

            Text("Preview")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(12)
    }

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile Emoji")
                .font(.headline)
                .foregroundColor(.primary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                ForEach(foodEmojis, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                    } label: {
                        Text(emoji)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(selectedEmoji == emoji ? Color.cauldronOrange.opacity(0.2) : Color.cauldronSecondaryBackground)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Button {
                    showingEmojiPicker = true
                } label: {
                    Label("Choose Emoji", systemImage: "face.smiling")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    selectedEmoji = foodEmojis.randomElement()
                } label: {
                    Label("Random", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.cauldronOrange)
            }

            if selectedEmoji != nil {
                Button {
                    selectedEmoji = nil
                } label: {
                    Label("Clear Selection", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile Color")
                .font(.headline)
                .foregroundColor(.primary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                ForEach(Color.allProfileColors, id: \.self) { color in
                    Button {
                        selectedColor = color.toHex()
                    } label: {
                        Circle()
                            .fill(color.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: selectedColor == color.toHex() ? 3 : 0)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .foregroundColor(color)
                                    .font(.headline)
                                    .opacity(selectedColor == color.toHex() ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                selectedColor = Color.allProfileColors.randomElement()?.toHex()
            } label: {
                Label("Random Color", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.cauldronOrange)
        }
    }

    // MARK: - Helper Properties

    private var backgroundColor: Color {
        if let colorHex = selectedColor, let color = Color.fromHex(colorHex) {
            return color
        }
        return .profileOrange
    }

    private var displayContent: String {
        if let emoji = selectedEmoji, !emoji.isEmpty {
            return emoji
        }
        return "AB"  // Placeholder initials for preview
    }
}

#Preview {
    AvatarCustomizationSheet(
        selectedEmoji: .constant("🍕"),
        selectedColor: .constant(Color.profilePink.toHex())
    )
}
