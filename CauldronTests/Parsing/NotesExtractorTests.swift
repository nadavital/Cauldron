//
//  NotesExtractorTests.swift
//  CauldronTests
//
//  Tests for NotesExtractor utility
//

import XCTest
@testable import Cauldron

@MainActor
final class NotesExtractorTests: XCTestCase {

    // MARK: - Basic Notes Extraction

    func testExtractNotes_SimpleNotesSection() {
        let lines = [
            "Recipe Title",
            "Ingredients:",
            "Flour",
            "Instructions:",
            "Mix well",
            "Notes:",
            "Use fresh ingredients for best results"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertEqual(notes, "Use fresh ingredients for best results")
    }

    func testExtractNotes_TipsSection() {
        let lines = [
            "Recipe Title",
            "Ingredients:",
            "Flour",
            "Tips:",
            "Store in airtight container",
            "Can substitute with almond flour"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertNotNil(notes)
        XCTAssertTrue(notes!.contains("Store in airtight container"))
        XCTAssertTrue(notes!.contains("Can substitute with almond flour"))
    }

    func testExtractNotes_ChefsNotesSection() {
        let lines = [
            "Recipe Title",
            "Chef's Notes:",
            "This recipe was inspired by my grandmother"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertEqual(notes, "This recipe was inspired by my grandmother")
    }

    // MARK: - Multiple Notes Sections

    func testExtractNotes_MultipleSections() {
        let lines = [
            "Recipe Title",
            "Notes:",
            "Best served warm",
            "Tips:",
            "Use room temperature eggs"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertNotNil(notes)
        XCTAssertTrue(notes!.contains("Notes:"))
        XCTAssertTrue(notes!.contains("Best served warm"))
        XCTAssertTrue(notes!.contains("Tips:"))
        XCTAssertTrue(notes!.contains("Use room temperature eggs"))
    }

    // MARK: - Storage and Variations

    func testExtractNotes_StorageSection() {
        let lines = [
            "Recipe Title",
            "Storage:",
            "Refrigerate for up to 5 days",
            "Can be frozen for 3 months"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertNotNil(notes)
        XCTAssertTrue(notes!.contains("Refrigerate for up to 5 days"))
    }

    func testExtractNotes_VariationsSection() {
        let lines = [
            "Recipe Title",
            "Variations:",
            "Add chocolate chips for a sweeter version",
            "Use whole wheat flour for a healthier option"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertNotNil(notes)
        XCTAssertTrue(notes!.contains("Add chocolate chips"))
    }

    // MARK: - Edge Cases

    func testExtractNotes_NoNotesSection() {
        let lines = [
            "Recipe Title",
            "Ingredients:",
            "Flour",
            "Instructions:",
            "Mix well"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertNil(notes)
    }

    func testExtractNotes_EmptyNotesSection() {
        let lines = [
            "Recipe Title",
            "Notes:",
            "Instructions:",
            "Mix well"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertNil(notes)
    }

    func testExtractNotes_StopsAtOtherSectionHeader() {
        let lines = [
            "Recipe Title",
            "Notes:",
            "Important note here",
            "Ingredients:",  // Should stop here
            "Not a note"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertEqual(notes, "Important note here")
        XCTAssertFalse(notes?.contains("Not a note") ?? true)
    }

    // MARK: - Text Input

    func testExtractNotes_FromText() {
        let text = """
        Recipe Title

        Ingredients:
        Flour

        Notes:
        This is a helpful note
        """

        let notes = NotesExtractor.extractNotes(from: text)
        XCTAssertEqual(notes, "This is a helpful note")
    }

    // MARK: - Case Sensitivity

    func testExtractNotes_CaseInsensitiveHeaders() {
        let lines = [
            "Recipe Title",
            "NOTES:",
            "All caps note"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertEqual(notes, "All caps note")
    }

    // MARK: - Real-World Examples

    func testExtractNotes_RealWorldRecipe() {
        let lines = [
            "Chocolate Chip Cookies",
            "Ingredients:",
            "2 cups flour",
            "1 cup sugar",
            "Instructions:",
            "Mix and bake",
            "Notes:",
            "For chewier cookies, underbake by 2 minutes",
            "Storage:",
            "Store in airtight container for up to 1 week"
        ]

        let notes = NotesExtractor.extractNotes(from: lines)
        XCTAssertNotNil(notes)
        XCTAssertTrue(notes!.contains("chewier cookies"))
        XCTAssertTrue(notes!.contains("airtight container"))
    }
}
