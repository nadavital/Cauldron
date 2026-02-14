import XCTest
@testable import Cauldron

final class ModelImportTextExtractorTests: XCTestCase {

    func testCollapsedNumberedInstructionBlobSplitsIntoSteps() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "Blob Split Test",
          "recipeIngredient": ["1 cup flour", "1 egg"],
          "recipeInstructions": "1. Mix flour and egg. 2. Bake for 20 minutes. 3. Cool before slicing."
        }
        </script>
        </head><body></body></html>
        """

        let extractor = ModelImportTextExtractor()
        let result = try XCTUnwrap(extractor.extract(fromHTML: html))

        XCTAssertEqual(result.title, "Blob Split Test")
        XCTAssertEqual(result.ingredientLines.count, 2)
        XCTAssertEqual(result.stepLines.count, 3)
        XCTAssertTrue(result.stepLines[0].contains("1. Mix flour and egg"))
    }

    func testSentenceInstructionDoesNotSplitOnPeriod() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "No Sentence Split",
          "recipeIngredient": ["2 tbsp butter"],
          "recipeInstructions": [
            "Whisk butter until smooth. Add salt and keep whisking."
          ]
        }
        </script>
        </head><body></body></html>
        """

        let extractor = ModelImportTextExtractor()
        let result = try XCTUnwrap(extractor.extract(fromHTML: html))

        XCTAssertEqual(result.stepLines.count, 1)
        XCTAssertEqual(result.stepLines[0], "Whisk butter until smooth. Add salt and keep whisking.")
    }
}
