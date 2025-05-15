import SwiftUI

struct TagsSelectionView: View {
    @Binding var selectedTagIDs: Set<String>

    var body: some View {
        RecipeInputCard(title: "Tags", systemImage: "tag") {
            TagSelectorField(label: "Recipe Tags", selectedTagIDs: $selectedTagIDs)
                .eraseToAnyView()
        }
    }
}

// Helper to wrap into AnyView for RecipeInputCard
private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}