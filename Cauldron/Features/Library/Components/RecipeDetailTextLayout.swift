//
//  RecipeDetailTextLayout.swift
//  Cauldron
//
//  Display-only text helpers for recipe detail content.
//

import Foundation

extension String {
    func recipeDetailLineBreakFriendly(maxUnbrokenCharacters: Int = 28) -> String {
        guard maxUnbrokenCharacters > 0, !isEmpty else {
            return self
        }

        var result = String.UnicodeScalarView()
        var unbrokenCount = 0

        for scalar in unicodeScalars {
            result.append(scalar)

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                unbrokenCount = 0
                continue
            }

            if scalar == "\u{200B}" {
                unbrokenCount = 0
                continue
            }

            unbrokenCount += 1

            let shouldPreferBreak = Self.recipeDetailPreferredBreakScalars.contains(scalar)
                && unbrokenCount >= Self.recipeDetailPreferredBreakMinimumRunLength
            if shouldPreferBreak || unbrokenCount >= maxUnbrokenCharacters {
                result.append("\u{200B}")
                unbrokenCount = 0
            }
        }

        return String(result)
    }

    private static let recipeDetailPreferredBreakScalars = Set("/\\-_.:,;?&=+#%()[]{}".unicodeScalars)
    private static let recipeDetailPreferredBreakMinimumRunLength = 8
}
