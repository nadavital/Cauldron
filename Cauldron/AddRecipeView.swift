import SwiftUI
import PhotosUI

struct AddRecipeView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var recipes: [Recipe]
    var recipeToEdit: Recipe?

    // Recipe properties
    @State private var name: String = ""
    @State private var prepTime: String = ""
    @State private var cookTime: String = ""
    @State private var servings: String = ""
    
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
    
    // Helper structs for dynamic lists
    struct IngredientInput: Identifiable {
        var id = UUID()
        var name: String
        var quantityString: String
        var unit: MeasurementUnit
        var isPlaceholder: Bool = false
        var isFocused: Bool = false
    }

    struct StringInput: Identifiable {
        var id = UUID()
        var value: String
        var isPlaceholder: Bool = false
        var isFocused: Bool = false
    }
    
    // Add these below the existing properties at the top of the AddRecipeView struct
    @State private var draggedIngredient: IngredientInput?
    @State private var draggedInstruction: StringInput?
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 20) {
                    // Ensure content does not expand horizontally
                    // Recipe name and image section
                    ZStack(alignment: .bottom) {
                        // Image header (takes full width)
                        Group {
                            if let imageData = selectedImageData, let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 200)
                                    .clipped()
                                    .overlay(LinearGradient(
                                        colors: [.clear, .black.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                            } else {
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(height: 200)
                            }
                        }
                        
                        // Overlay at bottom for name input + image picker button
                        HStack {
                            // Recipe name field
                            TextField("Recipe Name", text: $name)
                                .font(.title.bold())
                                .foregroundColor(selectedImageData != nil ? .white : .primary)
                                .padding(.vertical, 8)
                            
                            Spacer()
                            
                            // Image picker button
                            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                                Image(systemName: selectedImageData != nil ? "photo.fill.on.rectangle.fill" : "plus.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(selectedImageData != nil ? .white : .accentColor)
                                    .padding(8)
                                    .background(Circle().fill(selectedImageData != nil ? .black.opacity(0.5) : .accentColor.opacity(0.1)))
                            }
                            .onChange(of: selectedPhoto) {
                                Task {
                                    if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                                        selectedImageData = data
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    
                    // Time and Servings
                    RecipeInputCard(title: "Timing & Servings", systemImage: "clock") {
                        TimeServingsInputRow(
                            prepTime: $prepTime,
                            cookTime: $cookTime,
                            servings: $servings
                        )
                    }
                    
                    // Tags
                    RecipeInputCard(title: "Tags", systemImage: "tag") {
                        TagSelectorField(label: "Recipe Tags", selectedTagIDs: $selectedTagIDs)
                    }
                    
                    // Ingredients
                    ingredientsSection
                    
                    // Instructions
                    instructionsSection
                    
                    // Save button
                    Button {
                        // Clean up before saving
                        cleanupEmptyRows()
                        saveRecipe()
                        // Ensure we properly dismiss after saving
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            dismiss()
                        }
                    } label: {
                        Text("Save Recipe")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.top, 20)
                }
                .padding() // Apply padding inside the constrained width
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
    }
    
    // MARK: - View Components
    
    // Ingredients section
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with action buttons
            HStack {
                Label("Ingredients", systemImage: "basket")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Edit/Done button
                Button(action: {
                    withAnimation {
                        isIngredientsEditMode.toggle()
                        cleanupEmptyRows()
                    }
                }) {
                    Text(isIngredientsEditMode ? "Done" : "Edit")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                        .foregroundColor(.accentColor)
                }
                
                // Add button (only visible when not in edit mode)
                if (!isIngredientsEditMode) {
                    Button(action: {
                        withAnimation {
                            // Add a new ingredient at the bottom before the placeholder
                            if let placeholderIndex = ingredients.firstIndex(where: { $0.isPlaceholder }) {
                                ingredients.insert(IngredientInput(name: "", quantityString: "", unit: .cups), at: placeholderIndex)
                                
                                // Set focus with slight delay to allow animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    ingredients[placeholderIndex].isFocused = true
                                }
                            } else {
                                // If no placeholder exists, add at the end
                                ingredients.append(IngredientInput(name: "", quantityString: "", unit: .cups))
                                let newIndex = ingredients.count - 1
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    ingredients[newIndex].isFocused = true
                                }
                            }
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                    }
                }
            }
            
            // Ingredients list with animation
            VStack(spacing: 10) {
                ForEach($ingredients) { $ingredient in
                    if isIngredientsEditMode {
                        HStack {
                            // Reorder handle
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.trailing, 2)
                                .onDrag {
                                    self.startDragIngredient(item: ingredient)
                                    return NSItemProvider()
                                }
                                .onDrop(of: [.text], delegate: IngredientDropDelegate(item: ingredient, ingredients: $ingredients, draggedItem: $draggedIngredient))
                            
                            IngredientInputRow(
                                name: $ingredient.name,
                                quantityString: $ingredient.quantityString,
                                unit: $ingredient.unit,
                                isFocused: $ingredient.isFocused
                            )
                            
                            // Delete button - only shown in edit mode
                            Button(action: {
                                withAnimation {
                                    ingredients.removeAll { $0.id == ingredient.id }
                                    cleanupEmptyRows() // Ensure placeholder logic is maintained
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title3)
                            }
                            .padding(.leading, 8)
                        }
                    } else {
                        IngredientInputRow(
                            name: $ingredient.name,
                            quantityString: $ingredient.quantityString,
                            unit: $ingredient.unit,
                            isFocused: $ingredient.isFocused
                        )
                        .onChange(of: ingredient.isFocused) { focused in
                            if focused {
                                DispatchQueue.main.async {
                                    checkAndAddIngredientPlaceholder()
                                    cleanupTimer?.invalidate()
                                }
                            } else {
                                scheduleCleanup()
                            }
                        }
                        .onChange(of: ingredient.name) { newName in
                            if ingredient.id == ingredients.last?.id && !newName.isEmpty {
                                DispatchQueue.main.async {
                                    withAnimation {
                                        ingredients.append(IngredientInput(name: "", quantityString: "", unit: .cups, isPlaceholder: false))
                                    }
                                }
                            }
                            if newName.isEmpty && ingredient.id != ingredients.last?.id {
                                scheduleCleanup()
                            }
                        }
                    }
                }
                .transition(.asymmetric(insertion: .scale, removal: .opacity))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true) // Prevent horizontal expansion
    }
    
    // Instructions section
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Instructions", systemImage: "list.number")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    withAnimation {
                        isInstructionsEditMode.toggle()
                        cleanupEmptyRows()
                    }
                }) {
                    Text(isInstructionsEditMode ? "Done" : "Edit")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
                        .foregroundColor(.accentColor)
                }
                if !isInstructionsEditMode {
                    Button(action: {
                        withAnimation {
                            if let placeholderIndex = instructions.firstIndex(where: { $0.isPlaceholder }) {
                                instructions.insert(StringInput(value: "", isPlaceholder: false), at: placeholderIndex)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    instructions[placeholderIndex].isFocused = true
                                }
                            } else {
                                instructions.append(StringInput(value: "", isPlaceholder: false))
                                let newIndex = instructions.count - 1
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    instructions[newIndex].isFocused = true
                                }
                            }
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                    }
                }
            }
            VStack(spacing: 10) {
                ForEach($instructions) { $instruction in
                    if isInstructionsEditMode {
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.trailing, 2)
                                .onDrag {
                                    self.startDragInstruction(item: instruction)
                                    return NSItemProvider()
                                }
                                .onDrop(of: [.text], delegate: InstructionDropDelegate(item: instruction, instructions: $instructions, draggedItem: $draggedInstruction))
                            InstructionInputRow(
                                instruction: $instruction.value,
                                stepNumber: (instructions.firstIndex(where: { $0.id == instruction.id }) ?? -1) + 1,
                                isFocused: $instruction.isFocused
                            )
                            Button(action: {
                                withAnimation {
                                    instructions.removeAll { $0.id == instruction.id }
                                    cleanupEmptyRows()
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title3)
                            }
                            .padding(.leading, 8)
                        }
                    } else {
                        InstructionInputRow(
                            instruction: $instruction.value,
                            stepNumber: (instructions.firstIndex(where: { $0.id == instruction.id }) ?? -1) + 1,
                            isFocused: $instruction.isFocused
                        )
                        .onChange(of: instruction.isFocused) { focused in
                            if focused {
                                DispatchQueue.main.async {
                                    checkAndAddInstructionPlaceholder()
                                    cleanupTimer?.invalidate()
                                }
                            } else {
                                scheduleCleanup()
                            }
                        }
                        .onChange(of: instruction.value) { newValue in
                            if instruction.id == instructions.last?.id && !newValue.isEmpty {
                                DispatchQueue.main.async {
                                    withAnimation {
                                        instructions.append(StringInput(value: "", isPlaceholder: false))
                                    }
                                }
                            }
                            if newValue.isEmpty && instruction.id != instructions.last?.id {
                                scheduleCleanup()
                            }
                        }
                    }
                }
                .transition(.asymmetric(insertion: .scale, removal: .opacity))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true) // Prevent horizontal expansion
    }
    
    // MARK: - Helper Methods
    
    private func scheduleCleanup() {
        // Cancel any existing timer
        cleanupTimer?.invalidate()
        
        // Create a new timer that fires after 0.5 seconds
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            cleanupEmptyRows()
        }
    }
    
    private func cleanupEmptyRows() {
        DispatchQueue.main.async {
            withAnimation {
                // Safely handle empty ingredients
                if ingredients.count > 1 {
                    // Create a new filtered array rather than removing in-place
                    var nonEmptyIngredients = [IngredientInput]()
                    var emptyIngredients = [IngredientInput]()
                    
                    // Sort ingredients: keep non-empty ones and the focused one
                    for ingredient in ingredients {
                        if ingredient.isFocused || !ingredient.name.isEmpty || !ingredient.quantityString.isEmpty {
                            nonEmptyIngredients.append(ingredient)
                        } else {
                            emptyIngredients.append(ingredient)
                        }
                    }
                    
                    // Keep at least one empty ingredient at the end
                    if emptyIngredients.isEmpty {
                        nonEmptyIngredients.append(IngredientInput(name: "", quantityString: "", unit: .cups))
                    } else {
                        nonEmptyIngredients.append(emptyIngredients.first!)
                    }
                    
                    ingredients = nonEmptyIngredients
                }
                
                // Safely handle empty instructions
                if instructions.count > 1 {
                    // Create a new filtered array rather than removing in-place
                    var nonEmptyInstructions = [StringInput]()
                    var emptyInstructions = [StringInput]()
                    
                    // Sort instructions: keep non-empty ones and the focused one
                    for instruction in instructions {
                        if instruction.isFocused || !instruction.value.isEmpty {
                            nonEmptyInstructions.append(instruction)
                        } else {
                            emptyInstructions.append(instruction)
                        }
                    }
                    
                    // Keep at least one empty instruction at the end
                    if emptyInstructions.isEmpty {
                        nonEmptyInstructions.append(StringInput(value: ""))
                    } else {
                        nonEmptyInstructions.append(emptyInstructions.first!)
                    }
                    
                    instructions = nonEmptyInstructions
                }
            }
        }
    }
    
    private func checkAndAddIngredientPlaceholder() {
        // Make sure we have at least one empty ingredient at the end
        let hasEmptyRow = ingredients.contains { $0.name.isEmpty && !$0.isPlaceholder }
        
        if !hasEmptyRow {
            withAnimation {
                ingredients.append(IngredientInput(name: "", quantityString: "", unit: .cups, isPlaceholder: false))
            }
        }
    }
    
    private func checkAndAddInstructionPlaceholder() {
        // Make sure we have at least one empty instruction at the end
        let hasEmptyRow = instructions.contains { $0.value.isEmpty && !$0.isPlaceholder }
        
        if !hasEmptyRow {
            withAnimation {
                instructions.append(StringInput(value: "", isPlaceholder: false))
            }
        }
    }
    
    private func deleteIngredient(at index: Int) {
        if index < ingredients.count {
            ingredients.remove(at: index)
            checkAndAddIngredientPlaceholder()
        }
    }
    
    private func deleteInstruction(at index: Int) {
        if index < instructions.count {
            instructions.remove(at: index)
            checkAndAddInstructionPlaceholder()
        }
    }
    
    private func setupInitialData() {
        // Initialize with at least one empty ingredient and instruction if not editing
        if recipeToEdit == nil {
            ingredients.append(IngredientInput(name: "", quantityString: "", unit: .cups, isPlaceholder: false))
            instructions.append(StringInput(value: "", isPlaceholder: false))
        }
        
        if let recipe = recipeToEdit {
            name = recipe.name
            prepTime = "\(recipe.prepTime)"
            cookTime = "\(recipe.cookTime)"
            servings = "\(recipe.servings)"
            selectedImageData = recipe.imageData
            selectedTagIDs = recipe.tags
            
            // Load ingredients
            ingredients = recipe.ingredients.map { 
                IngredientInput(
                    id: $0.id,
                    name: $0.name,
                    quantityString: "\($0.quantity)",
                    unit: $0.unit
                )
            }
            // Add an empty row for new ingredients
            ingredients.append(IngredientInput(name: "", quantityString: "", unit: .pieces, isPlaceholder: false))
            
            // Load instructions
            instructions = recipe.instructions.map { StringInput(id: UUID(), value: $0) }
            // Add an empty row for new instructions
            instructions.append(StringInput(value: "", isPlaceholder: false))
        }
    }
    
    private func startDragIngredient(item: IngredientInput) {
        self.draggedIngredient = item
    }
    
    private func startDragInstruction(item: StringInput) {
        self.draggedInstruction = item
    }
    
    // Add DropDelegate structs inside AddRecipeView
    struct IngredientDropDelegate: DropDelegate {
        let item: IngredientInput
        @Binding var ingredients: [IngredientInput]
        @Binding var draggedItem: IngredientInput?
        
        func performDrop(info: DropInfo) -> Bool {
            draggedItem = nil
            return true
        }
        
        func dropEntered(info: DropInfo) {
            guard let draggedItem = self.draggedItem else { return }
            
            if let fromIndex = ingredients.firstIndex(where: { $0.id == draggedItem.id }),
               let toIndex = ingredients.firstIndex(where: { $0.id == item.id }),
               fromIndex != toIndex,
               !ingredients[fromIndex].isPlaceholder,
               !ingredients[toIndex].isPlaceholder {
                
                withAnimation(.default) {
                    ingredients.move(fromIndex: fromIndex, toIndex: toIndex)
                }
            }
        }
        
        func dropUpdated(info: DropInfo) -> DropProposal? {
            return DropProposal(operation: .move)
        }
    }

    struct InstructionDropDelegate: DropDelegate {
        let item: StringInput
        @Binding var instructions: [StringInput]
        @Binding var draggedItem: StringInput?
        
        func performDrop(info: DropInfo) -> Bool {
            draggedItem = nil
            return true
        }
        
        func dropEntered(info: DropInfo) {
            guard let draggedItem = self.draggedItem else { return }
            
            if let fromIndex = instructions.firstIndex(where: { $0.id == draggedItem.id }),
               let toIndex = instructions.firstIndex(where: { $0.id == item.id }),
               fromIndex != toIndex,
               !instructions[fromIndex].isPlaceholder,
               !instructions[toIndex].isPlaceholder {
                
                withAnimation(.default) {
                    instructions.move(fromIndex: fromIndex, toIndex: toIndex)
                }
            }
        }
        
        func dropUpdated(info: DropInfo) -> DropProposal? {
            return DropProposal(operation: .move)
        }
    }
    
    private func saveRecipe() {
        // Convert string values to appropriate types
        let prepTimeInt = Int(prepTime) ?? 0
        let cookTimeInt = Int(cookTime) ?? 0
        let servingsInt = Int(servings) ?? 1
        
        // Process ingredients - filter out placeholder and empty ones
        let newIngredients = ingredients.compactMap { input -> Ingredient? in
            // Skip placeholder or empty ingredients
            guard !input.isPlaceholder && !input.name.isEmpty else { return nil }
            
            // Parse quantity string - now handles fractions like 2 1/4
            var quantity: Double = 0
            
            // If quantity is empty, default to 1
            if input.quantityString.isEmpty {
                quantity = 1.0
            } else {
                // Check if we have a whole number and fraction (e.g., "2 1/4")
                let components = input.quantityString.components(separatedBy: " ")
                if components.count == 2, 
                   let wholeNumber = Double(components[0]),
                   components[1].contains("/") {
                    let fractionParts = components[1].components(separatedBy: "/")
                    if fractionParts.count == 2,
                       let numerator = Double(fractionParts[0]),
                       let denominator = Double(fractionParts[1]) {
                        quantity = wholeNumber + (numerator / denominator)
                    }
                } else if input.quantityString.contains("/") {
                    // Handle just a fraction (e.g., "1/4")
                    let fractionParts = input.quantityString.components(separatedBy: "/")
                    if fractionParts.count == 2,
                       let numerator = Double(fractionParts[0]),
                       let denominator = Double(fractionParts[1]) {
                        quantity = numerator / denominator
                    }
                } else {
                    // Regular decimal number
                    quantity = Double(input.quantityString) ?? 0
                }
            }
            
            return Ingredient(name: input.name, quantity: quantity, unit: input.unit)
        }
        
        // Process instructions - filter out placeholder and empty ones
        let newInstructions = instructions
            .filter { !$0.isPlaceholder && !$0.value.isEmpty }
            .map { $0.value }
        
        // Debug information
        print("DEBUG - Recipe validation: name '\(name)' (empty: \(name.isEmpty))")
        print("DEBUG - Original ingredients: \(ingredients.count), filtered: \(newIngredients.count)")
        if ingredients.count > 0 {
            for (i, ingredient) in ingredients.enumerated() {
                print("  Ingredient \(i): '\(ingredient.name)' (isPlaceholder: \(ingredient.isPlaceholder), isEmpty: \(ingredient.name.isEmpty))")
            }
        }
        print("DEBUG - Original instructions: \(instructions.count), filtered: \(newInstructions.count)")
        if instructions.count > 0 {
            for (i, instruction) in instructions.enumerated() {
                print("  Instruction \(i): '\(instruction.value)' (isPlaceholder: \(instruction.isPlaceholder), isEmpty: \(instruction.value.isEmpty))")
            }
        }
        
        // Validate
        guard !name.isEmpty, !newIngredients.isEmpty, !newInstructions.isEmpty else {
            // In a real app, you'd show an alert here
            print("Recipe name, ingredients, or instructions cannot be empty")
            return
        }
        
        // Create or update recipe
        let updatedOrNewRecipe = Recipe(
            id: recipeToEdit?.id ?? UUID(),
            name: name,
            ingredients: newIngredients,
            instructions: newInstructions,
            prepTime: prepTimeInt,
            cookTime: cookTimeInt,
            servings: servingsInt,
            imageData: selectedImageData,
            tags: selectedTagIDs
        )
        
        // Add to recipes array or update existing
        if let index = recipes.firstIndex(where: { $0.id == updatedOrNewRecipe.id }) {
            recipes[index] = updatedOrNewRecipe
            print("Updated existing recipe: \(updatedOrNewRecipe.name)")
        } else {
            recipes.append(updatedOrNewRecipe)
            print("Added new recipe: \(updatedOrNewRecipe.name)")
        }
        
        // Debug count of recipes after save
        print("Recipes array now contains \(recipes.count) recipes")
    }
    
    // MARK: - Helper Functions
    
    // Add this helper function to hide the keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var recipes: [Recipe] = []
        
        var body: some View {
            NavigationStack {
                AddRecipeView(recipes: $recipes)
            }
        }
    }
    
    return PreviewWrapper()
} 

// Extension for Array move functionality
extension Array {
    mutating func move(fromIndex: Int, toIndex: Int) {
        if fromIndex == toIndex { return }
        let element = self.remove(at: fromIndex)
        self.insert(element, at: toIndex)
    }
}
