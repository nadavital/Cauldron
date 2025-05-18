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

    @State private var draggedIngredient: IngredientInput?
    @State private var draggedInstruction: StringInput?

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
                                selectedImageData = data
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
                                        cleanupEmptyRows: cleanupEmptyRows,
                                        scheduleCleanup: scheduleCleanup,
                                        checkAndAddPlaceholder: checkAndAddInstructionPlaceholder,
                                        startDrag: startDragInstruction)

                    SaveButtonView(action: {
                        cleanupEmptyRows()
                        saveRecipe()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { dismiss() }
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
    }

    // MARK: - Helper Methods
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
        } else if let recipe = recipeToEdit {
            name = recipe.name
            prepTime = "\(recipe.prepTime)"
            cookTime = "\(recipe.cookTime)"
            servings = "\(recipe.servings)"
            selectedImageData = recipe.imageData
            selectedTagIDs = recipe.tags
            ingredients = recipe.ingredients.map {
                IngredientInput(id: $0.id, name: $0.name, quantityString: "\($0.quantity)", unit: $0.unit)
            } + [IngredientInput(name: "", quantityString: "", unit: .cups)]
            instructions = recipe.instructions.map { StringInput(value: $0) } + [StringInput(value: "", isPlaceholder: false)]
        }
    }

    private func saveRecipe() {
        let p = Int(prepTime) ?? 0
        let c = Int(cookTime) ?? 0
        let s = Int(servings) ?? 1
        let newIngs = ingredients.compactMap { inp -> Ingredient? in
            guard !inp.isPlaceholder && !inp.name.isEmpty else { return nil }
            // parse quantities including fractions...
            var qty: Double = 0
            let str = inp.quantityString
            if str.isEmpty { qty = 1 }
            else if str.contains("/") {
                let parts = str.split(separator: " ")
                if parts.count == 2, let w = Double(parts[0]), parts[1].contains("/") {
                    let f = parts[1].split(separator: "/").compactMap { Double($0) }
                    if f.count == 2 { qty = w + f[0]/f[1] }
                } else {
                    let f = str.split(separator: "/").compactMap { Double($0) }
                    if f.count == 2 { qty = f[0]/f[1] }
                }
            } else { qty = Double(str) ?? 0 }
            return Ingredient(name: inp.name, quantity: qty, unit: inp.unit)
        }
        let newInst = instructions.filter { !$0.isPlaceholder && !$0.value.isEmpty }.map { $0.value }
        guard !name.isEmpty, !newIngs.isEmpty, !newInst.isEmpty else { return }
        let rec = Recipe(id: recipeToEdit?.id ?? UUID(), name: name, ingredients: newIngs, instructions: newInst, prepTime: p, cookTime: c, servings: s, imageData: selectedImageData, tags: selectedTagIDs)
        if let idx = recipes.firstIndex(where: { $0.id == rec.id }) { recipes[idx] = rec }
        else { recipes.append(rec) }
    }
}
