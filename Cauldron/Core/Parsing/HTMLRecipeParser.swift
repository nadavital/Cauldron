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
        extractor: ModelImportTextExtractor,
        textParser: any ModelRecipeTextParsing,
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
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ParsingError.invalidSource
            }

            if let html = String(data: data, encoding: .utf8) {
                return html
            }

            if let html = String(data: data, encoding: .isoLatin1) {
                return html
            }

            throw ParsingError.invalidSource
        } catch let error as ParsingError {
            throw error
        } catch {
            throw ParsingError.networkError(error)
        }
    }
}
