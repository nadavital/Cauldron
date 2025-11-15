//
//  ImporterViewModelTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
import SwiftData
@testable import Cauldron

@MainActor
final class ImporterViewModelTests: XCTestCase {

    var viewModel: ImporterViewModel!
    var dependencies: DependencyContainer!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        // Use the preview container (in-memory)
        dependencies = DependencyContainer.preview()
        viewModel = ImporterViewModel(dependencies: dependencies)
    }

    override func tearDown() async throws {
        viewModel = nil
        dependencies = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_URLMode() {
        // Then
        XCTAssertEqual(viewModel.importType, .url)
        XCTAssertEqual(viewModel.urlString, "")
        XCTAssertEqual(viewModel.textInput, "")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isSuccess)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.importedRecipe)
        XCTAssertNil(viewModel.sourceInfo)
    }

    func testCanImport_URL_EmptyString_ReturnsFalse() {
        // Given
        viewModel.importType = .url
        viewModel.urlString = ""

        // Then
        XCTAssertFalse(viewModel.canImport)
    }

    func testCanImport_URL_WhitespaceOnly_ReturnsFalse() {
        // Given
        viewModel.importType = .url
        viewModel.urlString = "   "

        // Then
        XCTAssertFalse(viewModel.canImport)
    }

    func testCanImport_URL_ValidString_ReturnsTrue() {
        // Given
        viewModel.importType = .url
        viewModel.urlString = "https://youtube.com/watch?v=abc123"

        // Then
        XCTAssertTrue(viewModel.canImport)
    }

    func testCanImport_Text_EmptyString_ReturnsFalse() {
        // Given
        viewModel.importType = .text
        viewModel.textInput = ""

        // Then
        XCTAssertFalse(viewModel.canImport)
    }

    func testCanImport_Text_ValidString_ReturnsTrue() {
        // Given
        viewModel.importType = .text
        viewModel.textInput = "Chocolate chip cookies recipe"

        // Then
        XCTAssertTrue(viewModel.canImport)
    }

    // MARK: - URL Import Tests - Unsupported Platforms

    func testImportRecipe_TikTok_ReturnsError() async {
        // Given
        viewModel.importType = .url
        viewModel.urlString = "https://tiktok.com/@user/video/123456"

        // When
        await viewModel.importRecipe()

        // Then
        XCTAssertFalse(viewModel.isSuccess)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("TikTok") ?? false)
    }

    func testImportRecipe_Instagram_ReturnsError() async {
        // Given
        viewModel.importType = .url
        viewModel.urlString = "https://instagram.com/p/abc123"

        // When
        await viewModel.importRecipe()

        // Then
        XCTAssertFalse(viewModel.isSuccess)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Instagram") ?? false)
    }

    // MARK: - State Management Tests

    func testImportRecipe_ResetsStateBeforeImport() async {
        // Given - Set some existing state
        viewModel.importType = .url
        viewModel.urlString = "https://instagram.com/p/abc123"
        viewModel.errorMessage = "Old error"
        viewModel.isSuccess = true
        viewModel.importedRecipe = Recipe(
            title: "Old Recipe",
            ingredients: [],
            steps: [],
            yields: ""
        )
        viewModel.sourceInfo = "Old source"

        // When - Import from unsupported platform
        await viewModel.importRecipe()

        // Then - Old state should be cleared (except error message)
        XCTAssertFalse(viewModel.isSuccess)
        XCTAssertNil(viewModel.importedRecipe)
        XCTAssertNil(viewModel.sourceInfo)
        // errorMessage will be set to new error
        XCTAssertNotEqual(viewModel.errorMessage, "Old error")
    }
}
