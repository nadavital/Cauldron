//
//  PreparedSharedRecipeBridgeTests.swift
//  CauldronTests
//
//  Created on February 12, 2026.
//

import XCTest
@testable import Cauldron

@MainActor
final class PreparedSharedRecipeBridgeTests: XCTestCase {

    func testRecipeParserInputText_ContainsMetadataSectionsAndNotes() {
        let recipe = Recipe(
            title: "Sheet Pan Chicken",
            ingredients: [
                Ingredient(name: "chicken thighs", quantity: Quantity(value: 1.5, unit: .pound)),
                Ingredient(name: "soy sauce", quantity: Quantity(value: 0.25, unit: .cup), section: "Sauce")
            ],
            steps: [
                CookStep(index: 0, text: "Preheat oven to 425F."),
                CookStep(index: 1, text: "Whisk the sauce.", section: "Sauce")
            ],
            yields: "4 servings",
            totalMinutes: 35,
            notes: "Optional: add sesame seeds."
        )
        let prepared = PreparedSharedRecipe(recipe: recipe, sourceInfo: "Imported from shared webpage")

        let parserInput = prepared.recipeParserInputText()

        XCTAssertTrue(parserInput.contains("Sheet Pan Chicken"))
        XCTAssertTrue(parserInput.contains("Servings: 4 servings"))
        XCTAssertTrue(parserInput.contains("Total Time: 35 minutes"))
        XCTAssertTrue(parserInput.contains("Ingredients:"))
        XCTAssertTrue(parserInput.contains("Sauce:"))
        XCTAssertTrue(parserInput.contains("Instructions:"))
        XCTAssertTrue(parserInput.contains("1. Preheat oven to 425F."))
        XCTAssertTrue(parserInput.contains("2. Whisk the sauce."))
        XCTAssertTrue(parserInput.contains("Notes:"))
        XCTAssertTrue(parserInput.contains("Optional: add sesame seeds."))
    }

    func testRecipeMergedWithParsedContent_PreservesShareMetadata() {
        let sourceURL = URL(string: "https://example.com/recipe")!
        let imageURL = URL(string: "https://example.com/image.jpg")!

        let baseRecipe = Recipe(
            title: "Original Title",
            ingredients: [Ingredient(name: "original ingredient")],
            steps: [CookStep(index: 0, text: "Original step.")],
            yields: "4 servings",
            totalMinutes: 30,
            sourceURL: sourceURL,
            sourceTitle: "Example Source",
            notes: "Original note.",
            imageURL: imageURL
        )
        let prepared = PreparedSharedRecipe(recipe: baseRecipe, sourceInfo: "Imported from shared webpage")

        let parsedRecipe = Recipe(
            title: "Parsed Title",
            ingredients: [Ingredient(name: "parsed ingredient")],
            steps: [CookStep(index: 0, text: "Parsed step.")],
            yields: "2 servings",
            totalMinutes: nil,
            notes: "Parsed note."
        )

        let merged = prepared.recipeMergedWithParsedContent(parsedRecipe)

        XCTAssertEqual(merged.id, baseRecipe.id)
        XCTAssertEqual(merged.title, "Parsed Title")
        XCTAssertEqual(merged.ingredients.map(\.name), ["parsed ingredient"])
        XCTAssertEqual(merged.steps.map(\.text), ["Parsed step."])
        XCTAssertEqual(merged.yields, "2 servings")
        XCTAssertEqual(merged.totalMinutes, 30)
        XCTAssertEqual(merged.sourceURL, sourceURL)
        XCTAssertEqual(merged.sourceTitle, "Example Source")
        XCTAssertEqual(merged.imageURL, imageURL)
        XCTAssertEqual(merged.notes, "Parsed note.")
    }

    func testPreparedShareRecipeParserInput_ReparseProducesIngredientsAndSteps() async throws {
        let recipe = Recipe(
            title: "Shared Noodles",
            ingredients: [
                Ingredient(name: "8 oz noodles"),
                Ingredient(name: "2 tbsp soy sauce")
            ],
            steps: [
                CookStep(index: 0, text: "Boil noodles for 6 minutes."),
                CookStep(index: 1, text: "Toss with soy sauce.")
            ],
            yields: "2 servings",
            totalMinutes: 15,
            notes: "Serve warm."
        )
        let prepared = PreparedSharedRecipe(recipe: recipe, sourceInfo: "Imported from shared webpage")

        let parser = TextRecipeParser()
        let reparsed = try await parser.parse(from: prepared.recipeParserInputText())

        XCTAssertFalse(reparsed.ingredients.isEmpty)
        XCTAssertFalse(reparsed.steps.isEmpty)
    }

    func testPreparedSharePayload_DecodeViaStoreConversionPath() throws {
        let payload = PreparedShareRecipePayload(
            title: "Share Sheet Pasta",
            ingredients: ["8 oz pasta", "2 tbsp butter"],
            steps: ["Boil pasta", "Stir in butter"],
            yields: "2 servings",
            totalMinutes: 12,
            sourceURL: "https://example.com/pasta",
            sourceTitle: "Example Pasta",
            imageURL: "https://example.com/pasta.jpg",
            tagNames: ["Dinner", "Pasta"]
        )

        let data = try JSONEncoder().encode(payload)
        let prepared = ShareExtensionImportStore.preparedRecipe(from: data)

        XCTAssertEqual(prepared?.recipe.title, "Share Sheet Pasta")
        XCTAssertEqual(prepared?.recipe.ingredients.map(\.name), ["8 oz pasta", "2 tbsp butter"])
        XCTAssertEqual(prepared?.recipe.steps.map(\.text), ["Boil pasta", "Stir in butter"])
        XCTAssertEqual(prepared?.recipe.totalMinutes, 12)
        XCTAssertEqual(prepared?.recipe.sourceURL?.absoluteString, "https://example.com/pasta")
        XCTAssertEqual(prepared?.recipe.tags.map(\.name), ["Dinner", "Pasta"])
        XCTAssertEqual(prepared?.sourceInfo, "Imported from https://example.com/pasta")
    }

    func testPreparedSharePayload_InvalidRequiredFieldsFailsConversion() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "ingredients": ["8 oz pasta"],
            "steps": ["Boil pasta"]
        ])

        XCTAssertNil(ShareExtensionImportStore.preparedRecipe(from: data))
    }

    func testPreparedPayloadCanonicalizationMatchesTextEntryAndPreservesSourceMetadata() async throws {
        let payload = PreparedShareRecipePayload(
            title: "Skillet Flatbread",
            ingredients: [
                "Dough:",
                "1 cup flour",
                "1 teaspoon salt",
                "Topping:",
                "2 tablespoons olive oil"
            ],
            steps: [
                "Dough:",
                "Mix the flour and salt.",
                "Topping:",
                "Heat the olive oil for 5 minutes."
            ],
            yields: "2 servings",
            totalMinutes: 25,
            sourceURL: "https://example.com/skillet-flatbread",
            sourceTitle: "Example Kitchen",
            imageURL: "https://example.com/flatbread.jpg",
            tagNames: ["Dinner", "Bread"],
            notes: "Keep covered until serving."
        )
        let payloadData = try JSONEncoder().encode(payload)
        let prepared = try XCTUnwrap(ShareExtensionImportStore.preparedRecipe(from: payloadData))
        let parser = TextRecipeParser()

        let textEntry = try await parser.parse(from: prepared.recipeParserInputText())
        let canonical = await prepared.canonicalized(using: parser)

        XCTAssertEqual(canonical.recipe.title, textEntry.title)
        XCTAssertEqual(canonical.recipe.yields, textEntry.yields)
        XCTAssertEqual(canonical.recipe.totalMinutes, textEntry.totalMinutes)
        XCTAssertEqual(canonical.recipe.ingredients.map(ingredientSignature), textEntry.ingredients.map(ingredientSignature))
        XCTAssertEqual(canonical.recipe.steps.map(stepSignature), textEntry.steps.map(stepSignature))
        XCTAssertEqual(canonical.recipe.notes, textEntry.notes)

        let flour = try XCTUnwrap(canonical.recipe.ingredients.first(where: { $0.name == "flour" }))
        XCTAssertEqual(flour.quantity?.value, 1)
        XCTAssertEqual(flour.quantity?.unit, .cup)
        XCTAssertEqual(flour.section, "Dough")
        XCTAssertFalse(canonical.recipe.ingredients.contains(where: { $0.name == "1 cup flour" }))

        let timedStep = try XCTUnwrap(canonical.recipe.steps.first(where: { $0.text.contains("olive oil") }))
        XCTAssertEqual(timedStep.section, "Topping")
        XCTAssertEqual(timedStep.timers.map(\.seconds), [300])

        XCTAssertEqual(canonical.recipe.sourceURL?.absoluteString, payload.sourceURL)
        XCTAssertEqual(canonical.recipe.sourceTitle, payload.sourceTitle)
        XCTAssertEqual(canonical.recipe.imageURL?.absoluteString, payload.imageURL)
        XCTAssertEqual(canonical.recipe.tags.map(\.name), payload.tagNames)
        XCTAssertEqual(canonical.sourceInfo, "Imported from https://example.com/skillet-flatbread")
        XCTAssertNil(textEntry.sourceURL)
        XCTAssertNil(textEntry.sourceTitle)
        XCTAssertNil(textEntry.imageURL)
    }

    func testPreparedPayloadNotesRoundTripWithoutTags() throws {
        let payload = PreparedShareRecipePayload(
            title: "Simple Soup",
            ingredients: ["1 cup stock"],
            steps: ["Simmer for 5 minutes"],
            notes: "Freeze for up to one month."
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PreparedShareRecipePayload.self, from: data)

        XCTAssertTrue(decoded.tagNames.isEmpty)
        XCTAssertEqual(decoded.notes, payload.notes)
        XCTAssertEqual(
            ShareExtensionImportStore.preparedRecipe(from: data)?.recipe.notes,
            payload.notes
        )
    }

    func testJSONLDHowToSectionNumericTitleSurvivesPreparedCanonicalization() async throws {
        let html = """
        <html>
          <head>
            <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Recipe",
              "name": "Two Day Bread",
              "recipeIngredient": ["1 cup flour", "1 teaspoon salt"],
              "recipeInstructions": [
                {
                  "@type": "HowToSection",
                  "name": "Day 1",
                  "itemListElement": [
                    {"@type": "HowToStep", "text": "Mix the dough."}
                  ]
                },
                {
                  "@type": "HowToSection",
                  "name": "Stage 3",
                  "itemListElement": [
                    {"@type": "HowToStep", "text": "Bake for 30 minutes."}
                  ]
                }
              ]
            }
            </script>
          </head>
        </html>
        """
        let extraction = try XCTUnwrap(RecipeWebExtractionCore().extract(fromHTML: html))
        XCTAssertEqual(
            extraction.stepLines,
            ["Day 1:", "Mix the dough.", "Stage 3:", "Bake for 30 minutes."]
        )

        let payload = PreparedShareRecipePayload(
            title: try XCTUnwrap(extraction.title),
            ingredients: extraction.ingredientLines,
            steps: extraction.stepLines
        )
        let prepared = try XCTUnwrap(
            ShareExtensionImportStore.preparedRecipe(from: JSONEncoder().encode(payload))
        )
        let canonical = await prepared.canonicalized(using: TextRecipeParser())

        XCTAssertEqual(canonical.recipe.steps.map(\.section), ["Day 1", "Stage 3"])
        XCTAssertFalse(canonical.recipe.steps.contains(where: {
            $0.text == "Day 1:" || $0.text == "Stage 3:"
        }))
        XCTAssertEqual(
            canonical.recipe.steps.last?.timers.map(\.seconds),
            [1_800]
        )
    }

    func testQuantityAndNumberedStepLabelsAreNotDiscardedAsNumericSections() throws {
        let payload = PreparedShareRecipePayload(
            title: "Colon Content",
            ingredients: ["1 cup flour:", "2 teaspoons salt"],
            steps: ["Step 1:", "Mix everything"]
        )

        let prepared = try XCTUnwrap(
            ShareExtensionImportStore.preparedRecipe(from: JSONEncoder().encode(payload))
        )

        XCTAssertEqual(prepared.recipe.ingredients.first?.name, "1 cup flour:")
        XCTAssertEqual(prepared.recipe.steps.first?.text, "Step 1:")
        XCTAssertNil(prepared.recipe.ingredients.first?.section)
        XCTAssertNil(prepared.recipe.steps.first?.section)
    }

    private func ingredientSignature(_ ingredient: Ingredient) -> String {
        [
            ingredient.name,
            ingredient.quantity.map { String($0.value) } ?? "",
            ingredient.quantity?.unit.rawValue ?? "",
            ingredient.section ?? "",
            ingredient.note ?? ""
        ].joined(separator: "|")
    }

    private func stepSignature(_ step: CookStep) -> String {
        [
            String(step.index),
            step.text,
            step.section ?? "",
            step.timers.map { "\($0.seconds):\($0.label)" }.joined(separator: ",")
        ].joined(separator: "|")
    }
}
