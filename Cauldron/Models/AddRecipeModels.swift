import Foundation
import SwiftUI

// Helper struct for dynamic ingredient inputs
struct IngredientInput: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var quantityString: String
    var unit: MeasurementUnit
    var isPlaceholder: Bool = false
    var isFocused: Bool = false
}

// Helper struct for dynamic instruction inputs
struct StringInput: Identifiable, Equatable {
    var id: UUID = UUID()
    var value: String
    var isPlaceholder: Bool = false
    var isFocused: Bool = false
}

// Array move extension used for drag-and-drop reordering
extension Array {
    mutating func move(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex, indices.contains(fromIndex), indices.contains(toIndex) else { return }
        let element = remove(at: fromIndex)
        insert(element, at: toIndex)
    }
}