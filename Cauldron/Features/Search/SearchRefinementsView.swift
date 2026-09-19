import SwiftUI

/// Compact controls keep every action reachable without clipping a strip of chips.
struct SearchRefinementsView: View {
    @Bindable var model: SearchTabViewModel
    let editIngredients: () -> Void
    let clear: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filters
                sort
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 12) {
                filters
                sort
            }
        }
        .font(.subheadline)
        .buttonStyle(.glass)
    }

    private var filters: some View {
        Menu {
            Picker("Cooking time", selection: $model.timeFilter) {
                ForEach(RecipeTimeFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            Button("Ingredients…", systemImage: "carrot", action: editIngredients)
            if !model.selectedCategories.isEmpty {
                Section("Meal and category") {
                    ForEach(model.selectedCategories.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
                        Button("Remove \(category.displayName)", systemImage: "xmark") {
                            model.toggleCategory(category)
                        }
                    }
                }
            }
            if model.hasActiveRefinements || !model.selectedCategories.isEmpty {
                Divider()
                Button("Clear filters", systemImage: "xmark.circle", action: clear)
            }
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease")
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
    }

    private var sort: some View {
        Menu {
            Picker("Sort", selection: $model.sortOrder) {
                ForEach(RecipeSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
    }
}
