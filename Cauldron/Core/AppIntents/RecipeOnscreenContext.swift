import AppIntents
import SwiftUI

private struct RecipeOnscreenContext: ViewModifier {
    @ObservedObject private var session = CurrentUserSession.shared
    let recipe: Recipe

    func body(content: Content) -> some View {
        content.appEntityIdentifier(
            session.isAccountIdentityVerified && session.userId != nil &&
                recipe.ownerId == session.userId && !recipe.isPreview
                ? EntityIdentifier(for: RecipeIntentEntity.self, identifier: recipe.id)
                : nil
        )
    }
}

extension View {
    /// Observes account verification so an already-visible view drops stale Siri context.
    func recipeOnscreenContext(_ recipe: Recipe) -> some View {
        modifier(RecipeOnscreenContext(recipe: recipe))
    }
}
