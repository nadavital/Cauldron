import XCTest
@testable import Cauldron

final class RecipeWebExtractionCoreTests: XCTestCase {
    func testJSONLDExtractionIncludesStructuredMetadata() throws {
        let html = """
        <html>
          <head>
            <title>Sample Recipe Page</title>
            <script type=\"application/ld+json\">
            {
              \"@context\": \"https://schema.org\",
              \"@type\": \"Recipe\",
              \"name\": \"Core Pancakes\",
              \"recipeIngredient\": [\"1 cup flour\", \"1 egg\"],
              \"recipeInstructions\": [\"1. Mix\", \"2. Cook\"],
              \"recipeYield\": \"2 servings\",
              \"totalTime\": \"PT25M\",
              \"recipeCategory\": \"Breakfast\",
              \"keywords\": \"easy, quick\",
              \"image\": \"https://example.com/image.jpg\"
            }
            </script>
          </head>
          <body></body>
        </html>
        """

        let core = RecipeWebExtractionCore()
        let extraction = try XCTUnwrap(core.extract(fromHTML: html, sourceURL: URL(string: "https://example.com")))

        XCTAssertEqual(extraction.method, "jsonld_recipe")
        XCTAssertEqual(extraction.title, "Core Pancakes")
        XCTAssertEqual(extraction.pageTitle, "Sample Recipe Page")
        XCTAssertEqual(extraction.ingredientLines, ["1 cup flour", "1 egg"])
        XCTAssertEqual(extraction.stepLines, ["1. Mix", "2. Cook"])
        XCTAssertEqual(extraction.yields, "2 servings")
        XCTAssertEqual(extraction.totalMinutes, 25)
        XCTAssertEqual(extraction.imageURL?.absoluteString, "https://example.com/image.jpg")
        XCTAssertTrue(extraction.rawTagNames.contains("Breakfast"))
        XCTAssertTrue(extraction.rawTagNames.contains("easy"))
    }

    func testVisibleHTMLFallbackReturnsTitleAndRawLines() throws {
        let html = """
        <html>
          <head><title>Fallback Page</title></head>
          <body>
            <main>
              <p>Line one of recipe text.</p>
              <p>Line two of recipe text.</p>
            </main>
          </body>
        </html>
        """

        let core = RecipeWebExtractionCore()
        let extraction = try XCTUnwrap(core.extract(fromHTML: html))

        XCTAssertEqual(extraction.method, "html_visible_text")
        XCTAssertEqual(extraction.title, "Fallback Page")
        XCTAssertEqual(extraction.pageTitle, "Fallback Page")
        XCTAssertTrue(extraction.rawLines.contains("Fallback Page"))
        XCTAssertFalse(extraction.rawLines.isEmpty)
    }
}
