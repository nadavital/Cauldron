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
    
    // Initialize state with current values
    init(name: Binding<String>, quantityString: Binding<String>, unit: Binding<MeasurementUnit>, isFocused: Binding<Bool>) {
        self._name = name
        self._quantityString = quantityString
        self._unit = unit
        self._isFocused = isFocused
        
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
                        onSave: { newQuantity, newUnit in
                            // This is now redundant with onDismiss but keeping as a backup
                            quantityString = newQuantity
                            unit = newUnit
                        }
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

struct QuantityUnitPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var quantity: String
    @Binding var unit: MeasurementUnit
    var onSave: (String, MeasurementUnit) -> Void
    
    // Group units by category for better organization
    let volumeUnits: [MeasurementUnit] = [.cups, .tbsp, .tsp, .ml, .liters]
    let weightUnits: [MeasurementUnit] = [.grams, .kg, .ounce, .pound, .mg]
    let countUnits: [MeasurementUnit] = [.pieces, .pinch, .dash]
    
    // For segmenting the unit picker
    @State private var selectedCategoryIndex = 0
    @FocusState private var quantityFocus: Bool
    
    private var unitCategories: [[MeasurementUnit]] {
        [volumeUnits, weightUnits, countUnits]
    }
    private var selectedCategory: [MeasurementUnit] {
        unitCategories[selectedCategoryIndex]
    }
    
    // For quantity input
    @State private var quantityInput: String = ""
    
    // Common fractions for quick selection
    let fractions = ["¼", "⅓", "½", "⅔", "¾"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Simple, direct quantity input section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quantity")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    TextField("Enter whole number or decimal", text: $quantityInput)
                        .keyboardType(.decimalPad)
                        .focused($quantityFocus)
                        .font(.title3)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
                .padding(.top, 20)
                .padding(.bottom, 5)
                
                // Quick fraction buttons
                HStack(spacing: 10) {
                    ForEach(fractions, id: \.self) { fraction in
                        Button {
                            if let existingNumber = Double(quantityInput), existingNumber.truncatingRemainder(dividingBy: 1) == 0 {
                                // If we have a whole number, append the fraction
                                quantityInput = "\(Int(existingNumber)) \(fraction)"
                            } else {
                                // Otherwise just set it to the fraction
                                quantityInput = fraction
                            }
                        } label: {
                            Text(fraction)
                                .frame(minWidth: 40, minHeight: 40)
                                .background(
                                    Circle()
                                        .fill(quantityInput == fraction ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                                )
                                .foregroundColor(quantityInput == fraction ? .accentColor : .primary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                
                Divider()
                    .padding(.bottom, 15)
                
                // Unit section with integrated category selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unit")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    // Category selector right above units
                    Picker("Unit Category", selection: $selectedCategoryIndex) {
                        Text("Volume").tag(0)
                        Text("Weight").tag(1)
                        Text("Count").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                    
                    // Units grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 120))], spacing: 12) {
                        ForEach(selectedCategory, id: \.self) { unitOption in
                            Button {
                                unit = unitOption
                            } label: {
                                Text(unitOption.rawValue)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(unit == unitOption ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(unit == unitOption ? .accentColor : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Preview of selection
                HStack {
                    Spacer()
                    
                    Text("\(quantityInput) \(unit.displayName(for: Double(quantityInput) ?? 0))")
                        .font(.headline)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.1))
                        )
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .padding(.bottom, 20)
            .navigationTitle("Quantity & Unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Apply the quantity and unit
                        if !quantityInput.isEmpty {
                            quantity = quantityInput
                        }
                        onSave(quantity, unit)
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Initialize the input field with current quantity
                quantityInput = quantity
                
                // Set the initial category based on the current unit
                if volumeUnits.contains(unit) {
                    selectedCategoryIndex = 0
                } else if weightUnits.contains(unit) {
                    selectedCategoryIndex = 1
                } else {
                    selectedCategoryIndex = 2
                }
            }
        }
        .presentationDetents([.medium])
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
                IngredientInputRow(name: $name, quantityString: $qty, unit: $unit, isFocused: $focused)
                
                IngredientInputRow(name: .constant(""), quantityString: .constant(""), unit: .constant(.cups), isFocused: .constant(false))
                
                IngredientInputRow(name: .constant("Sugar"), quantityString: .constant(""), unit: .constant(.tbsp), isFocused: .constant(false))
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }
    
    return PreviewWrapper()
} 
