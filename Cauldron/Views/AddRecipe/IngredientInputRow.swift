import SwiftUI

struct IngredientInputRow: View {
    @Binding var name: String
    @Binding var quantityString: String
    @Binding var unit: MeasurementUnit
    @Binding var isFocused: Bool
    
    @State private var isQuantityEditing = false
    @State private var showQuantityUnitPicker = false
    @FocusState private var localFocus: Bool
    
    // For integrated quantity and unit picker
    @State private var tempQuantity: String
    @State private var tempUnit: MeasurementUnit
    
    // Add ingredient ID for custom unit persistence
    let ingredientId: UUID
    
    // Initialize state with current values
    init(name: Binding<String>, quantityString: Binding<String>, unit: Binding<MeasurementUnit>, isFocused: Binding<Bool>, ingredientId: UUID) {
        self._name = name
        self._quantityString = quantityString
        self._unit = unit
        self._isFocused = isFocused
        self.ingredientId = ingredientId
        
        // Initialize temp state for picker
        self._tempQuantity = State(initialValue: quantityString.wrappedValue)
        self._tempUnit = State(initialValue: unit.wrappedValue)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Ingredient name - give it most of the space
                TextField("Ingredient name", text: $name)
                    .font(.body)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .focused($localFocus)
                    .textFieldStyle(PlainTextFieldStyle())
                    .submitLabel(.done)
                    .onChange(of: localFocus) { 
                        // Add safety check to prevent updating the binding after view disposal
                        DispatchQueue.main.async {
                            // Only update if we're still in the view hierarchy
                            if !name.isEmpty || !quantityString.isEmpty {
                                isFocused = localFocus
                            }
                        }
                    }
                
                Spacer()
                
                // Quantity and unit button
                Button {
                    localFocus = false // Unfocus the name field
                    // Update temp values with current values
                    tempQuantity = quantityString.isEmpty ? "1" : quantityString
                    tempUnit = unit
                    showQuantityUnitPicker = true
                } label: {
                    Text(quantityDisplay)
                        .foregroundColor(quantityString.isEmpty ? .secondary : .primary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                }
                .sheet(isPresented: $showQuantityUnitPicker, onDismiss: {
                    // Ensure we update the binding values on dismiss
                    if !tempQuantity.isEmpty {
                        quantityString = tempQuantity
                        unit = tempUnit
                    }
                }) {
                    QuantityUnitPickerSheet(
                        quantity: $tempQuantity,
                        unit: $tempUnit,
                        onSave: { newQuantity, newUnit, customUnitName in
                            quantityString = newQuantity
                            unit = newUnit
                            // Custom unit is already saved to UserDefaults by the picker sheet
                        },
                        ingredientId: ingredientId
                    )
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            
            Divider()
                .padding(.leading, 60)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .onChange(of: name) { 
            // Use the same safety check pattern
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
    
    private var quantityDisplay: String {
        if quantityString.isEmpty {
            return "Add quantity"
        } else {
            // Use the displayName method to properly format
            return "\(quantityString) \(unit.displayName(for: Double(quantityString) ?? 0))"
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var name = "Flour"
        @State var qty = "2"
        @State var unit = MeasurementUnit.cups
        @State var focused = false
        
        var body: some View {
            VStack(spacing: 16) {
                IngredientInputRow(name: $name, quantityString: $qty, unit: $unit, isFocused: $focused, ingredientId: UUID())
                
                IngredientInputRow(name: .constant(""), quantityString: .constant(""), unit: .constant(.cups), isFocused: .constant(false), ingredientId: UUID())
                
                IngredientInputRow(name: .constant("Sugar"), quantityString: .constant(""), unit: .constant(.tbsp), isFocused: .constant(false), ingredientId: UUID())
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }
    
    return PreviewWrapper()
}
