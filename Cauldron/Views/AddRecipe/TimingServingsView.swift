import SwiftUI

struct TimingServingsView: View {
    @Binding var prepTime: String
    @Binding var cookTime: String
    @Binding var servings: String

    var body: some View {
        RecipeInputCard(title: "Timing & Servings", systemImage: "clock") {
            TimeServingsInputRow(
                prepTime: $prepTime,
                cookTime: $cookTime,
                servings: $servings
            )
            .eraseToAnyView()
        }
    }
}

// Helper to satisfy AnyView in RecipeInputCard
private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}