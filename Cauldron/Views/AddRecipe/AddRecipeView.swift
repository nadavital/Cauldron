import SwiftUI
import PhotosUI
import UIKit

struct AddRecipeView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var recipes: [Recipe]
    var recipeToEdit: Recipe?
    
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var firestoreManager = FirestoreManager()

    // Recipe properties
    @State private var name: String = ""
    @State private var prepTime: String = ""
    @State private var cookTime: String = ""
    @State private var servings: String = ""
    @State private var description: String = ""

    // Image picker related states
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil

    // Tags
    @State private var selectedTagIDs: Set<String> = []

    // Dynamic lists
    @State private var ingredients: [IngredientInput] = []
    @State private var instructions: [StringInput] = []

    // Edit mode states
    @State private var isIngredientsEditMode = false
    @State private var isInstructionsEditMode = false

    // Timer for cleanup
    @State private var cleanupTimer: Timer? = nil

    @State private var draggedIngredient: IngredientInput?
    @State private var draggedInstruction: StringInput?

    // Focus states for keyboard dismissal
    @FocusState private var isDescriptionFocused: Bool
    @State private var focusedInstructionID: UUID?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                // Image with title overlaid on top (z-axis)
                ZStack(alignment: .top) {
                    // Header image at the bottom of the stack
                    ImageHeaderView(name: $name,
                                   selectedPhoto: $selectedPhoto,
                                   selectedImageData: $selectedImageData)
                        .frame(width: geometry.size.width, height: 450)
                        .clipped()
                        
                    // Photo picker button positioned at top-right
                    VStack {
                        HStack {
                            Spacer()
                            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                                Image(systemName: selectedImageData != nil ? "photo.fill.on.rectangle.fill" : "plus.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(selectedImageData != nil ? .white : .accentColor)
                                    .padding(10)
                                    .background(
                                        Circle()
                                            .fill(selectedImageData != nil ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                                    )
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 16)
                        }
                        Spacer()
                    }
                    .onChange(of: selectedPhoto) { 
                        Task {
                            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                                // Compress the image immediately for better UX
                                selectedImageData = compressImageForDisplay(data)
                            }
                        }
                    }
                    
                    // Title text field overlaid on image
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            if name.isEmpty {
                                Text("Recipe Name")
                                    .font(.largeTitle.bold())
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            TextField("", text: $name)
                                .font(.largeTitle.bold())
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .frame(height: 450)
                .ignoresSafeArea(edges: .top)

                VStack(spacing: 20) {
                    RecipeInputCard(title: "Description", systemImage: "text.alignleft") {
                        AnyView(
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $description)
                                    .frame(maxWidth: .infinity, minHeight: 100)
                                    .focused($isDescriptionFocused)
                                    .scrollContentBackground(.hidden)
                                
                                // Placeholder text
                                if description.isEmpty {
                                    Text("Add a description...")
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.separator), lineWidth: 0.5)
                            )
                        )
                    }
                    TimingServingsView(prepTime: $prepTime,
                                       cookTime: $cookTime,
                                       servings: $servings)

                    TagsSelectionView(selectedTagIDs: $selectedTagIDs)

                    IngredientsSection(ingredients: $ingredients,
                                       isEditMode: $isIngredientsEditMode,
                                       draggedIngredient: $draggedIngredient,
                                       cleanupEmptyRows: cleanupEmptyRows,
                                       scheduleCleanup: scheduleCleanup,
                                       checkAndAddPlaceholder: checkAndAddIngredientPlaceholder,
                                       startDrag: startDragIngredient)

                    InstructionsSection(instructions: $instructions,
                                        isEditMode: $isInstructionsEditMode,
                                        draggedInstruction: $draggedInstruction,
                                        focusedIndex: $focusedInstructionID,
                                        cleanupEmptyRows: cleanupEmptyRows,
                                        scheduleCleanup: scheduleCleanup,
                                        checkAndAddPlaceholder: checkAndAddInstructionPlaceholder,
                                        startDrag: startDragInstruction)

                    SaveButtonView(action: {
                        cleanupEmptyRows()
                        Task {
                            await saveRecipe()
                        }
                    })
                }
                .padding()
                .frame(width: geometry.size.width)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarItems(leading: Button("Cancel") { dismiss() })
        .navigationTitle(recipeToEdit == nil ? "New Recipe" : "Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setupInitialData() }
        .onDisappear { cleanupTimer?.invalidate() }
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            hideKeyboard()
        }
        .safeAreaInset(edge: .bottom) {
            // Floating Done button when any field is focused
            if isDescriptionFocused || focusedInstructionID != nil {
                HStack {
                    Spacer()
                    Button("Done") {
                        hideKeyboard()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(25)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .background(Color.clear)
            }
        }
    }

    // MARK: - Helper Methods
    
    /// Compress image for display and storage
    private func compressImageForDisplay(_ imageData: Data) -> Data? {
        guard let uiImage = UIImage(data: imageData) else { return imageData }
        
        // More aggressive compression for Firestore compatibility
        // Target ~650KB to account for base64 encoding overhead
        let maxFileSize = 650_000
        let maxDimensions: [CGFloat] = [600, 500, 400, 300]
        
        for maxDimension in maxDimensions {
            let resizedImage = resizeImageForDisplay(uiImage, maxDimension: maxDimension)
            
            // Try progressively lower quality
            let qualities: [CGFloat] = [0.7, 0.5, 0.3, 0.2]
            
            for quality in qualities {
                if let compressedData = resizedImage.jpegData(compressionQuality: quality),
                   compressedData.count <= maxFileSize {
                    print("Display image compressed from \(imageData.count) bytes to \(compressedData.count) bytes at \(maxDimension)px")
                    return compressedData
                }
            }
        }
        
        print("Using original image data - may require further compression when saving")
        return imageData
    }
    
    /// Resize image while maintaining aspect ratio
    private func resizeImageForDisplay(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        
        if scale >= 1.0 { return image }
        
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // Schedule a delayed cleanup to remove empty rows
    private func scheduleCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            cleanupEmptyRows()
        }
    }

    // Remove any empty input rows, ensuring at least one placeholder at end
    private func cleanupEmptyRows() {
        withAnimation {
            // Ingredients
            if ingredients.count > 1 {
                var nonEmpty = [IngredientInput]()
                var empties = [IngredientInput]()
                for ing in ingredients {
                    if ing.isFocused || !ing.name.isEmpty || !ing.quantityString.isEmpty {
                        nonEmpty.append(ing)
                    } else {
                        empties.append(ing)
                    }
                }
                if empties.isEmpty {
                    nonEmpty.append(IngredientInput(name: "", quantityString: "", unit: .cups))
                } else {
                    nonEmpty.append(empties.first!)
                }
                ingredients = nonEmpty
            }
            // Instructions
            if instructions.count > 1 {
                var nonEmpty = [StringInput]()
                var empties = [StringInput]()
                for inst in instructions {
                    if inst.isFocused || !inst.value.isEmpty {
                        nonEmpty.append(inst)
                    } else {
                        empties.append(inst)
                    }
                }
                if empties.isEmpty {
                    nonEmpty.append(StringInput(value: ""))
                } else {
                    nonEmpty.append(empties.first!)
                }
                instructions = nonEmpty
            }
        }
    }

    private func checkAndAddIngredientPlaceholder() {
        let hasEmpty = ingredients.contains { $0.name.isEmpty && !$0.isPlaceholder }
        if !hasEmpty {
            withAnimation {
                ingredients.append(IngredientInput(name: "", quantityString: "", unit: .cups))
            }
        }
    }

    private func checkAndAddInstructionPlaceholder() {
        let hasEmpty = instructions.contains { $0.value.isEmpty && !$0.isPlaceholder }
        if !hasEmpty {
            withAnimation {
                instructions.append(StringInput(value: "", isPlaceholder: false))
            }
        }
    }

    private func startDragIngredient(item: IngredientInput) {
        print("Starting drag for ingredient: \(item.name)")
        draggedIngredient = item
    }

    private func startDragInstruction(item: StringInput) {
        draggedInstruction = item
    }

    private func setupInitialData() {
        if recipeToEdit == nil {
            ingredients = [IngredientInput(name: "", quantityString: "", unit: .cups)]
            instructions = [StringInput(value: "", isPlaceholder: false)]
            description = ""
        } else if let recipe = recipeToEdit {
            name = recipe.name
            prepTime = "\(recipe.prepTime)"
            cookTime = "\(recipe.cookTime)"
            servings = "\(recipe.servings)"
            selectedImageData = recipe.imageData
            selectedTagIDs = recipe.tags
            ingredients = recipe.ingredients.map {
                // Convert decimal back to fraction for better UX
                let quantityDisplay = decimalToFraction($0.quantity)
                
                // Save custom unit name to UserDefaults if it exists
                if let customUnit = $0.customUnitName, !customUnit.isEmpty {
                    let key = "customUnit_\($0.id.uuidString)"
                    UserDefaults.standard.set(customUnit, forKey: key)
                }
                
                return IngredientInput(id: $0.id, name: $0.name, quantityString: quantityDisplay, unit: $0.unit)
            } + [IngredientInput(name: "", quantityString: "", unit: .cups)]
            instructions = recipe.instructions.map { StringInput(value: $0) } + [StringInput(value: "", isPlaceholder: false)]
            description = recipe.description
        }
    }
    
    // Helper function to convert decimal to fraction for display
    private func decimalToFraction(_ decimal: Double) -> String {
        // Handle whole numbers
        if decimal.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(decimal))"
        }
        
        let whole = Int(decimal)
        let fractionalPart = decimal - Double(whole)
        
        // Check for common fractions with some tolerance
        let epsilon = 0.001
        let commonFractions: [(Double, String)] = [
            (0.125, "⅛"), (0.25, "¼"), (1.0/3.0, "⅓"), (0.375, "⅜"),
            (0.5, "½"), (0.625, "⅝"), (2.0/3.0, "⅔"), (0.75, "¾"), (0.875, "⅞")
        ]
        
        // Check if the fractional part matches a common fraction
        for (value, fraction) in commonFractions {
            if abs(fractionalPart - value) < epsilon {
                if whole > 0 {
                    return "\(whole) \(fraction)"
                } else {
                    return fraction
                }
            }
        }
        
        // Try to find a simple fraction representation
        let denominators = [2, 3, 4, 5, 6, 8, 16]
        for denom in denominators {
            let numerator = round(fractionalPart * Double(denom))
            if abs(fractionalPart - numerator / Double(denom)) < epsilon {
                let num = Int(numerator)
                if num > 0 && num < denom {
                    if whole > 0 {
                        return "\(whole) \(num)/\(denom)"
                    } else {
                        return "\(num)/\(denom)"
                    }
                }
            }
        }
        
        // Fallback to decimal with reasonable precision
        if whole > 0 {
            return String(format: "%.3f", decimal).trimmingCharacters(in: CharacterSet(charactersIn: "0")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        } else {
            return String(format: "%.3f", decimal)
        }
    }

    private func saveRecipe() async {
        let p = Int(prepTime) ?? 0
        let c = Int(cookTime) ?? 0
        let s = Int(servings) ?? 1
        let newIngs = ingredients.compactMap { inp -> Ingredient? in
            guard !inp.isPlaceholder && !inp.name.isEmpty else { return nil }
            
            // parse quantities including fractions...
            var qty: Double = 0
            let str = inp.quantityString
            
            if str.isEmpty { 
                qty = 1 
            } else if str.contains("¼") || str.contains("⅓") || str.contains("½") || str.contains("⅔") || str.contains("¾") {
                // Handle unicode fractions
                if str.contains(" ") {
                    // Mixed number with unicode fraction (e.g. "1 ½")
                    let parts = str.split(separator: " ")
                    if parts.count == 2, let whole = Double(parts[0]) {
                        let fraction = String(parts[1])
                        if fraction == "¼" {
                            qty = whole + 0.25
                        } else if fraction == "⅓" {
                            qty = whole + 1.0/3.0
                        } else if fraction == "½" {
                            qty = whole + 0.5
                        } else if fraction == "⅔" {
                            qty = whole + 2.0/3.0
                        } else if fraction == "¾" {
                            qty = whole + 0.75
                        } else if fraction == "⅛" {
                            qty = whole + 0.125
                        } else if fraction == "⅜" {
                            qty = whole + 0.375
                        } else if fraction == "⅝" {
                            qty = whole + 0.625
                        } else if fraction == "⅞" {
                            qty = whole + 0.875
                        } else {
                            qty = whole
                        }
                    }
                } else {
                    // Just a unicode fraction
                    if str == "¼" {
                        qty = 0.25
                    } else if str == "⅓" {
                        qty = 1.0/3.0
                    } else if str == "½" {
                        qty = 0.5
                    } else if str == "⅔" {
                        qty = 2.0/3.0
                    } else if str == "¾" {
                        qty = 0.75
                    } else if str == "⅛" {
                        qty = 0.125
                    } else if str == "⅜" {
                        qty = 0.375
                    } else if str == "⅝" {
                        qty = 0.625
                    } else if str == "⅞" {
                        qty = 0.875
                    }
                }
            } else if str.contains("/") {
                // Handle text fractions (e.g. "1/2" or "1 1/2")
                let parts = str.split(separator: " ")
                if parts.count == 2, let w = Double(parts[0]), parts[1].contains("/") {
                    let f = parts[1].split(separator: "/").compactMap { Double($0) }
                    if f.count == 2 { qty = w + f[0]/f[1] }
                } else {
                    let f = str.split(separator: "/").compactMap { Double($0) }
                    if f.count == 2 { qty = f[0]/f[1] }
                }
            } else { 
                qty = Double(str) ?? 0 
            }
            
            // Check for custom unit name in UserDefaults (set by QuantityUnitPickerSheet)
            var customUnitName: String? = nil
            if inp.unit == .none {
                // Get the custom unit name for this ingredient
                let key = "customUnit_\(inp.id.uuidString)"
                customUnitName = UserDefaults.standard.string(forKey: key)
            }
            
            return Ingredient(name: inp.name, quantity: qty, unit: inp.unit, customUnitName: customUnitName)
        }
        let newInst = instructions.filter { !$0.isPlaceholder && !$0.value.isEmpty }.map { $0.value }
        let recipe = Recipe(id: recipeToEdit?.id ?? UUID(), name: name, ingredients: newIngs, instructions: newInst, prepTime: p, cookTime: c, servings: s, imageData: selectedImageData, tags: selectedTagIDs, description: description)
        
        do {
            // Save to Firebase
            try await firestoreManager.saveRecipe(recipe)
            
            // Update local array
            await MainActor.run {
                if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
                    recipes[idx] = recipe
                } else {
                    recipes.append(recipe)
                }
                
                // Dismiss the view
                dismiss()
            }
        } catch {
            print("Error saving recipe: \(error)")
            
            // Check if it's an image size error and provide specific feedback
            let errorDescription = error.localizedDescription
            if errorDescription.contains("longer than") && errorDescription.contains("bytes") {
                print("Image still too large after compression. Consider removing the image or using a smaller one.")
                // Still save without image as fallback
                var recipeWithoutImage = recipe
                recipeWithoutImage.imageData = nil
                
                do {
                    try await firestoreManager.saveRecipe(recipeWithoutImage)
                    await MainActor.run {
                        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
                            recipes[idx] = recipeWithoutImage
                        } else {
                            recipes.append(recipeWithoutImage)
                        }
                        print("Recipe saved without image due to size constraints")
                        dismiss()
                    }
                } catch {
                    print("Failed to save recipe even without image: \(error)")
                    // Still update local array as final fallback
                    await MainActor.run {
                        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
                            recipes[idx] = recipe
                        } else {
                            recipes.append(recipe)
                        }
                        dismiss()
                    }
                }
            } else {
                // Other error - still update local array as fallback
                await MainActor.run {
                    if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
                        recipes[idx] = recipe
                    } else {
                        recipes.append(recipe)
                    }
                    dismiss()
                }
            }
        }
    }

    private func hideKeyboard() {
        isDescriptionFocused = false
        focusedInstructionID = nil
    }
}

#Preview {
    AddRecipeView(recipes: .constant([Recipe(id: UUID(), name: "Sample Recipe", ingredients: [Ingredient(name: "Ingredient 1", quantity: 1.5, unit: .cups)], instructions: ["Instruction 1"], prepTime: 10, cookTime: 20, servings: 4, imageData: nil, tags: [], description: "A sample recipe description.")]), recipeToEdit: nil)
}
