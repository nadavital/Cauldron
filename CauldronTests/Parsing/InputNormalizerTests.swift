//
//  InputNormalizerTests.swift
//  CauldronTests
//
//  Tests for InputNormalizer utility
//

import XCTest
@testable import Cauldron

@MainActor
final class InputNormalizerTests: XCTestCase {

    // MARK: - Line Break Normalization

    func testNormalize_WindowsLineBreaks() {
        let input = "Line 1\r\nLine 2\r\nLine 3"
        let result = InputNormalizer.normalize(input)
        XCTAssertTrue(result.contains("\n"))
        XCTAssertFalse(result.contains("\r"))
    }

    func testNormalize_OldMacLineBreaks() {
        let input = "Line 1\rLine 2\rLine 3"
        let result = InputNormalizer.normalize(input)
        XCTAssertTrue(result.contains("\n"))
        XCTAssertFalse(result.contains("\r"))
    }

    func testNormalize_MixedLineBreaks() {
        let input = "Line 1\r\nLine 2\rLine 3\nLine 4"
        let result = InputNormalizer.normalize(input)
        // All line breaks should be \n
        let lineCount = result.components(separatedBy: "\n").count
        XCTAssertEqual(lineCount, 4)
    }

    // MARK: - Social Media Artifact Removal

    func testNormalize_RemovesHashtags() {
        let input = "Great recipe! #foodie #homecooking #delicious"
        let result = InputNormalizer.normalize(input)
        XCTAssertFalse(result.contains("#foodie"))
        XCTAssertFalse(result.contains("#homecooking"))
        XCTAssertFalse(result.contains("#delicious"))
        XCTAssertTrue(result.contains("Great recipe!"))
    }

    func testNormalize_KeepsHashInMeasurements() {
        let input = "Use #10 can of tomatoes"
        let result = InputNormalizer.normalize(input)
        // #10 should remain since it's not followed by a letter
        XCTAssertTrue(result.contains("#10"))
    }

    func testNormalize_RemovesMentions() {
        let input = "Recipe by @chef_john adapted from @foodnetwork"
        let result = InputNormalizer.normalize(input)
        XCTAssertFalse(result.contains("@chef_john"))
        XCTAssertFalse(result.contains("@foodnetwork"))
        XCTAssertTrue(result.contains("Recipe by"))
    }

    func testNormalize_RemovesSocialPhrases() {
        let inputs = [
            "Follow me for more recipes",
            "Link in bio",
            "Tap to shop",
            "Double tap if you love pasta",
            "Save this post",
            "Tag a friend who loves cookies"
        ]

        for input in inputs {
            let result = InputNormalizer.normalize(input)
            XCTAssertTrue(result.trimmingCharacters(in: .whitespaces).isEmpty || result.count < input.count,
                         "Failed to remove social phrase: \(input)")
        }
    }

    // MARK: - Unicode Bullet Normalization

    func testNormalize_UnicodeBullets() {
        let bullets = ["●", "○", "◦", "▪", "▫", "■", "□", "▸", "▹", "►", "▻", "➤", "➢", "→"]

        for bullet in bullets {
            let input = "\(bullet) First item"
            let result = InputNormalizer.normalize(input)
            XCTAssertTrue(result.contains("•") || !result.contains(bullet),
                         "Failed to normalize bullet: \(bullet)")
        }
    }

    func testNormalize_DashNormalization() {
        let input = "– En dash — Em dash"
        let result = InputNormalizer.normalize(input)
        // En dash and em dash should be normalized to hyphen
        XCTAssertTrue(result.contains("-"))
    }

    // MARK: - Whitespace Cleanup

    func testNormalize_MultipleSpaces() {
        let input = "Too    many     spaces"
        let result = InputNormalizer.normalize(input)
        XCTAssertFalse(result.contains("  "))
        XCTAssertTrue(result.contains("Too many spaces"))
    }

    func testNormalize_ExcessiveNewlines() {
        let input = "Line 1\n\n\n\n\nLine 2"
        let result = InputNormalizer.normalize(input)
        // Should collapse to max 2 newlines
        XCTAssertFalse(result.contains("\n\n\n"))
    }

    func testNormalize_TrimWhitespace() {
        let input = "   Trimmed content   "
        let result = InputNormalizer.normalize(input)
        XCTAssertEqual(result, "Trimmed content")
    }

    // MARK: - Recipe Content Validation

    func testTextLooksLikeRecipe_ValidRecipe() {
        let validRecipes = [
            "2 cups flour, 1 tbsp sugar. Mix and bake at 350°F.",
            "Ingredients: flour, sugar. Instructions: mix, cook, serve.",
            "Recipe for chocolate cake. Add 2 cups flour and bake."
        ]

        for recipe in validRecipes {
            XCTAssertTrue(InputNormalizer.textLooksLikeRecipe(recipe),
                         "Should recognize as recipe: \(recipe)")
        }
    }

    func testTextLooksLikeRecipe_NotRecipe() {
        let nonRecipes = [
            "Hello world",
            "This is just random text",
            "No cooking keywords here"
        ]

        for text in nonRecipes {
            XCTAssertFalse(InputNormalizer.textLooksLikeRecipe(text),
                          "Should not recognize as recipe: \(text)")
        }
    }

    // MARK: - HTML Entity Handling

    func testNormalize_HTMLEntities() {
        let input = "Use &frac12; cup flour &amp; 1 tsp salt"
        let result = InputNormalizer.normalize(input)
        XCTAssertTrue(result.contains("½") || result.contains("1/2"))
        XCTAssertTrue(result.contains("&") || !result.contains("&amp;"))
    }

    // MARK: - Integration Tests

    func testNormalize_RealWorldSocialMediaPost() {
        let input = """
        THE BEST Chocolate Chip Cookies! 🍪

        #chocolate #cookies #baking #homemade

        Follow me @bakerlove for more!

        Ingredients:
        • 2 cups flour
        • 1 cup sugar

        Link in bio for full recipe!

        #foodie #yummy #delicious
        """

        let result = InputNormalizer.normalize(input)

        // Should keep the important content
        XCTAssertTrue(result.contains("Chocolate Chip Cookies"))
        XCTAssertTrue(result.contains("Ingredients"))
        XCTAssertTrue(result.contains("flour"))
        XCTAssertTrue(result.contains("sugar"))

        // Should remove social media artifacts
        XCTAssertFalse(result.contains("#chocolate"))
        XCTAssertFalse(result.contains("@bakerlove"))
        XCTAssertFalse(result.contains("Link in bio"))
    }

    func testNormalize_MessyWebsitePaste() {
        let input = """
        Recipe Title\r\n\r\n\r\n

        Servings: 4    |    Time: 30 min

        INGREDIENTS:\r\n► 2 cups flour\r\n► 1 cup sugar

        INSTRUCTIONS:\r\n1. Mix well\r\n2. Bake
        """

        let result = InputNormalizer.normalize(input)

        // Should normalize structure
        XCTAssertFalse(result.contains("\r"))
        XCTAssertFalse(result.contains("\n\n\n"))
        XCTAssertTrue(result.contains("Recipe Title"))
        XCTAssertTrue(result.contains("flour"))
    }

    // MARK: - Edge Cases

    func testNormalize_EmptyString() {
        let result = InputNormalizer.normalize("")
        XCTAssertEqual(result, "")
    }

    func testNormalize_OnlyWhitespace() {
        let result = InputNormalizer.normalize("   \n\n   \t   ")
        XCTAssertEqual(result, "")
    }

    func testNormalize_PreservesImportantContent() {
        let input = "Mix 1-2 cups of flour with 1/2 tsp salt"
        let result = InputNormalizer.normalize(input)
        // Should preserve the measurement range and fraction
        XCTAssertTrue(result.contains("1-2") || result.contains("1 - 2"))
        XCTAssertTrue(result.contains("1/2"))
    }
}
