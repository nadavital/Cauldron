//
//  RecipeLayoutControls.swift
//  Cauldron
//

import SwiftUI

enum RecipeLayoutMode: String {
    case auto
    case compact
    case grid

    static let appStorageKey = "recipes.layoutMode"

    func resolved(for horizontalSizeClass: UserInterfaceSizeClass?) -> RecipeLayoutMode {
        if self == .auto {
            return horizontalSizeClass == .regular ? .grid : .compact
        }
        return self
    }

    var iconName: String {
        switch self {
        case .grid:
            "square.grid.2x2"
        case .compact, .auto:
            "list.bullet"
        }
    }

    static var defaultGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 16)]
    }
}

struct RecipeLayoutToolbarButton: View {
    let resolvedMode: RecipeLayoutMode
    let onSelectMode: (RecipeLayoutMode) -> Void

    var body: some View {
        Menu {
            Button {
                onSelectMode(.grid)
            } label: {
                HStack {
                    Label("Grid", systemImage: "square.grid.2x2")
                    if resolvedMode == .grid {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                onSelectMode(.compact)
            } label: {
                HStack {
                    Label("Compact", systemImage: "list.bullet")
                    if resolvedMode == .compact {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: resolvedMode.iconName)
        }
    }
}
