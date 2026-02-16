import Foundation

/// App adapter over the shared recipe web extraction core.
struct ModelImportTextExtractor: Sendable {
    struct Extraction: Sendable {
        let method: String
        let title: String?
        let ingredientLines: [String]
        let stepLines: [String]
        let noteLines: [String]
        let rawLines: [String]
        let yields: String?
        let totalMinutes: Int?
        let imageURL: URL?
        let tags: [Tag]
    }

    private let core = RecipeWebExtractionCore()

    func extract(fromHTML html: String, sourceURL: URL? = nil) -> Extraction? {
        guard let extraction = core.extract(fromHTML: html, sourceURL: sourceURL) else {
            return nil
        }

        let tags = extraction.rawTagNames.map { Tag(name: $0) }

        return Extraction(
            method: extraction.method,
            title: extraction.title,
            ingredientLines: extraction.ingredientLines,
            stepLines: extraction.stepLines,
            noteLines: extraction.noteLines,
            rawLines: extraction.rawLines,
            yields: extraction.yields,
            totalMinutes: extraction.totalMinutes,
            imageURL: extraction.imageURL,
            tags: tags
        )
    }
}
