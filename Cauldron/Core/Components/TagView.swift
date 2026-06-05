//
//  TagView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/6/25.
//

import SwiftUI

/// A unified view for displaying tags across the app.
/// Automatically resolves the correct emoji and color from `RecipeCategory`.
struct TagView: View {
    let text: String
    let isSelected: Bool
    let onRemove: (() -> Void)?
    
    // Resolve category for styling
    private var category: RecipeCategory? {
        RecipeCategory.match(string: text)
    }
    
    // Use category display name if available, otherwise use text
    private var displayName: String {
        category?.displayName ?? text
    }
    
    private var emoji: String? {
        category?.emoji
    }
    
    private var color: Color {
        category?.color ?? .cauldronOrange
    }
    
    init(_ tag: Tag, isSelected: Bool = false, onRemove: (() -> Void)? = nil) {
        self.text = tag.name
        self.isSelected = isSelected
        self.onRemove = onRemove
    }
    
    init(_ text: String, isSelected: Bool = false, onRemove: (() -> Void)? = nil) {
        self.text = text
        self.isSelected = isSelected
        self.onRemove = onRemove
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if let emoji = emoji {
                Text(emoji)
                    .font(.caption2)
            }
            
            Text(displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)

            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .padding(4)
                        .background(color.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(displayName) tag")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(isSelected ? 0.25 : 0.15))
        .foregroundColor(color)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(color, lineWidth: isSelected ? 1.5 : 0)
        )
        // Collapse into a single labeled element only for display-only tags.
        // When a remove button is present we keep children accessible so the
        // remove action stays reachable by VoiceOver.
        .if(onRemove == nil) { view in
            view
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(displayName)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TagView("Breakfast")
        TagView("Italian", isSelected: true)
        TagView("Unknown Tag")
        TagView("Vegetarian", onRemove: {})
    }
}
