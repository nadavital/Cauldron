import XCTest
@testable import Cauldron

final class RecipeHTTPDocumentLoaderTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecipeDocumentURLProtocol.self]
        session = URLSession(configuration: configuration)
        RecipeDocumentURLProtocol.stub = nil
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        RecipeDocumentURLProtocol.stub = nil
        super.tearDown()
    }

    func testLoadsAcceptedHTMLWithinByteLimit() async throws {
        RecipeDocumentURLProtocol.stub = .init(
            statusCode: 200,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            data: Data("<html>Recipe</html>".utf8)
        )

        let html = try await RecipeHTTPDocumentLoader.loadHTML(
            from: URL(string: "https://example.com/recipe")!,
            session: session,
            maximumBytes: 1_024
        )

        XCTAssertEqual(html, "<html>Recipe</html>")
    }

    func testRejectsNonSuccessStatus() async {
        RecipeDocumentURLProtocol.stub = .init(
            statusCode: 404,
            headers: ["Content-Type": "text/html"],
            data: Data("missing".utf8)
        )

        await assertLoaderError(.unacceptableStatus(404)) {
            try await RecipeHTTPDocumentLoader.loadHTML(
                from: URL(string: "https://example.com/missing")!,
                session: session
            )
        }
    }

    func testRejectsNonHTMLContentType() async {
        RecipeDocumentURLProtocol.stub = .init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: Data("{}".utf8)
        )

        await assertLoaderError(.unsupportedContentType("application/json")) {
            try await RecipeHTTPDocumentLoader.loadHTML(
                from: URL(string: "https://example.com/api")!,
                session: session
            )
        }
    }

    func testRejectsDeclaredOversizedResponseBeforeReadingBody() async {
        RecipeDocumentURLProtocol.stub = .init(
            statusCode: 200,
            headers: [
                "Content-Type": "text/html",
                "Content-Length": "100"
            ],
            data: Data("short".utf8)
        )

        await assertLoaderError(.responseTooLarge(maximumBytes: 8)) {
            try await RecipeHTTPDocumentLoader.loadHTML(
                from: URL(string: "https://example.com/large")!,
                session: session,
                maximumBytes: 8
            )
        }
    }

    func testRejectsChunkedBodyThatCrossesByteLimit() async {
        RecipeDocumentURLProtocol.stub = .init(
            statusCode: 200,
            headers: ["Content-Type": "text/html"],
            data: Data("12345".utf8)
        )

        await assertLoaderError(.responseTooLarge(maximumBytes: 4)) {
            try await RecipeHTTPDocumentLoader.loadHTML(
                from: URL(string: "https://example.com/chunked")!,
                session: session,
                maximumBytes: 4
            )
        }
    }

    func testDecodesISO8859Content() async throws {
        RecipeDocumentURLProtocol.stub = .init(
            statusCode: 200,
            headers: ["Content-Type": "text/html; charset=iso-8859-1"],
            data: Data([0x63, 0x61, 0x66, 0xE9])
        )

        let html = try await RecipeHTTPDocumentLoader.loadHTML(
            from: URL(string: "https://example.com/latin")!,
            session: session
        )

        XCTAssertEqual(html, "café")
    }

    func testCancellationPropagatesAsCancellationError() async {
        RecipeDocumentURLProtocol.stub = .init(
            statusCode: 200,
            headers: ["Content-Type": "text/html"],
            data: Data("<html>late</html>".utf8),
            delay: 2
        )

        let task = Task {
            try await RecipeHTTPDocumentLoader.loadHTML(
                from: URL(string: "https://example.com/slow")!,
                session: session
            )
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    private func assertLoaderError(
        _ expected: RecipeHTTPDocumentLoader.LoaderError,
        operation: () async throws -> String
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as RecipeHTTPDocumentLoader.LoaderError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Expected loader error, got \(error)")
        }
    }
}

private final class RecipeDocumentURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let data: Data
        var delay: TimeInterval = 0
    }

    static var stub: Stub?
    private var pendingWork: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.stub, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        pendingWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay, execute: work)
    }

    override func stopLoading() {
        pendingWork?.cancel()
        pendingWork = nil
    }
}
