//
//  GroceriesView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import os
import Combine

/// View for managing the unified grocery list
struct GroceriesView: View {
    @StateObject private var viewModel: GroceriesViewModel
    @State private var showingAddItem = false
    @State private var viewMode: GroceryGroupingType = .recipe  // Default to grouped by recipe
    @State private var collapsedGroups: Set<String> = []  // Track which groups are collapsed
    @State private var isAIAvailable = false

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: GroceriesViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    if viewMode == .none {
                        ungroupedListView
                    } else {
                        groupedListView
                    }
                }
            }
            .navigationTitle("Groceries")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort By", selection: $viewMode) {
                            Label("Sorted by Recipe", systemImage: "list.bullet.rectangle")
                                .tag(GroceryGroupingType.recipe)
                            if isAIAvailable {
                                Label("AI Sort", systemImage: "apple.intelligence")
                                    .tag(GroceryGroupingType.aiSort)
                            }
                            Label("Unsorted", systemImage: "list.bullet")
                                .tag(GroceryGroupingType.none)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }

                if viewModel.hasCheckedItems {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteCheckedItems() }
                        } label: {
                            Label("Clear Checked", systemImage: "checkmark.circle.badge.xmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddGroceryItemView(dependencies: viewModel.dependencies, onAdd: {
                    await viewModel.loadItems(viewMode: viewMode)
                })
            }
            .task {
                await viewModel.loadItems(viewMode: viewMode)
                isAIAvailable = await viewModel.checkAIAvailability()
            }
            .refreshable {
                await viewModel.loadItems(viewMode: viewMode)
            }
            .onChange(of: viewMode) { _, newMode in
                viewModel.updateGroups(for: newMode)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cart")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Grocery Items")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add items manually or from recipes")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingAddItem = true
            } label: {
                Label("Add First Item", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.cauldronOrange)
        }
        .padding(40)
    }

    // MARK: - Grouped View (by Recipe)

    private var groupedListView: some View {
        List {
            ForEach(viewModel.groups) { group in
                Section {
                    if !collapsedGroups.contains(group.id) {
                        ForEach(group.items) { item in
                            itemRow(item: item)
                                .id(item.id)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        .onDelete { offsets in
                            deleteItemsFromGroup(group: group, at: offsets)
                        }
                    }
                } header: {
                    HStack(spacing: 12) {
                        // Check/uncheck button on the left
                        Button {
                            Task {
                                await viewModel.toggleRecipe(recipeID: group.id)
                            }
                        } label: {
                            Image(systemName: group.allItemsChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(group.allItemsChecked ? .cauldronOrange : .secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        // Recipe name in the middle
                        Text(group.name)
                            .font(.headline)

                        Spacer()

                        // Item count
                        Text("\(group.items.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Collapse/expand button on the right
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if collapsedGroups.contains(group.id) {
                                    collapsedGroups.remove(group.id)
                                } else {
                                    collapsedGroups.insert(group.id)
                                }
                            }
                        } label: {
                            Image(systemName: collapsedGroups.contains(group.id) ? "chevron.right" : "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.title3)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.groups.map { $0.id })
    }

    // MARK: - Ungrouped View

    private var ungroupedListView: some View {
        List {
            ForEach(viewModel.sortedItems) { item in
                itemRow(item: item)
                    .id(item.id)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            .onDelete(perform: deleteItems)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.sortedItems.map { $0.id })
    }

    // MARK: - Item Row

    private func itemRow(item: GroceryItemDisplay) -> some View {
        Button {
            Task {
                await viewModel.toggleItem(id: item.id)
            }
        } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isChecked ? .cauldronOrange : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .strikethrough(item.isChecked)
                    if let quantity = item.quantity {
                        Text(quantity.displayString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Delete Operations

    private func deleteItems(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let item = viewModel.sortedItems[index]
                await viewModel.deleteItem(id: item.id)
            }
        }
    }

    private func deleteItemsFromGroup(group: GroceryGroup, at offsets: IndexSet) {
        Task {
            for index in offsets {
                let item = group.items[index]
                await viewModel.deleteItem(id: item.id)
            }
        }
    }
}

// MARK: - Add Item View

struct AddGroceryItemView: View {
    let dependencies: DependencyContainer
    let onAdd: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hasQuantity = false
    @State private var quantityValue: Double = 1.0
    @State private var selectedUnit: UnitKind = .cup

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Toggle("Add Quantity", isOn: $hasQuantity)
                }

                if hasQuantity {
                    Section("Quantity") {
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("0", value: $quantityValue, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }

                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(UnitKind.allCases, id: \.self) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        Task {
                            let quantity = hasQuantity ? Quantity(value: quantityValue, unit: selectedUnit) : nil
                            let listId = try? await dependencies.groceryRepository.getOrCreateDefaultList()
                            if let listId = listId {
                                try? await dependencies.groceryRepository.addItem(
                                    listId: listId,
                                    name: name,
                                    quantity: quantity
                                )
                            }
                            await onAdd()
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
class GroceriesViewModel: ObservableObject {
    @Published var items: [GroceryItemDisplay] = []
    @Published var groups: [GroceryGroup] = []
    @Published var sortedItems: [GroceryItemDisplay] = []

    let dependencies: DependencyContainer
    private var currentViewMode: GroceryGroupingType = .recipe

    var hasCheckedItems: Bool {
        items.contains { $0.isChecked }
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    func loadItems(viewMode: GroceryGroupingType? = nil, animated: Bool = false) async {
        if let viewMode = viewMode {
            currentViewMode = viewMode
        }
        do {
            items = try await dependencies.groceryRepository.fetchAllItemsForDisplay()

            if animated {
                withAnimation(.easeInOut(duration: 0.3)) {
                    updateSortedItems()
                    updateGroups(for: currentViewMode)
                }
            } else {
                updateSortedItems()
                updateGroups(for: currentViewMode)
            }

            // Categorize uncategorized items in background
            await categorizeUncategorizedItems()
        } catch {
            AppLogger.persistence.error("Failed to load grocery items: \(error.localizedDescription)")
        }
    }

    /// Categorize items that don't have an AI category yet
    private func categorizeUncategorizedItems() async {
        guard await dependencies.groceryCategorizer.isAvailable else {
            return
        }

        do {
            let uncategorized = try await dependencies.groceryRepository.fetchUncategorizedItems()
            guard !uncategorized.isEmpty else { return }

            // Categorize in background
            Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    let results = try await self.dependencies.groceryCategorizer.categorizeItems(uncategorized)
                    for (itemId, category) in results {
                        try await self.dependencies.groceryRepository.updateCategory(itemId: itemId, category: category)
                    }
                    // Reload items to show new categories
                    await MainActor.run {
                        Task { await self.loadItems() }
                    }
                } catch {
                    AppLogger.persistence.error("Failed to categorize items: \(error.localizedDescription)")
                }
            }
        } catch {
            AppLogger.persistence.error("Failed to fetch uncategorized items: \(error.localizedDescription)")
        }
    }

    func updateGroups(for mode: GroceryGroupingType) {
        currentViewMode = mode
        switch mode {
        case .recipe:
            groups = items.groupByRecipe()
        case .aiSort:
            groups = items.groupByAICategory()
        case .none:
            groups = []
        }
    }

    private func updateSortedItems() {
        sortedItems = items.sortForUngroupedView()
    }

    func checkAIAvailability() async -> Bool {
        return await dependencies.groceryCategorizer.isAvailable
    }

    func toggleItem(id: UUID) async {
        do {
            try await dependencies.groceryRepository.toggleItem(id: id)
            await loadItems(animated: true)
        } catch {
            AppLogger.persistence.error("Failed to toggle item: \(error.localizedDescription)")
        }
    }

    func toggleRecipe(recipeID: String) async {
        // Determine what we're toggling based on current view mode
        let itemsToToggle: [GroceryItemDisplay]

        switch currentViewMode {
        case .recipe:
            // Filter by recipeID
            itemsToToggle = items.filter { $0.recipeID == recipeID || (recipeID == "other" && $0.recipeID == nil) }
        case .aiSort:
            // Filter by AI category
            itemsToToggle = items.filter { $0.aiCategory == recipeID }
        case .none:
            return
        }

        let allChecked = !itemsToToggle.isEmpty && itemsToToggle.allSatisfy { $0.isChecked }

        do {
            if currentViewMode == .aiSort {
                // Use category-specific method
                try await dependencies.groceryRepository.setCategoryChecked(category: recipeID, isChecked: !allChecked)
            } else if recipeID == "other" {
                // For "Other Items", toggle each individual item
                for item in itemsToToggle {
                    if item.isChecked != !allChecked {
                        try await dependencies.groceryRepository.toggleItem(id: item.id)
                    }
                }
            } else {
                // For recipe items, use the bulk operation
                try await dependencies.groceryRepository.setRecipeChecked(recipeID: recipeID, isChecked: !allChecked)
            }
            await loadItems(animated: true)
        } catch {
            AppLogger.persistence.error("Failed to toggle group: \(error.localizedDescription)")
        }
    }

    func checkAll() async {
        do {
            try await dependencies.groceryRepository.setAllItemsChecked(isChecked: true)
            await loadItems()
        } catch {
            AppLogger.persistence.error("Failed to check all items: \(error.localizedDescription)")
        }
    }

    func uncheckAll() async {
        do {
            try await dependencies.groceryRepository.setAllItemsChecked(isChecked: false)
            await loadItems()
        } catch {
            AppLogger.persistence.error("Failed to uncheck all items: \(error.localizedDescription)")
        }
    }

    func deleteItem(id: UUID) async {
        do {
            try await dependencies.groceryRepository.deleteItem(id: id)
            await loadItems()
        } catch {
            AppLogger.persistence.error("Failed to delete item: \(error.localizedDescription)")
        }
    }

    func deleteCheckedItems() async {
        let checkedItemIds = items.filter { $0.isChecked }.map { $0.id }
        for id in checkedItemIds {
            do {
                try await dependencies.groceryRepository.deleteItem(id: id)
            } catch {
                AppLogger.persistence.error("Failed to delete item: \(error.localizedDescription)")
            }
        }
        await loadItems()
    }
}

#Preview {
    GroceriesView(dependencies: .preview())
}
