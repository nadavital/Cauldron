//
//  HTMLRecipeParser.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Parser for extracting recipes from HTML URLs through the shared model-backed text pipeline.
actor HTMLRecipeParser: RecipeParser {
    typealias HTMLFetcher = @Sendable (URL) async throws -> String

    private let extractor: ModelImportTextExtractor
    private let textParser: any ModelRecipeTextParsing
    private let htmlFetcher: HTMLFetcher

    init(
        extractor: ModelImportTextExtractor = ModelImportTextExtractor(),
        textParser: any ModelRecipeTextParsing = TextRecipeParser(),
        htmlFetcher: @escaping HTMLFetcher = HTMLRecipeParser.defaultHTMLFetcher(for:)
    ) {
        self.extractor = extractor
        self.textParser = textParser
        self.htmlFetcher = htmlFetcher
    }

    func parse(from urlString: String) async throws -> Recipe {
        guard let url = URL(string: urlString) else {
            throw ParsingError.invalidSource
        }

        let html = try await htmlFetcher(url)

        guard let extraction = extractor.extract(fromHTML: html, sourceURL: url) else {
            throw ParsingError.noRecipeFound
        }

        return try await textParser.parse(
            lines: extraction.rawLines,
            sourceURL: url,
            sourceTitle: url.host,
            imageURL: extraction.imageURL,
            tags: extraction.tags,
            preferredTitle: extraction.title,
            yieldsOverride: extraction.yields,
            totalMinutesOverride: extraction.totalMinutes
        )
    }

    nonisolated private static func defaultHTMLFetcher(for url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParsingError.invalidSource
        }
        return html
    }
}
