//
//  GroceriesView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import os
import Combine

/// View for managing grocery lists
struct GroceriesView: View {
    @StateObject private var viewModel: GroceriesViewModel
    @State private var showingNewList = false
    @State private var showingMergeView = false
    
    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: GroceriesViewModel(dependencies: dependencies))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.lists.isEmpty {
                    emptyState
                } else {
                    groceryListsList
                }
            }
            .navigationTitle("Grocery Lists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingNewList = true
                        } label: {
                            Label("New Empty List", systemImage: "plus")
                        }
                        
                        Button {
                            showingMergeView = true
                        } label: {
                            Label("From Recipes", systemImage: "fork.knife")
                        }
                    } label: {
                        Label("New List", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewList) {
                NewGroceryListView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingMergeView) {
                GroceryListMergeView(dependencies: viewModel.dependencies)
            }
            .task {
                await viewModel.loadLists()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cart")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Grocery Lists")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create a list to start shopping")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingNewList = true
            } label: {
                Label("Create First List", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.cauldronOrange)
        }
        .padding(40)
    }
    
    private var groceryListsList: some View {
        List {
            ForEach(viewModel.lists, id: \.id) { list in
                NavigationLink(destination: GroceryListDetailView(listId: list.id, dependencies: viewModel.dependencies)) {
                    VStack(alignment: .leading) {
                        Text(list.title)
                            .font(.headline)
                        Text("\(list.itemCount) items • \(list.createdAt.timeAgo())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteLists)
        }
    }
    
    private func deleteLists(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let list = viewModel.lists[index]
                await viewModel.deleteList(list.id)
            }
        }
    }
}

struct NewGroceryListView: View {
    @ObservedObject var viewModel: GroceriesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("List name", text: $title)
            }
            .navigationTitle("New Grocery List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", systemImage: "checkmark") {
                        Task {
                            await viewModel.createList(title: title)
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

struct GroceryListDetailView: View {
    let listId: UUID
    let dependencies: DependencyContainer
    
    @State private var items: [(id: UUID, name: String, quantity: Quantity?, isChecked: Bool)] = []
    @State private var showingAddItem = false
    @State private var autoSort = true
    @State private var showingAddToPantryConfirmation = false
    @State private var showingShareSheet = false
    @State private var shareText = ""
    
    var checkedItems: [(id: UUID, name: String, quantity: Quantity?, isChecked: Bool)] {
        items.filter { $0.isChecked }
    }
    
    var sortedItems: [(id: UUID, name: String, quantity: Quantity?, isChecked: Bool)] {
        if autoSort {
            return items.sorted { !$0.isChecked && $1.isChecked }
        } else {
            return items
        }
    }
    
    var body: some View {
        List {
            ForEach(sortedItems, id: \.id) { item in
                Button {
                    Task {
                        try? await dependencies.groceryRepository.toggleItem(id: item.id)
                        await loadItems()
                    }
                } label: {
                    HStack {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(item.isChecked ? .cauldronOrange : .secondary)
                        
                        VStack(alignment: .leading) {
                            Text(item.name)
                                .strikethrough(item.isChecked)
                            if let quantity = item.quantity {
                                Text(quantity.displayString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteItems)
        }
        .navigationTitle("Grocery List")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        autoSort.toggle()
                    } label: {
                        Label(autoSort ? "Auto-sort: On" : "Auto-sort: Off", 
                              systemImage: autoSort ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    }
                    
                    Divider()
                    
                    Button {
                        selectAll()
                    } label: {
                        Label("Check All", systemImage: "checkmark.circle")
                    }
                    
                    Button {
                        uncheckAll()
                    } label: {
                        Label("Uncheck All", systemImage: "circle")
                    }
                    
                    Divider()
                    
                    if !checkedItems.isEmpty {
                        Button {
                            showingAddToPantryConfirmation = true
                        } label: {
                            Label("Add Checked to Pantry", systemImage: "archivebox")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView(listId: listId, dependencies: dependencies, onAdd: {
                await loadItems()
            })
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [shareText])
        }
        .confirmationDialog("Add to Pantry", isPresented: $showingAddToPantryConfirmation) {
            Button("Add \(checkedItems.count) items to Pantry") {
                Task {
                    await addCheckedItemsToPantry()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will add all checked items to your pantry and remove them from this list.")
        }
        .task {
            await loadItems()
        }
    }
    
    private func loadItems() async {
        do {
            items = try await dependencies.groceryRepository.fetchItems(listId: listId)
        } catch {
            AppLogger.persistence.error("Failed to load grocery items: \(error.localizedDescription)")
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let item = items[index]
                try? await dependencies.groceryRepository.deleteItem(id: item.id)
            }
            await loadItems()
        }
    }
    
    private func exportAndShare() {
        let groceryItems = items.map { item in
            GroceryItem(name: item.name, quantity: item.quantity)
        }
        shareText = dependencies.groceryService.exportToText(groceryItems)
        showingShareSheet = true
    }
    
    private func selectAll() {
        Task {
            for item in items where !item.isChecked {
                try? await dependencies.groceryRepository.toggleItem(id: item.id)
            }
            await loadItems()
        }
    }
    
    private func uncheckAll() {
        Task {
            for item in items where item.isChecked {
                try? await dependencies.groceryRepository.toggleItem(id: item.id)
            }
            await loadItems()
        }
    }
    
    private func addCheckedItemsToPantry() async {
        for item in checkedItems {
            // Add to pantry
            do {
                try await dependencies.pantryRepository.add(name: item.name, quantity: item.quantity)
                // Remove from grocery list
                try await dependencies.groceryRepository.deleteItem(id: item.id)
            } catch {
                AppLogger.persistence.error("Failed to add item to pantry: \(error.localizedDescription)")
            }
        }
        await loadItems()
    }
}

struct AddGroceryItemView: View {
    let listId: UUID
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
                            try? await dependencies.groceryRepository.addItem(
                                listId: listId,
                                name: name,
                                quantity: quantity
                            )
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

@MainActor
class GroceriesViewModel: ObservableObject {
    @Published var lists: [(id: UUID, title: String, createdAt: Date, itemCount: Int)] = []
    let dependencies: DependencyContainer
    
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }
    
    func loadLists() async {
        do {
            lists = try await dependencies.groceryRepository.fetchAllLists()
        } catch {
            AppLogger.persistence.error("Failed to load grocery lists: \(error.localizedDescription)")
        }
    }
    
    func createList(title: String) async {
        do {
            _ = try await dependencies.groceryRepository.createList(title: title)
            await loadLists()
        } catch {
            AppLogger.persistence.error("Failed to create grocery list: \(error.localizedDescription)")
        }
    }
    
    func deleteList(_ id: UUID) async {
        do {
            try await dependencies.groceryRepository.deleteList(id: id)
            await loadLists()
        } catch {
            AppLogger.persistence.error("Failed to delete grocery list: \(error.localizedDescription)")
        }
    }
}

#Preview {
    GroceriesView(dependencies: .preview())
}
