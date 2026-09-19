import SwiftUI
import UIKit
import XCTest
@testable import Cauldron

/// Visual smoke captures of real creation surfaces. No model generation or import
/// requests are sent; behavior regressions are covered by the view-model suites.
@MainActor
final class RecipeCreationAdaptiveRenderingTests: XCTestCase {
    func testCreationSurfacesResize() async throws {
        let dependencies = DependencyContainer.preview()
        try await capture(AIRecipeGeneratorView(dependencies: dependencies, screenshotPreview: true), name: "generation")
        try await capture(ImporterView(dependencies: dependencies), name: "import")
        try await capture(RecipeEditorView(dependencies: dependencies), name: "editor")
    }

    private func capture<Content: View>(_ content: Content, name: String) async throws {
        let traits = CookModeAdaptiveRenderingTests.Traits()
        let host = UIHostingController(rootView: CreationProbe(content: content, traits: traits))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for (suffix, size, horizontal, textSize) in [
            ("outer", CGSize(width: 466, height: 678), UserInterfaceSizeClass.compact, DynamicTypeSize.large),
            ("wide", CGSize(width: 951, height: 669), UserInterfaceSizeClass.regular, DynamicTypeSize.large),
            ("tall", CGSize(width: 669, height: 951), .regular, .large),
            ("narrow", CGSize(width: 320, height: 669), .compact, .large),
            ("accessibility", CGSize(width: 466, height: 678), .compact, .accessibility3)
        ] {
            traits.horizontal = horizontal
            traits.textSize = textSize
            window.frame.size = size
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            let screenshot = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "\(name)-\(suffix)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private struct CreationProbe<Content: View>: View {
        let content: Content
        let traits: CookModeAdaptiveRenderingTests.Traits
        var body: some View {
            content
                .environment(\.horizontalSizeClass, traits.horizontal)
                .environment(\.dynamicTypeSize, traits.textSize)
        }
    }
}
