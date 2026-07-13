import Foundation

enum SharedRecipePreprocessor {
    private static let extractor = RecipeWebExtractionCore()
    private static let maximumHTMLBytes = 3_000_000

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
            tagNames: extraction.rawTagNames
        )
    }

    private static func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  httpResponse.mimeType == nil || httpResponse.mimeType == "text/html" || httpResponse.mimeType == "application/xhtml+xml",
                  httpResponse.expectedContentLength <= Int64(maximumHTMLBytes) || httpResponse.expectedContentLength < 0 else {
                return nil
            }
            var data = Data()
            data.reserveCapacity(min(max(Int(httpResponse.expectedContentLength), 0), maximumHTMLBytes))
            for try await byte in bytes {
                guard data.count < maximumHTMLBytes else { return nil }
                data.append(byte)
            }

            if let html = String(data: data, encoding: .utf8) {
                return html
            }

            if let html = String(data: data, encoding: .isoLatin1) {
                return html
            }

            return nil
        } catch {
            return nil
        }
    }
}
