//
//  RecipeDetailTextLayoutTests.swift
//  CauldronTests
//

import Foundation
import Testing
@testable import Cauldron

struct RecipeDetailTextLayoutTests {
    @Test func normalTextIsUnchanged() {
        let text = "Mix the flour, water, and salt until smooth."

        #expect(text.recipeDetailLineBreakFriendly() == text)
    }

    @Test func longUnbrokenTextGetsBreakOpportunitiesWithoutChangingVisibleCharacters() {
        let text = "https://example.com/recipes/super-long-imported-path-with-query?source=shareextension&tracking=abcdef1234567890"
        let wrapped = text.recipeDetailLineBreakFriendly(maxUnbrokenCharacters: 16)

        #expect(wrapped.contains("\u{200B}"))
        #expect(wrapped.replacingOccurrences(of: "\u{200B}", with: "") == text)
    }
}
