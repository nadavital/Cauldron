//
//  CategorySelectionRow.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/14/25.
//

import SwiftUI

struct CategorySelectionRow: View {
    let title: String
    let icon: String
    let options: [RecipeCategory]
    @Binding var selected: Set<RecipeCategory>
    var horizontalPadding: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            toggleSelection(option)
                        } label: {
                            TagView(option.tagValue, isSelected: selected.contains(option))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 8)
            }
        }
    }

    private func toggleSelection(_ option: RecipeCategory) {
        withAnimation(.spring(response: 0.3)) {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        }
    }
}
