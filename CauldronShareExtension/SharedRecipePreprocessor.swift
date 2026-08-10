import Foundation

enum SharedRecipePreprocessor {
    private static let extractor = RecipeWebExtractionCore()

    static func prepareRecipePayload(from url: URL) async -> PreparedShareRecipePayload? {
        guard let html = await fetchHTML(from: url),
              let extraction = extractor.extract(fromHTML: html, sourceURL: url) else {
            return nil
        }

        let resolvedTitle = (extraction.title ?? extraction.pageTitle)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredients = extraction.ingredientLines
        let steps = extraction.stepLines

        guard let title = resolvedTitle, !title.isEmpty, !ingredients.isEmpty, !steps.isEmpty else {
            return nil
        }

        return PreparedShareRecipePayload(
            title: title,
            ingredients: Array(ingredients.prefix(80)),
            steps: Array(steps.prefix(80)),
            yields: extraction.yields,
            totalMinutes: extraction.totalMinutes,
            sourceURL: url.absoluteString,
            sourceTitle: extraction.pageTitle,
            imageURL: extraction.imageURL?.absoluteString,
            tagNames: extraction.rawTagNames,
            notes: extraction.noteLines.isEmpty ? nil : extraction.noteLines.joined(separator: "\n")
        )
    }

    private static func fetchHTML(from url: URL) async -> String? {
        try? await RecipeHTTPDocumentLoader.loadHTML(from: url)
    }
}
