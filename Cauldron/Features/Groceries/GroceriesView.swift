//
//  GroceriesView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import os

/// View for managing the unified grocery list
struct GroceriesView: View {
    let isActive: Bool
    @State private var viewModel: GroceriesViewModel
    @ObservedObject private var currentUserSession = CurrentUserSession.shared
    @State private var showingAddItem = false
    @State private var showingProfileSheet = false
    @State private var experiencePreferences: ExperiencePreferences
    @State private var collapsedGroups: Set<String> = []  // Track which groups are collapsed
    @State private var isAIAvailable = false

    init(dependencies: DependencyContainer, isActive: Bool = true) {
        self.isActive = isActive
        _viewModel = State(initialValue: GroceriesViewModel(dependencies: dependencies))
        _experiencePreferences = State(initialValue: .shared)
    }

    private var viewMode: GroceryGroupingType {
        experiencePreferences.groceryGrouping
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
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Groceries")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort By", selection: Binding(
                            get: { experiencePreferences.groceryGrouping },
                            set: { experiencePreferences.groceryGrouping = $0 }
                        )) {
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
                            Task { await viewModel.requestDeleteCheckedItems() }
                        } label: {
                            Label("Clear Checked", systemImage: "checkmark.circle.badge.xmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                }

                if !RuntimeEnvironment.prefersDesktopWorkspace {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if let user = currentUserSession.currentUser {
                            Button {
                                showingProfileSheet = true
                            } label: {
                                ProfileAvatar(user: user, size: 30, dependencies: viewModel.dependencies)
                            }
                            .accessibilityLabel("Profile and settings")
                            .accessibilityHint("Opens your profile and app settings")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingProfileSheet) {
                NavigationStack {
                    if let user = currentUserSession.currentUser {
                        UserProfileView(user: user, dependencies: viewModel.dependencies)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done", systemImage: "checkmark") { showingProfileSheet = false }
                                }
                            }
                        }
                }
                .appSheetSizing(.large)
            }
            .sheet(isPresented: $showingAddItem) {
                AddGroceryItemView(dependencies: viewModel.dependencies, onAdd: {
                    await viewModel.loadItems(viewMode: viewMode)
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .appSheetSizing(.compact)
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
            .overlay(alignment: .bottom) {
                if isActive {
                    VStack(spacing: Theme.Spacing.xs) {
                        if let transaction = viewModel.undoCoordinator.visibleTransaction {
                            undoBar(transaction)
                        }

                        HStack {
                            Spacer()

                            Button {
                                showingAddItem = true
                            } label: {
                                Label("Add Item", systemImage: "plus")
                                    .font(.headline)
                                    .padding(.horizontal, Theme.Spacing.xs)
                                    .padding(.vertical, Theme.Spacing.xxs)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.extraLarge)
                            .tint(.cauldronOrange)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xs)
                    .allowsHitTesting(true)
                }
            }
            .alert("Unable to Update Groceries", isPresented: Binding(
                get: { viewModel.operationErrorMessage != nil },
                set: { if !$0 { viewModel.operationErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.operationErrorMessage ?? "Please try again.")
            }
        }
    }

    private func undoBar(_ transaction: UndoTransactionCoordinator.VisibleTransaction) -> some View {
        AppSurface(style: .elevated) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(transaction.message)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer(minLength: Theme.Spacing.xs)
                Button(transaction.actionTitle) {
                    withAnimation(Theme.Animation.snappy) {
                        viewModel.undoCoordinator.undo()
                    }
                }
                .font(.headline)
                .foregroundStyle(Color.cauldronOrange)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: Theme.HitTarget.minimum)
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        EmptyStateView(
            title: "No Grocery Items",
            message: "Add items manually or from recipes.",
            systemImage: "cart"
        )
        .padding(Theme.Spacing.xxl)
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
                    HStack(spacing: Theme.Spacing.sm) {
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
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 88, for: .scrollContent)
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
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 88, for: .scrollContent)
    }

    // MARK: - Item Row

    private func itemRow(item: GroceryItemDisplay) -> some View {
        Button {
            Haptics.light()
            Task {
                await viewModel.toggleItem(id: item.id)
            }
        } label: {
            HStack {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isChecked ? .cauldronOrange : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: item.isChecked)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
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
        let ids = offsets.compactMap { index in
            viewModel.sortedItems.indices.contains(index) ? viewModel.sortedItems[index].id : nil
        }
        Task { await viewModel.requestDeleteItems(ids: ids) }
    }

    private func deleteItemsFromGroup(group: GroceryGroup, at offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            group.items.indices.contains(index) ? group.items[index].id : nil
        }
        Task { await viewModel.requestDeleteItems(ids: ids) }
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
    @State private var errorMessage: String?

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
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        Task {
                            do {
                                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmedName.isEmpty else { return }
                                let quantity = hasQuantity ? Quantity(value: quantityValue, unit: selectedUnit) : nil
                                let listId = try await dependencies.groceryRepository.getOrCreateDefaultList()
                                try await dependencies.groceryRepository.addItem(
                                    listId: listId,
                                    name: trimmedName,
                                    quantity: quantity
                                )
                                await onAdd()
                                dismiss()
                            } catch {
                                errorMessage = "Cauldron couldn't add this item. Your entry is still here."
                            }
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
            .alert("Unable to Add Item", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
}

// MARK: - View Model

@MainActor
@Observable
final class GroceriesViewModel {
    var items: [GroceryItemDisplay] = []
    var groups: [GroceryGroup] = []
    var sortedItems: [GroceryItemDisplay] = []
    var inlineItemName = ""
    var operationErrorMessage: String?

    let dependencies: DependencyContainer
    let undoCoordinator: UndoTransactionCoordinator
    private var currentViewMode: GroceryGroupingType = .recipe
    @ObservationIgnored private var categorizationTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherCategorizationPass = false
    @ObservationIgnored private var pendingDeleteIDs: Set<UUID> = []
    @ObservationIgnored private var itemsRevision = 0
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private static let maximumLoadAttempts = 3
    @ObservationIgnored private var deferredReloadTask: Task<Void, Never>?
    @ObservationIgnored private var deferredReloadGeneration = 0
    @ObservationIgnored private let loadItemsAction: @MainActor () async throws -> [GroceryItemDisplay]
    @ObservationIgnored private let addItemAction: @MainActor (String) async throws -> Void
    @ObservationIgnored private let toggleItemAction: @MainActor (UUID) async throws -> Void
    @ObservationIgnored private let deleteItemsAction: @MainActor (Set<UUID>) async throws -> Void

    var hasCheckedItems: Bool {
        items.contains { $0.isChecked }
    }

    init(
        dependencies: DependencyContainer,
        undoCoordinator: UndoTransactionCoordinator? = nil,
        loadItemsAction: (@MainActor () async throws -> [GroceryItemDisplay])? = nil,
        addItemAction: (@MainActor (String) async throws -> Void)? = nil,
        toggleItemAction: (@MainActor (UUID) async throws -> Void)? = nil,
        deleteItemsAction: (@MainActor (Set<UUID>) async throws -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.undoCoordinator = undoCoordinator ?? UndoTransactionCoordinator()
        self.loadItemsAction = loadItemsAction ?? { [repository = dependencies.groceryRepository] in
            try await repository.fetchAllItemsForDisplay()
        }
        self.addItemAction = addItemAction ?? { [repository = dependencies.groceryRepository] name in
            let listID = try await repository.getOrCreateDefaultList()
            try await repository.addItem(listId: listID, name: name)
        }
        self.toggleItemAction = toggleItemAction ?? { [repository = dependencies.groceryRepository] id in
            try await repository.toggleItem(id: id)
        }
        self.deleteItemsAction = deleteItemsAction ?? { [repository = dependencies.groceryRepository] ids in
            try await repository.deleteItems(ids: ids)
        }
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func loadItems(viewMode: GroceryGroupingType? = nil, animated: Bool = false) async {
        deferredReloadTask?.cancel()
        deferredReloadTask = nil
        deferredReloadGeneration &+= 1
        loadGeneration &+= 1
        let generation = loadGeneration
        await performLoad(
            viewMode: viewMode,
            animated: animated,
            allowsDeferredRetry: true,
            generation: generation
        )
    }

    private func performLoad(
        viewMode: GroceryGroupingType?,
        animated: Bool,
        allowsDeferredRetry: Bool,
        generation: Int
    ) async {
        if let viewMode = viewMode {
            currentViewMode = viewMode
        }
        do {
            var loadedItems: [GroceryItemDisplay]?
            for attempt in 1...Self.maximumLoadAttempts {
                guard !Task.isCancelled else { return }
                let requestedRevision = itemsRevision
                let candidateItems = try await loadItemsAction()
                guard !Task.isCancelled else { return }
                guard generation == loadGeneration else { return }
                guard requestedRevision == itemsRevision else {
                    if attempt == Self.maximumLoadAttempts {
                        AppLogger.persistence.notice(
                            "Grocery items changed during \(Self.maximumLoadAttempts) consecutive loads"
                        )
                    }
                    continue
                }

                loadedItems = candidateItems
                break
            }

            guard let loadedItems else {
                if allowsDeferredRetry {
                    scheduleDeferredReload(animated: animated, generation: generation)
                } else {
                    AppLogger.persistence.notice(
                        "Grocery items kept changing during the deferred reload; keeping the current view state"
                    )
                }
                return
            }
            items = loadedItems.filter { !pendingDeleteIDs.contains($0.id) }

            if animated {
                withAnimation(.easeInOut(duration: 0.3)) {
                    updateSortedItems()
                    updateGroups(for: currentViewMode)
                }
            } else {
                updateSortedItems()
                updateGroups(for: currentViewMode)
            }

            scheduleCategorizationIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            AppLogger.persistence.error("Failed to load grocery items: \(error.localizedDescription)")
        }
    }

    private func scheduleDeferredReload(animated: Bool, generation requestGeneration: Int) {
        guard requestGeneration == loadGeneration,
              deferredReloadTask == nil else { return }

        deferredReloadGeneration &+= 1
        let deferredGeneration = deferredReloadGeneration
        deferredReloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.loadGeneration == requestGeneration,
                  self.deferredReloadGeneration == deferredGeneration else { return }

            await self.performLoad(
                viewMode: self.currentViewMode,
                animated: animated,
                allowsDeferredRetry: false,
                generation: requestGeneration
            )

            guard self.deferredReloadGeneration == deferredGeneration else { return }
            self.deferredReloadTask = nil
        }
    }

    private func scheduleCategorizationIfNeeded() {
        guard categorizationTask == nil else {
            needsAnotherCategorizationPass = true
            return
        }

        categorizationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.categorizationTask = nil
                if self.needsAnotherCategorizationPass {
                    self.needsAnotherCategorizationPass = false
                    self.scheduleCategorizationIfNeeded()
                }
            }
            await self.categorizeUncategorizedItems()
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

            let results = try await dependencies.groceryCategorizer.categorizeItems(uncategorized)
            guard !results.isEmpty else { return }

            for (itemId, category) in results {
                try await dependencies.groceryRepository.updateCategory(itemId: itemId, category: category)
            }

            applyCategorizationResults(results)
        } catch {
            AppLogger.persistence.error("Failed to categorize items: \(error.localizedDescription)")
        }
    }

    func applyCategorizationResults(_ results: [UUID: String]) {
        guard !results.isEmpty else { return }
        itemsRevision &+= 1

        items = items.map { item in
            guard let category = results[item.id] else { return item }
            return GroceryItemDisplay(
                id: item.id,
                name: item.name,
                quantity: item.quantity,
                isChecked: item.isChecked,
                recipeID: item.recipeID,
                recipeName: item.recipeName,
                addedOrder: item.addedOrder,
                aiCategory: category
            )
        }
        updateSortedItems()
        updateGroups(for: currentViewMode)
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

    @discardableResult
    func addQuickItem() async -> Bool {
        let trimmedName = inlineItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        do {
            try await addItemAction(trimmedName)
            inlineItemName = ""
            operationErrorMessage = nil
            await loadItems(viewMode: currentViewMode)
            return true
        } catch {
            operationErrorMessage = "Cauldron couldn't add \"\(trimmedName)\". Your entry is still here."
            return false
        }
    }

    func toggleItem(id: UUID) async {
        do {
            try await toggleItemAction(id)
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                await loadItems(animated: true)
                return
            }

            itemsRevision &+= 1
            items[index].isChecked.toggle()
            withAnimation(.easeInOut(duration: 0.3)) {
                updateSortedItems()
                updateGroups(for: currentViewMode)
            }
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

            let idsToToggle = Set(itemsToToggle.map(\.id))
            itemsRevision &+= 1
            items = items.map { item in
                guard idsToToggle.contains(item.id) else { return item }
                var updatedItem = item
                updatedItem.isChecked = !allChecked
                return updatedItem
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                updateSortedItems()
                updateGroups(for: currentViewMode)
            }
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

    func requestDeleteItems(ids: [UUID]) async {
        let requestedIDs = Set(ids)
        guard !requestedIDs.isEmpty else { return }

        // Resolve the previous optimistic transaction before snapshotting this
        // one. Its commit failure may restore items that must be represented in
        // the replacement transaction's snapshot.
        await undoCoordinator.commitNow()

        let exactIDs = requestedIDs.intersection(items.map(\.id))
        guard !exactIDs.isEmpty else { return }

        let deletedSnapshots = items.enumerated().compactMap { index, item in
            exactIDs.contains(item.id) ? DeletedItemSnapshot(item: item, originalIndex: index) : nil
        }
        pendingDeleteIDs.formUnion(exactIDs)
        itemsRevision &+= 1
        items.removeAll { exactIDs.contains($0.id) }
        updateSortedItems()
        updateGroups(for: currentViewMode)

        let count = exactIDs.count
        await undoCoordinator.schedule(
            message: count == 1 ? "Grocery item removed" : "\(count) grocery items removed",
            commit: { [weak self, deleteItemsAction] in
                try await deleteItemsAction(exactIDs)
                self?.finishDelete(ids: exactIDs)
            },
            undo: { [weak self] in
                self?.restoreDeletedItems(deletedSnapshots, ids: exactIDs)
            },
            onFailure: { [weak self] error in
                self?.restoreDeletedItems(deletedSnapshots, ids: exactIDs)
                self?.operationErrorMessage = "Cauldron couldn't remove the selected groceries. Nothing was lost."
                AppLogger.persistence.error("Failed to delete grocery items: \(error.localizedDescription)")
            }
        )
    }

    func requestDeleteCheckedItems() async {
        await requestDeleteItems(ids: items.filter(\.isChecked).map(\.id))
    }

    private struct DeletedItemSnapshot {
        let item: GroceryItemDisplay
        let originalIndex: Int
    }

    private func finishDelete(ids: Set<UUID>) {
        pendingDeleteIDs.subtract(ids)
        itemsRevision &+= 1
        items.removeAll { ids.contains($0.id) }
        updateSortedItems()
        updateGroups(for: currentViewMode)
    }

    private func restoreDeletedItems(_ snapshots: [DeletedItemSnapshot], ids: Set<UUID>) {
        pendingDeleteIDs.subtract(ids)
        itemsRevision &+= 1

        var currentIDs = Set(items.map(\.id))
        for snapshot in snapshots.sorted(by: { $0.originalIndex < $1.originalIndex })
            where !currentIDs.contains(snapshot.item.id) {
            items.insert(snapshot.item, at: min(snapshot.originalIndex, items.endIndex))
            currentIDs.insert(snapshot.item.id)
        }
        updateSortedItems()
        updateGroups(for: currentViewMode)
    }
}

#Preview {
    GroceriesView(dependencies: .preview())
}
