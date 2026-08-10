import AppIntents
import SwiftUI

struct RecipeEntityContextModifier: ViewModifier {
    let recipeID: UUID
    let isResolvable: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isResolvable {
            content.appEntityIdentifier(
                EntityIdentifier(for: RecipeIntentEntity.self, identifier: recipeID)
            )
        } else {
            content
        }
    }
}
