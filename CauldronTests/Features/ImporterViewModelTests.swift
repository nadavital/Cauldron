//
//  ImporterViewModelTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
import SwiftData
import UIKit
@testable import Cauldron

/// Tests for ImporterViewModel
/// Note: ViewModels are created as local variables to avoid @Observable + @MainActor
/// deinitialization issues during test teardown (Swift issue #85221)
@MainActor
final class ImporterViewModelTests: XCTestCase {

    // Helper to create fresh ViewModel for each test
    private func makeViewModel() -> (ImporterViewModel, DependencyContainer) {
        let dependencies = DependencyContainer.preview()
        let viewModel = ImporterViewModel(dependencies: dependencies)
        return (viewModel, dependencies)
    }

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    // MARK: - Initial State Tests

    func testInitialState_URLMode() async {
        let (viewModel, _) = makeViewModel()

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

    func testCanImport_URL_EmptyString_ReturnsFalse() async {
        let (viewModel, _) = makeViewModel()

        // Given
        viewModel.importType = .url
        viewModel.urlString = ""

        // Then
        XCTAssertFalse(viewModel.canImport)
    }

    func testCanImport_URL_WhitespaceOnly_ReturnsFalse() async {
        let (viewModel, _) = makeViewModel()

        // Given
        viewModel.importType = .url
        viewModel.urlString = "   "

        // Then
        XCTAssertFalse(viewModel.canImport)
    }

    func testCanImport_URL_ValidString_ReturnsTrue() async {
        let (viewModel, _) = makeViewModel()

        // Given
        viewModel.importType = .url
        viewModel.urlString = "https://youtube.com/watch?v=abc123"

        // Then
        XCTAssertTrue(viewModel.canImport)
    }

    func testCanImport_URL_WithoutScheme_ReturnsTrue() async {
        let (viewModel, _) = makeViewModel()

        viewModel.importType = .url
        viewModel.urlString = "allrecipes.com/recipe/12345"

        XCTAssertTrue(viewModel.canImport)
    }

    func testCanImport_Text_EmptyString_ReturnsFalse() async {
        let (viewModel, _) = makeViewModel()

        // Given
        viewModel.importType = .text
        viewModel.textInput = ""

        // Then
        XCTAssertFalse(viewModel.canImport)
    }

    func testCanImport_Text_ValidString_ReturnsTrue() async {
        let (viewModel, _) = makeViewModel()

        // Given
        viewModel.importType = .text
        viewModel.textInput = "Chocolate chip cookies recipe"

        // Then
        XCTAssertTrue(viewModel.canImport)
    }

    func testPreloadText_SetsTextImportModeAndTrimsInput() async {
        let (viewModel, _) = makeViewModel()

        viewModel.preloadText("  Tomato Soup\n\nIngredients:\nTomatoes\n  ")

        XCTAssertEqual(viewModel.importType, .text)
        XCTAssertEqual(viewModel.textInput, "Tomato Soup\n\nIngredients:\nTomatoes")
        XCTAssertTrue(viewModel.canImport)
    }

    func testPreloadText_IgnoresWhitespaceOnlyText() async {
        let (viewModel, _) = makeViewModel()

        viewModel.preloadText("    \n\t")

        XCTAssertEqual(viewModel.importType, .url)
        XCTAssertEqual(viewModel.textInput, "")
    }

    func testCanImport_Image_NoSelection_ReturnsFalse() async {
        let (viewModel, _) = makeViewModel()

        // Given
        viewModel.importType = .image
        viewModel.selectedOCRImage = nil

        // Then
        XCTAssertFalse(viewModel.canImport)
    }

    func testCanImport_Image_WithSelection_ReturnsTrue() async {
        let (viewModel, _) = makeViewModel()

        // Given
        viewModel.importType = .image
        viewModel.selectedOCRImage = makeTestImage()

        // Then
        XCTAssertTrue(viewModel.canImport)
    }

    // MARK: - URL Import Tests - Invalid URLs

    func testImportRecipe_TikTok_InvalidURL_ReturnsError() async {
        let (viewModel, _) = makeViewModel()

        // Given - Invalid TikTok URL (fake video ID)
        viewModel.importType = .url
        viewModel.urlString = "https://tiktok.com/@user/video/123456"

        // When
        await viewModel.importRecipe()

        // Then - Should fail (no recipe at fake URL)
        XCTAssertFalse(viewModel.isSuccess)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testImportRecipe_Instagram_InvalidURL_ReturnsError() async {
        let (viewModel, _) = makeViewModel()

        // Given - Invalid Instagram URL (fake post ID)
        viewModel.importType = .url
        viewModel.urlString = "https://instagram.com/p/abc123"

        // When
        await viewModel.importRecipe()

        // Then - Should fail (no recipe at fake URL)
        XCTAssertFalse(viewModel.isSuccess)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - State Management Tests

    func testImportRecipe_ResetsStateBeforeImport() async {
        let (viewModel, _) = makeViewModel()

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

    func testImportedRecipeSaveBuilderUsesCurrentUserOwner() {
        let sourceOwnerId = UUID()
        let currentUserId = UUID()
        let importedRecipe = Recipe(
            title: "Shared Import",
            ingredients: [],
            steps: [],
            ownerId: sourceOwnerId
        )

        let recipeForSave = ImportedRecipeSaveBuilder.recipeForSave(
            from: importedRecipe,
            userId: currentUserId
        )

        XCTAssertEqual(recipeForSave.ownerId, currentUserId)
    }

    func testImportedRecipeSaveBuilderDoesNotFallbackToSourceOwner() {
        let sourceOwnerId = UUID()
        let importedRecipe = Recipe(
            title: "Shared Import",
            ingredients: [],
            steps: [],
            ownerId: sourceOwnerId
        )

        let recipeForSave = ImportedRecipeSaveBuilder.recipeForSave(
            from: importedRecipe,
            userId: nil
        )

        XCTAssertNil(recipeForSave.ownerId)
    }

    func testImportedRecipeSaveBuilderClearsSourceCloudIdentity() {
        let importedRecipe = Recipe(
            title: "Cloudy Import",
            ingredients: [],
            steps: [],
            cloudRecordName: "source-private-record",
            cloudImageRecordName: "source-image-record",
            imageModifiedAt: Date()
        )

        let recipeForSave = ImportedRecipeSaveBuilder.recipeForSave(
            from: importedRecipe,
            userId: UUID()
        )

        XCTAssertNil(recipeForSave.cloudRecordName)
        XCTAssertNil(recipeForSave.cloudImageRecordName)
        XCTAssertNil(recipeForSave.imageModifiedAt)
    }

    func testImportedRecipeSaveBuilderClearsSourceCopyMetadata() {
        let sourceRecipeId = UUID()
        let importedRecipe = Recipe(
            title: "Copied Import",
            ingredients: [],
            steps: [],
            originalRecipeId: sourceRecipeId,
            originalCreatorId: UUID(),
            originalCreatorName: "Someone Else",
            savedAt: Date(),
            sourceRecipeUpdatedAt: Date(),
            followsSourceUpdates: true,
            relatedRecipeIds: [UUID()],
            isPreview: true
        )

        let recipeForSave = ImportedRecipeSaveBuilder.recipeForSave(
            from: importedRecipe,
            userId: UUID()
        )

        XCTAssertNil(recipeForSave.originalRecipeId)
        XCTAssertNil(recipeForSave.originalCreatorId)
        XCTAssertNil(recipeForSave.originalCreatorName)
        XCTAssertNil(recipeForSave.savedAt)
        XCTAssertNil(recipeForSave.sourceRecipeUpdatedAt)
        XCTAssertFalse(recipeForSave.followsSourceUpdates)
        XCTAssertEqual(recipeForSave.relatedRecipeIds, [])
        XCTAssertFalse(recipeForSave.isPreview)
    }
}
