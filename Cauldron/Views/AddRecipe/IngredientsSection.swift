import SwiftUI

struct IngredientsSection: View {
    @Binding var ingredients: [IngredientInput]
    @Binding var isEditMode: Bool
    @Binding var draggedIngredient: IngredientInput?
    let cleanupEmptyRows: () -> Void
    let scheduleCleanup: () -> Void
    let checkAndAddPlaceholder: () -> Void
    let startDrag: (IngredientInput) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Ingredients", systemImage: "basket")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(action: {
                    withAnimation {
                        isEditMode.toggle()
                        cleanupEmptyRows()
                    }
                }) {
                    Text(isEditMode ? "Done" : "Edit")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
                        .foregroundColor(.accentColor)
                }
                if !isEditMode {
                    Button(action: {
                        withAnimation {
                            if let idx = ingredients.firstIndex(where: { $0.isPlaceholder }) {
                                ingredients.insert(IngredientInput(name: "", quantityString: "", unit: .cups), at: idx)
                                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { ingredients[idx].isFocused = true }
                            } else {
                                ingredients.append(IngredientInput(name: "", quantityString: "", unit: .cups))
                                let newIdx = ingredients.count-1
                                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { ingredients[newIdx].isFocused = true }
                            }
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            VStack(spacing: 10) {
                ForEach($ingredients) { $ingredient in
                    if isEditMode {
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.trailing, 2)
                                .onDrag { startDrag(ingredient); return NSItemProvider() }
                                .onDrop(of: [.text], delegate: IngredientDropDelegate(item: ingredient, ingredients: $ingredients, draggedItem: $draggedIngredient))
                            IngredientInputRow(name: $ingredient.name, quantityString: $ingredient.quantityString, unit: $ingredient.unit, isFocused: $ingredient.isFocused)
                            Button(action: {
                                withAnimation { ingredients.removeAll { $0.id == ingredient.id }; cleanupEmptyRows() }
                            }) {
                                Image(systemName: "minus.circle.fill").font(.title3).foregroundColor(.red)
                            }.padding(.leading, 8)
                        }
                    } else {
                        IngredientInputRow(name: $ingredient.name, quantityString: $ingredient.quantityString, unit: $ingredient.unit, isFocused: $ingredient.isFocused)
                            .onChange(of: ingredient.isFocused) { focused in
                                if focused { checkAndAddPlaceholder() }
                            }
                            .onChange(of: ingredient.name) { new in
                                if ingredient.id == ingredients.last?.id && !new.isEmpty { withAnimation { ingredients.append(IngredientInput(name: "", quantityString: "", unit: .cups)) } }
                                else if new.isEmpty && ingredient.id != ingredients.last?.id { scheduleCleanup() }
                            }
                    }
                }.transition(.asymmetric(insertion: .scale, removal: .opacity))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    // Local DropDelegate to handle reordering
    struct IngredientDropDelegate: DropDelegate {
        let item: IngredientInput
        @Binding var ingredients: [IngredientInput]
        @Binding var draggedItem: IngredientInput?
        func performDrop(info: DropInfo) -> Bool { draggedItem = nil; return true }
        func dropEntered(info: DropInfo) {
            guard let dragged = draggedItem,
                  let from = ingredients.firstIndex(where: { $0.id == dragged.id }),
                  let to = ingredients.firstIndex(where: { $0.id == item.id }),
                  from != to,
                  !ingredients[from].isPlaceholder,
                  !ingredients[to].isPlaceholder else { return }
            withAnimation { ingredients.move(fromIndex: from, toIndex: to) }
        }
        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    }
}
