//
//  RecipeDetailView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import os

/// Detailed view of a recipe
struct RecipeDetailView: View {
    let recipe: Recipe
    let dependencies: DependencyContainer
    
    @State private var showingCookMode = false
    @State private var showingEditSheet = false
    @State private var scaleFactor: Double = 1.0
    @State private var showingGroceryOptions = false
    @State private var showingNewListSheet = false
    @State private var newListTitle = ""
    @State private var existingLists: [(id: UUID, title: String)] = []
    @State private var localIsFavorite: Bool
    @State private var scalingWarnings: [ScalingWarning] = []
    @State private var showingShareSheet = false
    
    init(recipe: Recipe, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.dependencies = dependencies
        self._localIsFavorite = State(initialValue: recipe.isFavorite)
    }
    
    private var scaledResult: ScaledRecipe {
        RecipeScaler.scale(recipe, by: scaleFactor)
    }
    
    private var scaledRecipe: Recipe {
        scaledResult.recipe
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Image
                if let imageURL = recipe.imageURL,
                   let image = loadImage(filename: imageURL.lastPathComponent) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipped()
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                
                // Header
                headerSection
                
                // Ingredients
                ingredientsSection
                
                // Steps
                stepsSection
                
                // Nutrition
                if let nutrition = recipe.nutrition, nutrition.hasData {
                    nutritionSection(nutrition)
                }
                
                // Notes
                if let notes = recipe.notes, !notes.isEmpty {
                    notesSection(notes)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: localIsFavorite ? "star.fill" : "star")
                        .foregroundStyle(localIsFavorite ? .yellow : .primary)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCookMode = true
                } label: {
                    Label("Start Cooking", systemImage: "flame.fill")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Recipe", systemImage: "pencil")
                    }
                    
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share Recipe", systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        Task {
                            await loadExistingLists()
                            showingGroceryOptions = true
                        }
                    } label: {
                        Label("Add to Grocery List", systemImage: "cart.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingCookMode) {
            CookModeView(recipe: recipe, dependencies: dependencies)
        }
        .sheet(isPresented: $showingEditSheet) {
            RecipeEditorView(dependencies: dependencies, recipe: recipe)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareRecipeView(recipe: recipe, dependencies: dependencies)
        }
        .confirmationDialog("Add to Grocery List", isPresented: $showingGroceryOptions) {
            Button("Create New List") {
                showingNewListSheet = true
            }
            
            ForEach(existingLists, id: \.id) { list in
                Button(list.title) {
                    Task {
                        await addToExistingList(list.id)
                    }
                }
            }
            
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingNewListSheet) {
            NavigationStack {
                Form {
                    TextField("List Name", text: $newListTitle)
                    
                    Button("Create & Add Items") {
                        Task {
                            await createNewListAndAddItems()
                            showingNewListSheet = false
                        }
                    }
                    .disabled(newListTitle.isEmpty)
                }
                .navigationTitle("New Grocery List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingNewListSheet = false
                        }
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                if let time = recipe.displayTime {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundColor(.cauldronOrange)
                        Text(time)
                    }
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .foregroundColor(.cauldronOrange)
                    Text(recipe.yields)
                }
                
                Spacer()
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recipe.tags) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.cauldronOrange.opacity(0.15))
                                .foregroundColor(.cauldronOrange)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            // Scale picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipe Scale")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Picker("Scale", selection: $scaleFactor) {
                    Text("½×").tag(0.5)
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                    Text("3×").tag(3.0)
                }
                .pickerStyle(.segmented)
                
                // Scaling warnings
                if !scaledResult.warnings.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(scaledResult.warnings) { warning in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: warning.icon)
                                    .foregroundColor(warning.color)
                                    .font(.caption)
                                
                                Text(warning.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(warning.color.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .cardStyle()
    }
    
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(scaledRecipe.ingredients) { ingredient in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.cauldronOrange)
                        .padding(.top, 6)
                        .fixedSize()
                    
                    Text(ingredient.displayString)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }
    
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(recipe.steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(step.index + 1)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.cauldronOrange)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.text)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if !step.timers.isEmpty {
                            HStack {
                                ForEach(step.timers) { timer in
                                    Label(timer.displayDuration, systemImage: "timer")
                                        .font(.caption)
                                        .foregroundColor(.cauldronOrange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.cauldronOrange.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .cardStyle()
    }
    
    private func nutritionSection(_ nutrition: Nutrition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrition")
                .font(.title2)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let calories = nutrition.calories {
                    nutritionItem(label: "Calories", value: "\(Int(calories))")
                }
                if let protein = nutrition.protein {
                    nutritionItem(label: "Protein", value: "\(Int(protein))g")
                }
                if let carbs = nutrition.carbohydrates {
                    nutritionItem(label: "Carbs", value: "\(Int(carbs))g")
                }
                if let fat = nutrition.fat {
                    nutritionItem(label: "Fat", value: "\(Int(fat))g")
                }
            }
        }
        .padding()
        .cardStyle()
    }
    
    private func nutritionItem(label: String, value: String) -> some View {
        VStack {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.cauldronOrange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.title2)
                .fontWeight(.bold)
            
            // Detect and make URLs clickable
            if let attributedString = makeLinksClickable(notes) {
                Text(attributedString)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .tint(.cauldronOrange)
            } else {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cardStyle()
    }
    
    private func makeLinksClickable(_ text: String) -> AttributedString? {
        var attributedString = AttributedString(text)
        
        // Regular expression to detect URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        guard let matches = matches, !matches.isEmpty else {
            return nil
        }
        
        for match in matches.reversed() {
            if let range = Range(match.range, in: text),
               let url = match.url {
                let startIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: match.range.location)
                let endIndex = attributedString.characters.index(startIndex, offsetBy: match.range.length)
                let attributedRange = startIndex..<endIndex
                
                attributedString[attributedRange].link = url
                attributedString[attributedRange].foregroundColor = .cauldronOrange
                attributedString[attributedRange].underlineStyle = .single
            }
        }
        
        return attributedString
    }
    
    private func loadExistingLists() async {
        do {
            let lists = try await dependencies.groceryRepository.fetchAllLists()
            existingLists = lists.map { (id: $0.id, title: $0.title) }
        } catch {
            AppLogger.general.error("Failed to load grocery lists: \(error.localizedDescription)")
        }
    }
    
    private func createNewListAndAddItems() async {
        do {
            let listId = try await dependencies.groceryRepository.createList(title: newListTitle)
            await addIngredientsToList(listId)
            newListTitle = ""
        } catch {
            AppLogger.general.error("Failed to create grocery list: \(error.localizedDescription)")
        }
    }
    
    private func addToExistingList(_ listId: UUID) async {
        await addIngredientsToList(listId)
    }
    
    private func addIngredientsToList(_ listId: UUID) async {
        for ingredient in scaledRecipe.ingredients {
            do {
                try await dependencies.groceryRepository.addItem(
                    listId: listId,
                    name: ingredient.name,
                    quantity: ingredient.quantity
                )
            } catch {
                AppLogger.general.error("Failed to add ingredient to grocery list: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadImage(filename: String) -> UIImage? {
        // Synchronous load for SwiftUI - consider caching for performance
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsURL.appendingPathComponent("RecipeImages").appendingPathComponent(filename)
        
        guard let imageData = try? Data(contentsOf: imageURL) else {
            return nil
        }
        return UIImage(data: imageData)
    }
    
    private func toggleFavorite() {
        Task {
            do {
                try await dependencies.recipeRepository.toggleFavorite(id: recipe.id)
                localIsFavorite.toggle()
            } catch {
                AppLogger.general.error("Failed to toggle favorite: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(
            recipe: Recipe(
                title: "Sample Recipe",
                ingredients: [
                    Ingredient(name: "Flour", quantity: Quantity(value: 2, unit: .cup)),
                    Ingredient(name: "Sugar", quantity: Quantity(value: 1, unit: .cup))
                ],
                steps: [
                    CookStep(index: 0, text: "Mix dry ingredients", timers: []),
                    CookStep(index: 1, text: "Bake for 30 minutes", timers: [.minutes(30)])
                ]
            ),
            dependencies: .preview()
        )
    }
}

