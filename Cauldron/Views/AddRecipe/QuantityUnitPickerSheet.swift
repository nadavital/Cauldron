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
    let moreUnits: [MeasurementUnit] = [.pieces, .pinch, .dash]
    @State private var customUnit: String = ""
    @State private var isCustomSelected: Bool = false
    
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quantity")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    TextField("Enter quantity", text: $quantityInput)
                        .keyboardType(.decimalPad)
                        .focused($quantityFocus)
                        .font(.title2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Quick fraction buttons - make them smaller and more compact
                HStack(spacing: 8) {
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
                                .font(.subheadline.weight(.medium))
                                .frame(width: 32, height: 32)
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
                .padding(.bottom, 16)
                
                Divider()
                    .padding(.bottom, 12)
                
                // Unit section with integrated category selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unit")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    // Category selector - make it more compact
                    Picker("Unit Category", selection: $selectedCategoryIndex) {
                        Text("Volume").tag(0)
                        Text("Weight").tag(1)
                        Text("More").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    // Units grid - include Custom button in More category
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 100))], spacing: 8) {
                        ForEach(selectedCategory, id: \.self) { unitOption in
                            Button {
                                unit = unitOption
                                isCustomSelected = false
                                // Clear custom unit when selecting a predefined unit
                                if unitOption != .none {
                                    customUnit = ""
                                }
                            } label: {
                                Text(unitOption.displayName(for: Double(quantityInput) ?? 0))
                                    .font(.subheadline)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(unit == unitOption && !isCustomSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(unit == unitOption && !isCustomSelected ? .accentColor : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Add Custom button only in More category
                        if selectedCategoryIndex == 2 {
                            Button {
                                isCustomSelected = true
                                unit = .none
                            } label: {
                                Text("Custom")
                                    .font(.subheadline)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isCustomSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                                    )
                                    .foregroundColor(isCustomSelected ? .accentColor : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    
                    // Custom unit text field - only show when Custom is selected
                    if selectedCategoryIndex == 2 && isCustomSelected {
                        VStack(spacing: 8) {
                            TextField("Enter custom unit", text: $customUnit)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .padding(.horizontal)
                        }
                        .padding(.top, 8)
                    }
                }
                
                Spacer(minLength: 16)
                
                // Preview of selection - make it more subtle
                HStack {
                    Spacer()
                    
                    let displayUnit = isCustomSelected && !customUnit.isEmpty ? customUnit : unit.displayName(for: Double(quantityInput) ?? 0)
                    Text("\(quantityInput) \(displayUnit)")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.1))
                        )
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
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
                        // Keep fractions as fractions for better UX
                        var finalQuantity = quantityInput
                        
                        if !quantityInput.isEmpty {
                            // Convert common text fractions to unicode fractions
                            if quantityInput == "1/4" {
                                finalQuantity = "¼"
                            } else if quantityInput == "1/3" {
                                finalQuantity = "⅓"
                            } else if quantityInput == "1/2" {
                                finalQuantity = "½"
                            } else if quantityInput == "2/3" {
                                finalQuantity = "⅔"
                            } else if quantityInput == "3/4" {
                                finalQuantity = "¾"
                            } else if quantityInput == "1/8" {
                                finalQuantity = "⅛"
                            } else if quantityInput == "3/8" {
                                finalQuantity = "⅜"
                            } else if quantityInput == "5/8" {
                                finalQuantity = "⅝"
                            } else if quantityInput == "7/8" {
                                finalQuantity = "⅞"
                            } else if quantityInput.contains(" ") && quantityInput.contains("/") {
                                // Handle mixed numbers with text fractions (e.g., "2 1/4")
                                let parts = quantityInput.split(separator: " ")
                                if parts.count == 2, let whole = Int(parts[0]), parts[1].contains("/") {
                                    let fraction = String(parts[1])
                                    let unicodeFraction: String
                                    switch fraction {
                                    case "1/4": unicodeFraction = "¼"
                                    case "1/3": unicodeFraction = "⅓"
                                    case "1/2": unicodeFraction = "½"
                                    case "2/3": unicodeFraction = "⅔"
                                    case "3/4": unicodeFraction = "¾"
                                    case "1/8": unicodeFraction = "⅛"
                                    case "3/8": unicodeFraction = "⅜"
                                    case "5/8": unicodeFraction = "⅝"
                                    case "7/8": unicodeFraction = "⅞"
                                    default: unicodeFraction = fraction
                                    }
                                    finalQuantity = "\(whole) \(unicodeFraction)"
                                }
                            }
                            // If it's already a unicode fraction, decimal, or other format, keep it as is
                        }
                        
                        quantity = finalQuantity
                        
                        // Save custom unit to UserDefaults and pass it to callback
                        var customUnitName: String? = nil
                        if isCustomSelected && !customUnit.isEmpty {
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
                
                // Load custom unit if it exists and set states accordingly
                if unit == .none {
                    let key = "customUnit_\(ingredientId.uuidString)"
                    if let loadedCustomUnit = UserDefaults.standard.string(forKey: key), !loadedCustomUnit.isEmpty {
                        customUnit = loadedCustomUnit
                        isCustomSelected = true
                    }
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
        .presentationDetents([.medium, .large])
    }
} 