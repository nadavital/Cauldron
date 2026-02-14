import Foundation
import XCTest
@testable import Cauldron

final class URLImportModelPipelineTests: XCTestCase {
    func testHTMLImportRoutesThroughSharedModelTextParser() async throws {
        let url = "https://example.com/recipe"
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context":"https://schema.org",
          "@type":"Recipe",
          "name":"Model URL Import",
          "recipeIngredient":["1 cup flour","1 egg"],
          "recipeInstructions":["1. Mix ingredients","2. Bake for 20 minutes"]
        }
        </script>
        </head><body></body></html>
        """

        let spy = SpyModelRecipeTextParser()
        let parser = HTMLRecipeParser(
            extractor: ModelImportTextExtractor(),
            textParser: spy,
            htmlFetcher: { _ in html }
        )

        _ = try await parser.parse(from: url)

        let callCount = await spy.callCount
        let captured = await spy.capturedLines
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(captured.contains("Ingredients"))
        XCTAssertTrue(captured.contains("Instructions"))
    }
}

private actor SpyModelRecipeTextParser: ModelRecipeTextParsing {
    private(set) var callCount = 0
    private(set) var capturedLines: [String] = []

    func parse(
        lines: [String],
        sourceURL: URL?,
        sourceTitle: String?,
        imageURL: URL?,
        tags: [Tag],
        preferredTitle: String?,
        yieldsOverride: String?,
        totalMinutesOverride: Int?
    ) async throws -> Recipe {
        callCount += 1
        capturedLines = lines
        return Recipe(
            title: preferredTitle ?? "Spy Recipe",
            ingredients: [Ingredient(name: "Flour")],
            steps: [CookStep(index: 0, text: "Mix", timers: [])],
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            imageURL: imageURL
        )
    }
}
