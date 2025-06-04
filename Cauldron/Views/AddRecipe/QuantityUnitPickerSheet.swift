import SwiftUI

struct QuantityUnitPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var quantity: String
    @Binding var unit: MeasurementUnit
    var onSave: (String, MeasurementUnit, String?) -> Void
    var ingredientId: UUID // Add ingredient ID to save custom units
    
    // Group units by category for better organization
    let volumeUnits: [MeasurementUnit] = [.cups, .tbsp, .tsp, .ml, .liters]
    let weightUnits: [MeasurementUnit] = [.grams, .kg, .ounce, .pound, .mg]
    let moreUnits: [MeasurementUnit] = [.pieces, .pinch, .dash, .none]
    @State private var customUnit: String = ""
    
    // For segmenting the unit picker
    @State private var selectedCategoryIndex = 0
    @FocusState private var quantityFocus: Bool
    
    private var unitCategories: [[MeasurementUnit]] {
        [volumeUnits, weightUnits, moreUnits]
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
                        Text("More").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                    
                    // Units grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 120))], spacing: 12) {
                        ForEach(selectedCategory, id: \.self) { unitOption in
                            Button {
                                unit = unitOption
                                // Clear custom unit when selecting a predefined unit
                                if unitOption != .none {
                                    customUnit = ""
                                }
                            } label: {
                                Text(unitOption.displayName(for: Double(quantityInput) ?? 0))
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
                    
                    // Custom unit section - only show in More section
                    if selectedCategoryIndex == 2 {
                        // Custom unit input field
                        VStack {
                            TextField("Custom unit", text: $customUnit)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            
                            Button {
                                // Use custom unit
                                if !customUnit.isEmpty {
                                    unit = .none
                                }
                            } label: {
                                Text("Use Custom: \(customUnit)")
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(!customUnit.isEmpty && unit == .none ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(!customUnit.isEmpty ? .accentColor : .gray)
                            }
                            .disabled(customUnit.isEmpty)
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal)
                        }
                        .padding(.top, 8)
                    }
                }
                
                Spacer()
                
                // Preview of selection
                HStack {
                    Spacer()
                    
                    let displayUnit = unit == .none && !customUnit.isEmpty ? customUnit : unit.displayName(for: Double(quantityInput) ?? 0)
                    Text("\(quantityInput) \(displayUnit)")
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
                        // Fixed fraction handling logic
                        var finalQuantity = quantityInput
                        
                        if !quantityInput.isEmpty {
                            // Handle unicode fractions first
                            if quantityInput.contains("¼") || quantityInput.contains("⅓") || quantityInput.contains("½") || quantityInput.contains("⅔") || quantityInput.contains("¾") {
                                let parts = quantityInput.split(separator: " ")
                                if parts.count == 2, let whole = Double(parts[0]) {
                                    // Mixed number with fraction (e.g., "1 ½")
                                    let fraction = String(parts[1])
                                    var fractionValue: Double = 0
                                    switch fraction {
                                    case "¼": fractionValue = 0.25
                                    case "⅓": fractionValue = 1.0/3.0
                                    case "½": fractionValue = 0.5
                                    case "⅔": fractionValue = 2.0/3.0
                                    case "¾": fractionValue = 0.75
                                    case "⅛": fractionValue = 0.125
                                    case "⅜": fractionValue = 0.375
                                    case "⅝": fractionValue = 0.625
                                    case "⅞": fractionValue = 0.875
                                    default: fractionValue = 0
                                    }
                                    finalQuantity = "\(whole + fractionValue)"
                                } else if parts.count == 1 {
                                    // Just a unicode fraction
                                    let fraction = quantityInput
                                    switch fraction {
                                    case "¼": finalQuantity = "0.25"
                                    case "⅓": finalQuantity = "\(1.0/3.0)"
                                    case "½": finalQuantity = "0.5"
                                    case "⅔": finalQuantity = "\(2.0/3.0)"
                                    case "¾": finalQuantity = "0.75"
                                    case "⅛": finalQuantity = "0.125"
                                    case "⅜": finalQuantity = "0.375"
                                    case "⅝": finalQuantity = "0.625"
                                    case "⅞": finalQuantity = "0.875"
                                    default: break
                                    }
                                }
                            } else if quantityInput.contains("/") {
                                // Handle text fractions (e.g., "1/2" or "1 1/2")
                                let parts = quantityInput.split(separator: " ")
                                if parts.count == 2, let whole = Double(parts[0]), parts[1].contains("/") {
                                    // Mixed number with text fraction
                                    let fractionParts = parts[1].split(separator: "/")
                                    if fractionParts.count == 2, let num = Double(fractionParts[0]), let den = Double(fractionParts[1]), den != 0 {
                                        finalQuantity = "\(whole + num/den)"
                                    }
                                } else if parts.count == 1 && quantityInput.contains("/") {
                                    // Just a text fraction
                                    let fractionParts = quantityInput.split(separator: "/")
                                    if fractionParts.count == 2, let num = Double(fractionParts[0]), let den = Double(fractionParts[1]), den != 0 {
                                        finalQuantity = "\(num/den)"
                                    }
                                }
                            }
                            // If it's already a decimal or whole number, keep it as is
                        }
                        
                        quantity = finalQuantity
                        
                        // Save custom unit to UserDefaults and pass it to callback
                        var customUnitName: String? = nil
                        if unit == .none && !customUnit.isEmpty {
                            customUnitName = customUnit
                            // Save to UserDefaults for persistence
                            let key = "customUnit_\(ingredientId.uuidString)"
                            UserDefaults.standard.set(customUnit, forKey: key)
                        }
                        
                        onSave(quantity, unit, customUnitName)
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Initialize the input field with current quantity
                quantityInput = quantity
                
                // Load custom unit if it exists
                if unit == .none {
                    let key = "customUnit_\(ingredientId.uuidString)"
                    customUnit = UserDefaults.standard.string(forKey: key) ?? ""
                }
                
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