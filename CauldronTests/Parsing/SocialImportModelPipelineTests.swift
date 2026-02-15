import Foundation
import XCTest
@testable import Cauldron

final class SocialImportModelPipelineTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockSocialURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockSocialURLProtocol.self)
        super.tearDown()
    }

    override func setUp() async throws {
        try await super.setUp()
        MockSocialURLProtocol.responseByURL = [:]
    }

    func testYouTubeImportUsesSharedModelParser() async throws {
        let url = "https://www.youtube.com/watch?v=abc123"
        MockSocialURLProtocol.responseByURL[url] = """
        <html><head>
        <meta property="og:title" content="Model YouTube Recipe - YouTube">
        <meta name="description" content="Ingredients: 1 cup rice 2 tbsp oil Instructions: Cook rice for 10 minutes and serve.">
        <meta property="og:image" content="https://example.com/thumb.jpg">
        </head><body></body></html>
        """

        let spy = SpySocialModelRecipeTextParser()
        let parser = YouTubeRecipeParser(
            foundationModelsService: FoundationModelsService(),
            textParser: spy
        )

        _ = try await parser.parse(from: url)

        let callCount = await spy.callCount
        let lines = await spy.lastLines
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(lines.joined(separator: "\n").lowercased().contains("ingredients"))
    }

    func testInstagramImportUsesSharedModelParser() async throws {
        let url = "https://www.instagram.com/p/abc123/"
        MockSocialURLProtocol.responseByURL[url] = """
        <html><head>
        <meta property="og:description" content="Easy Pasta Recipe Ingredients: 8 oz pasta 1 tbsp oil Instructions: Boil pasta and toss with oil.">
        <meta property="og:image" content="https://example.com/ig.jpg">
        </head><body></body></html>
        """

        let spy = SpySocialModelRecipeTextParser()
        let parser = InstagramRecipeParser(
            foundationModelsService: FoundationModelsService(),
            textParser: spy
        )

        _ = try await parser.parse(from: url)

        let callCount = await spy.callCount
        let lines = await spy.lastLines
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(lines.joined(separator: "\n").lowercased().contains("pasta"))
    }

    func testTikTokImportUsesSharedModelParser() async throws {
        let url = "https://www.tiktok.com/@creator/video/12345"
        MockSocialURLProtocol.responseByURL[url] = """
        <html><head>
        <meta property="og:description" content="Ingredients: 1 cup oats 2 tbsp yogurt  Instructions: Mix ingredients and chill 10 minutes.">
        <meta property="og:title" content="Overnight Oats | TikTok">
        <meta property="og:image" content="https://example.com/tt.jpg">
        </head><body></body></html>
        """

        let spy = SpySocialModelRecipeTextParser()
        let parser = TikTokRecipeParser(
            foundationModelsService: FoundationModelsService(),
            textParser: spy
        )

        _ = try await parser.parse(from: url)

        let callCount = await spy.callCount
        let lines = await spy.lastLines
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(lines.joined(separator: "\n").lowercased().contains("instructions"))
    }
}

private actor SpySocialModelRecipeTextParser: ModelRecipeTextParsing {
    private(set) var callCount = 0
    private(set) var lastLines: [String] = []

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
        lastLines = lines
        return Recipe(
            title: preferredTitle ?? "Social Spy Recipe",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Step", timers: [])],
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            imageURL: imageURL
        )
    }
}

private final class MockSocialURLProtocol: URLProtocol {
    static var responseByURL: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        return responseByURL[url] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url?.absoluteString,
              let payload = Self.responseByURL[url],
              let data = payload.data(using: .utf8) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
