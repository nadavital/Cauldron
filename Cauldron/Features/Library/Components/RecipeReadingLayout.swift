import Foundation

/// Content-driven sizing shared by recipe reading and the pre-27.1 cook layout.
/// Receives the safe-area container width, never a device or main-screen size.
nonisolated enum RecipeReadingLayout {
    static func usesColumns(availableWidth: CGFloat, accessibilityText: Bool) -> Bool {
        !accessibilityText && availableWidth >= 760
    }

    static func workbenchWidth(availableWidth: CGFloat) -> CGFloat {
        min(360, max(280, availableWidth * 0.38))
    }
}
