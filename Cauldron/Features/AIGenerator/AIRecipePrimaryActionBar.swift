import SwiftUI

/// A persistent action: validity changes enablement, never its place in the layout.
enum AIRecipePrimaryActionState: Equatable {
    case generate(isEnabled: Bool)
    case generating
    case save
    case saving

    var isEnabled: Bool {
        switch self {
        case .generate(let isEnabled): isEnabled
        case .save: true
        case .generating, .saving: false
        }
    }
}

struct AIRecipePrimaryActionBar: View {
    let state: AIRecipePrimaryActionState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                switch state {
                case .generate:
                    Label("Generate Recipe", systemImage: "wand.and.stars")
                case .generating:
                    ProgressView()
                    Text("Cooking up your recipe…")
                case .save:
                    Label("Save Recipe", systemImage: "checkmark")
                case .saving:
                    ProgressView()
                    Text("Saving Recipe…")
                }
            }
            .font(.headline)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
        }
        // Glass-prominent buttons can disappear in this sheet while remaining
        // in accessibility. Keep the primary action on a reliably drawn style.
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.cauldronOrange)
        .disabled(!state.isEnabled)
        .accessibilityIdentifier("aiRecipePrimaryAction")
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
