//
//  PantryView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import Combine
import os

struct PantryEditItem: Identifiable {
    let id: UUID
    let name: String
    let quantity: Quantity?
}

/// View for managing pantry items
struct PantryView: View {
    @StateObject private var viewModel: PantryViewModel
    @State private var showingAddItem = false
    @State private var editingItem: PantryEditItem?
    
    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: PantryViewModel(dependencies: dependencies))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    itemsList
                }
            }
            .navigationTitle("Pantry")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddItem = true
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddPantryItemView(viewModel: viewModel, editingItem: nil)
            }
            .sheet(item: $editingItem) { item in
                AddPantryItemView(viewModel: viewModel, editingItem: item)
            }
            .task {
                await viewModel.loadItems()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cabinet")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Pantry is Empty")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add ingredients you have on hand")
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
    
    private var itemsList: some View {
        List {
            ForEach(viewModel.items, id: \.id) { item in
                Button {
                    editingItem = PantryEditItem(id: item.id, name: item.name, quantity: item.quantity)
                } label: {
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.cauldronOrange)
                        
                        Text(item.name)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if let quantity = item.quantity {
                            Text(quantity.displayString)
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteItems)
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let item = viewModel.items[index]
                await viewModel.deleteItem(item.id)
            }
        }
    }
}

struct AddPantryItemView: View {
    @ObservedObject var viewModel: PantryViewModel
    let editingItem: PantryEditItem?
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var hasQuantity = false
    @State private var quantityValue: Double = 1.0
    @State private var selectedUnit: UnitKind = .cup
    
    private var isEditing: Bool { editingItem != nil }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item name (e.g., flour, sugar)", text: $name)
                        .textInputAutocapitalization(.words)
                }
                
                Section {
                    Toggle("Track Quantity", isOn: $hasQuantity)
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
            .navigationTitle(isEditing ? "Edit Item" : "Add Pantry Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Add", systemImage: "checkmark") {
                        Task {
                            let quantity = hasQuantity ? Quantity(value: quantityValue, unit: selectedUnit) : nil
                            if let editing = editingItem {
                                await viewModel.updateItem(id: editing.id, name: name, quantity: quantity)
                            } else {
                                await viewModel.addItem(name: name, quantity: quantity)
                            }
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let editing = editingItem {
                    name = editing.name
                    if let quantity = editing.quantity {
                        hasQuantity = true
                        quantityValue = quantity.value
                        selectedUnit = quantity.unit
                    }
                }
            }
        }
    }
}

@MainActor
class PantryViewModel: ObservableObject {
    @Published var items: [(id: UUID, name: String, quantity: Quantity?)] = []
    let dependencies: DependencyContainer
    
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }
    
    func loadItems() async {
        do {
            items = try await dependencies.pantryRepository.fetchAll()
        } catch {
            AppLogger.persistence.error("Failed to load pantry: \(error.localizedDescription)")
        }
    }
    
    func addItem(name: String, quantity: Quantity?) async {
        do {
            try await dependencies.pantryRepository.add(name: name, quantity: quantity)
            await loadItems()
        } catch {
            AppLogger.persistence.error("Failed to add pantry item: \(error.localizedDescription)")
        }
    }
    
    func updateItem(id: UUID, name: String, quantity: Quantity?) async {
        do {
            try await dependencies.pantryRepository.update(id: id, name: name, quantity: quantity)
            await loadItems()
        } catch {
            AppLogger.persistence.error("Failed to update pantry item: \(error.localizedDescription)")
        }
    }
    
    func deleteItem(_ id: UUID) async {
        do {
            try await dependencies.pantryRepository.delete(id: id)
            await loadItems()
        } catch {
            AppLogger.persistence.error("Failed to delete pantry item: \(error.localizedDescription)")
        }
    }
}

#Preview {
    PantryView(dependencies: .preview())
}
