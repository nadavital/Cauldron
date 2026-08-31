//
//  MainTabView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import Combine
import os
import UIKit

/// Tab identifiers for MainTabView
enum AppTab: Hashable {
    case cook
    case collections
    case collection(UUID)
    case groceries
    case sharing
    case search
}

/// Main tab-based navigation view
struct MainTabView: View {
    private enum DesktopProfileLayout {
        static let avatarSize: CGFloat = 18
        static let rowHeight: CGFloat = 32
        static let contentSpacing: CGFloat = 10
        static let horizontalInset: CGFloat = 30
        static let bottomInset: CGFloat = 8
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let dependencies: DependencyContainer
    let preloadedData: PreloadedRecipeData?
    @State private var selectedTab: AppTab
    @State private var sidebarCollections: [Collection] = []
    @State private var sharedImportRequest: SharedImportRequest?
    @State private var didCheckInitialPendingImport = false
    @State private var isSavingPreparedSharedRecipe = false
    @State private var isIngestingShareTransport = false
    @State private var showSharedRecipeSavedToast = false
    @State private var sidebarRefreshTask: Task<Void, Never>?
    @State private var activeShareImportAcknowledgement: ShareImportAcknowledgement?
    @State private var isOpeningRecipeIntent = false
    @State private var showingDesktopProfileSheet = false
    @Binding private var pendingSharedContent: ContentView.SharedContentWrapper?
    @ObservedObject private var connectionManager: ConnectionManager
    @ObservedObject private var currentUserSession = CurrentUserSession.shared

    @State private var searchNavigationPath = NavigationPath()

    private enum ShareImportAcknowledgement: Equatable {
        case prepared(Data)
        case text(String)
        case url(URL)
        case durableJob(UUID)

        var durableJobID: UUID? {
            guard case .durableJob(let id) = self else { return nil }
            return id
        }
    }

    private struct SharedImportRequest: Identifiable {
        let id = UUID()
        let initialURL: URL?
        let initialText: String?
        let preparedRecipe: Recipe?
        let preparedSourceInfo: String?
        let destinationRecipeID: UUID?
    }

    private var isCookModeActive: Bool {
        dependencies.cookModeCoordinator.isActive && dependencies.cookModeCoordinator.currentRecipe != nil
    }

    private var isRegularWidthLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var featuredSidebarCollections: [Collection] {
        Array(sidebarCollections.prefix(4))
    }

    private var selectedTabBinding: Binding<AppTab?> {
        Binding(
            get: { selectedTab },
            set: { selectedTab = $0 ?? .cook }
        )
    }

    init(
        dependencies: DependencyContainer,
        preloadedData: PreloadedRecipeData?,
        pendingSharedContent: Binding<ContentView.SharedContentWrapper?> = .constant(nil)
    ) {
        self.dependencies = dependencies
        self.preloadedData = preloadedData
        self._pendingSharedContent = pendingSharedContent
        self.connectionManager = dependencies.connectionManager
        self._selectedTab = State(initialValue: Self.initialSelectedTab())
    }

    var body: some View {
        appIntentAwareScaffold
        .fullScreenCover(isPresented: Binding(
            get: { dependencies.cookModeCoordinator.showFullScreen },
            set: { dependencies.cookModeCoordinator.showFullScreen = $0 }
        )) {
            if let recipe = dependencies.cookModeCoordinator.currentRecipe {
                NavigationStack {
                    CookModeView(
                        recipe: recipe,
                        coordinator: dependencies.cookModeCoordinator,
                        dependencies: dependencies
                    )
                }
            }
        }
        .sheet(item: $sharedImportRequest, onDismiss: acknowledgeActiveShareImport) { request in
            ImporterView(
                dependencies: dependencies,
                initialURL: request.initialURL,
                initialText: request.initialText,
                preparedRecipe: request.preparedRecipe,
                preparedSourceInfo: request.preparedSourceInfo,
                destinationRecipeID: request.destinationRecipeID,
                onSuccessfulSave: completeActiveDurableImport
            )
            .appSheetSizing(.large)
        }
        .sheet(isPresented: $showingDesktopProfileSheet) {
            NavigationStack {
                if let user = currentUserSession.currentUser {
                    UserProfileView(user: user, dependencies: dependencies)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", systemImage: "checkmark") {
                                    showingDesktopProfileSheet = false
                                }
                            }
                        }
                }
            }
            .appSheetSizing(.large)
        }
        .tint(.cauldronOrange)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToConnections)) { _ in
            // Switch to Friends tab when connection notification is tapped
            AppLogger.general.info("📍 Switching to Friends tab from notification")
            selectedTab = .sharing
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToReferralProfile)) { _ in
            AppLogger.general.info("📍 Switching to Friends tab for referral profile navigation")
            selectedTab = .sharing
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSharedContent"))) { notification in
            if let contentWrapper = notification.object as? ContentView.SharedContentWrapper {
                AppLogger.general.info("📍 Navigating to shared content in Search tab")
                navigateToSharedContent(contentWrapper)
            }
        }
        .task(id: pendingSharedContent?.id) {
            deliverPendingSharedContentIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToSearchTab"))) { _ in
            // Switch to Search tab when "Find people to add" is tapped from Friends empty state
            AppLogger.general.info("📍 Switching to Search tab to find people")
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecipeImportURL)) { notification in
            guard let url = notification.object as? URL else { return }
            guard sharedImportRequest == nil else {
                AppLogger.general.debug("Ignoring duplicate import URL notification while an import is already open")
                return
            }
            if ShareExtensionImportStore.pendingTransportItem() != nil {
                AppLogger.general.info("📥 Durable Share Extension handoff supersedes URL notification")
                openPendingImporterIfNeeded()
                return
            }
            AppLogger.general.info("📥 Opening importer from Share Extension URL: \(url.absoluteString)")
            openImporter(with: url, acknowledgement: .url(url))
        }
        .task {
            if !didCheckInitialPendingImport {
                didCheckInitialPendingImport = true
                openPendingImporterIfNeeded()
            }
            scheduleSidebarCollectionsRefresh(delayNanoseconds: 0)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            openPendingImporterIfNeeded()
            scheduleSidebarCollectionsRefresh()
            Task {
                await dependencies.cookModeCoordinator.reconcileExternalState()
                await openPendingRecipeIntentIfNeeded()
                openPendingVisualRecipeSearchIfNeeded()
            }
        }
        .onChange(of: horizontalSizeClass) {
            scheduleSidebarCollectionsRefresh()
        }
        .onChange(of: selectedTab) { _, newTab in
            guard isRegularWidthLayout else { return }

            switch newTab {
            case .collection:
                scheduleSidebarCollectionsRefresh()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionMetadataChanged)) { notification in
            applyOptimisticSidebarCollectionUpdate(notification)
            scheduleSidebarCollectionsRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionUpdated)) { _ in
            scheduleSidebarCollectionsRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionRecipesChanged)) { _ in
            scheduleSidebarCollectionsRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionDeleted)) { _ in
            scheduleSidebarCollectionsRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CollectionAdded"))) { notification in
            applyOptimisticSidebarCollectionInsert(notification)
            scheduleSidebarCollectionsRefresh()
        }
        .toast(
            isShowing: Binding(
                get: { dependencies.cookModeCoordinator.showRecipeDeletedToast },
                set: { dependencies.cookModeCoordinator.showRecipeDeletedToast = $0 }
            ),
            icon: "trash.fill",
            message: "Recipe was deleted"
        )
        .toast(
            isShowing: $showSharedRecipeSavedToast,
            icon: "checkmark.circle.fill",
            message: "Recipe imported from share sheet"
        )
    }

    private var appIntentAwareScaffold: some View {
        tabScaffoldWithAccessory
            .task {
                await openPendingRecipeIntentIfNeeded()
                openPendingVisualRecipeSearchIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRecipeFromIntent)) { _ in
                Task { await openPendingRecipeIntentIfNeeded() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openVisualRecipeSearch)) { _ in
                openPendingVisualRecipeSearchIfNeeded()
            }
            .onReceive(Publishers.Merge3(
                NotificationCenter.default.publisher(for: .recipeAdded),
                NotificationCenter.default.publisher(for: NSNotification.Name("RecipeUpdated")),
                NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))
            )) { _ in
                RecipeSpotlightIndexer.shared.scheduleReconciliation()
            }
    }

    private static func initialSelectedTab() -> AppTab {
        #if DEBUG
        switch RuntimeEnvironment.screenshotTab {
        case "groceries":
            return .groceries
        case "friends", "sharing":
            return .sharing
        case "search":
            return .search
        case "collections":
            return .collections
        default:
            return .cook
        }
        #else
        return .cook
        #endif
    }

    @ViewBuilder
    private var tabScaffoldWithAccessory: some View {
        if #available(iOS 26.1, macCatalyst 26.1, *) {
            tabScaffold
                // On iPad, this enables the native sidebar-based tab presentation.
                // On iPhone, it keeps standard tab bar behavior.
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: isCookModeActive) {
                    cookModeAccessory
                }
        } else {
            tabScaffold
                // On iPad, this enables the native sidebar-based tab presentation.
                // On iPhone, it keeps standard tab bar behavior.
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    if isCookModeActive {
                        cookModeAccessory
                    }
                }
        }
    }

    private var cookModeAccessory: some View {
        CookModeBanner(coordinator: dependencies.cookModeCoordinator)
            .contentShape(Rectangle())
            .onTapGesture {
                dependencies.cookModeCoordinator.expandToFullScreen()
            }
    }

    @MainActor
    private func deliverPendingSharedContentIfNeeded() {
        guard let contentWrapper = pendingSharedContent else { return }
        AppLogger.general.info("📍 Delivering deferred shared content route")
        navigateToSharedContent(contentWrapper)
        pendingSharedContent = nil
    }

    @MainActor
    private func navigateToSharedContent(_ contentWrapper: ContentView.SharedContentWrapper) {
        selectedTab = .search

        // Reset path first to ensure clean navigation
        searchNavigationPath = NavigationPath()

        // Push content based on type
        switch contentWrapper.content {
        case .recipe(let recipe, _):
            searchNavigationPath.append(recipe)
        case .profile(let user):
            searchNavigationPath.append(user)
        case .collection(let collection, _):
            searchNavigationPath.append(collection)
        }
    }

    @MainActor
    private func openPendingRecipeIntentIfNeeded() async {
        guard !isOpeningRecipeIntent else { return }
        isOpeningRecipeIntent = true
        defer { isOpeningRecipeIntent = false }

        while let recipeID = RecipeIntentNavigationStore.pendingRecipeID() {
            do {
                guard let recipe = try await RecipeIntentProvider.shared.recipe(id: recipeID) else {
                    _ = RecipeIntentNavigationStore.consume(expectedRecipeID: recipeID)
                    continue
                }
                guard RecipeIntentNavigationStore.consume(expectedRecipeID: recipeID) != nil else {
                    // A newer route replaced this one while it was resolving.
                    continue
                }
                selectedTab = .search
                searchNavigationPath = NavigationPath()
                searchNavigationPath.append(recipe)
            } catch {
                AppLogger.general.error("Unable to open recipe from App Intent: \(error.localizedDescription)")
                // Drain a newer request if one replaced the failing route. Keep
                // the current route durable so a later activation can retry it.
                guard RecipeIntentNavigationStore.pendingRecipeID() != recipeID else {
                    return
                }
            }
        }
    }

    @MainActor
    private func openPendingVisualRecipeSearchIfNeeded() {
        guard RecipeIntentNavigationStore.hasPendingVisualSearch() else { return }
        let recipeIDs = RecipeIntentNavigationStore.pendingVisualSearch()
        guard RecipeIntentNavigationStore.consumeVisualSearch(expectedRecipeIDs: recipeIDs) else {
            return
        }
        selectedTab = .search
        searchNavigationPath = NavigationPath()
        searchNavigationPath.append(VisualRecipeSearchRoute(recipeIDs: recipeIDs))
    }

    private var tabScaffold: some View {
        TabView(selection: selectedTabBinding) {
            Tab("Cook", systemImage: "flame.fill", value: .cook) {
                CookTabView(dependencies: dependencies, preloadedData: preloadedData)
            }

            Tab("Groceries", systemImage: "cart.fill", value: .groceries) {
                GroceriesView(
                    dependencies: dependencies,
                    isActive: selectedTab == .groceries
                )
            }

            Tab("Friends", systemImage: "person.2.fill", value: .sharing) {
                FriendsTabView(dependencies: dependencies)
            }
            .badge(connectionManager.pendingRequestsCount)

            if isRegularWidthLayout {
                Tab("Collections", systemImage: "folder.fill", value: .collections) {
                    NavigationStack {
                        CollectionsListView(dependencies: dependencies)
                    }
                }
            }

            if isRegularWidthLayout {
                if !featuredSidebarCollections.isEmpty {
                    TabSection {
                        ForEach(featuredSidebarCollections, id: \.id) { collection in
                            Tab(
                                collectionSidebarLabel(for: collection),
                                systemImage: collectionSidebarSystemImage(for: collection),
                                value: Optional(AppTab.collection(collection.id))
                            ) {
                                NavigationStack {
                                    CollectionDetailView(collection: collection, dependencies: dependencies)
                                }
                            }
                        }
                    } header: {
                        Text("Collections")
                    }
                    .defaultVisibility(.hidden, for: .tabBar)
                }
            }

            #if targetEnvironment(macCatalyst)
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchTabView(
                    dependencies: dependencies,
                    navigationPath: $searchNavigationPath,
                    isActive: selectedTab == .search
                )
            }
            #else
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchTabView(
                    dependencies: dependencies,
                    navigationPath: $searchNavigationPath,
                    isActive: selectedTab == .search
                )
            }
            #endif
        }
        .tabViewSidebarBottomBar {
            if RuntimeEnvironment.prefersDesktopWorkspace,
               let user = currentUserSession.currentUser {
                Button {
                    showingDesktopProfileSheet = true
                } label: {
                    HStack(spacing: DesktopProfileLayout.contentSpacing) {
                        ProfileAvatar(
                            user: user,
                            size: DesktopProfileLayout.avatarSize,
                            dependencies: dependencies
                        )
                            .accessibilityHidden(true)
                        Text(user.displayName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: DesktopProfileLayout.rowHeight,
                            maxHeight: DesktopProfileLayout.rowHeight,
                            alignment: .leading
                        )
                        .contentShape(.rect)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(user.displayName), profile and settings")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesktopProfileLayout.horizontalInset)
                .padding(.bottom, DesktopProfileLayout.bottomInset)
                .foregroundStyle(.secondary)
                .accessibilityHint("Opens your profile and app settings")
            }
        }
        // The adaptive tab container owns Catalyst's native toolbar. Remove
        // its redundant app-title item here so feature toolbar controls stay.
        .modifier(DesktopToolbarTitleRemovalModifier())
    }

    private func openPendingImporterIfNeeded() {
        guard !isSavingPreparedSharedRecipe,
              !isIngestingShareTransport,
              sharedImportRequest == nil else {
            return
        }

        if let transportItem = ShareExtensionImportStore.pendingTransportItem() {
            isIngestingShareTransport = true
            Task {
                await ingestShareTransportItem(transportItem)
            }
            return
        }

        if let prepared = ShareExtensionImportStore.pendingPreparedRecipe() {
            AppLogger.general.info("📥 Found pending prepared Share Extension recipe payload")
            isSavingPreparedSharedRecipe = true
            Task {
                await autoSavePreparedSharedRecipe(prepared)
            }
            return
        }

        if let pendingText = ShareExtensionImportStore.pendingRecipeText() {
            AppLogger.general.info("📥 Found pending Share Extension text")
            openImporter(withText: pendingText, acknowledgement: .text(pendingText))
            return
        }

        guard let pendingURL = ShareExtensionImportStore.pendingRecipeURL() else {
            return
        }

        AppLogger.general.info("📥 Found pending Share Extension URL: \(pendingURL.absoluteString)")
        openImporter(with: pendingURL, acknowledgement: .url(pendingURL))
    }

    @MainActor
    private func ingestShareTransportItem(_ item: ShareExtensionInboxItem) async {
        defer { isIngestingShareTransport = false }

        do {
            let job = try await dependencies.recipeImportInboxStore.ingest(item)
            ShareExtensionImportStore.acknowledgeTransportItem(id: item.id)

            if let payloadData = item.preparedPayload,
               let prepared = ShareExtensionImportStore.preparedRecipe(from: payloadData) {
                let canonical = await prepared.canonicalized(using: dependencies.textParser)
                _ = try await dependencies.recipeImportInboxStore.transition(id: job.id, to: .needsReview)
                openPreparedImporter(
                    recipe: canonical.recipe,
                    sourceInfo: canonical.sourceInfo,
                    acknowledgement: .durableJob(job.id)
                )
                return
            }

            if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty,
               ShareExtensionImportStore.plainTextRecipeShouldTakePrecedenceOverURL(text) {
                _ = try await dependencies.recipeImportInboxStore.transition(id: job.id, to: .needsReview)
                openImporter(withText: text, acknowledgement: .durableJob(job.id))
                return
            }

            if let urlString = item.urlString,
               let url = URL(string: urlString),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                _ = try await dependencies.recipeImportInboxStore.transition(id: job.id, to: .needsReview)
                openImporter(with: url, acknowledgement: .durableJob(job.id))
                return
            }

            if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                _ = try await dependencies.recipeImportInboxStore.transition(id: job.id, to: .needsReview)
                openImporter(withText: text, acknowledgement: .durableJob(job.id))
                return
            }

            _ = try await dependencies.recipeImportInboxStore.transition(
                id: job.id,
                to: .failed,
                errorCategory: "invalidPayload"
            )
            scheduleNextPendingImport()
        } catch {
            // The cross-process handoff remains untouched until durable app
            // persistence succeeds, so relaunching can retry without data loss.
            AppLogger.general.error("Failed to persist shared import handoff: \(error.localizedDescription)")
        }
    }

    private func openImporter(with url: URL, acknowledgement: ShareImportAcknowledgement? = nil) {
        selectedTab = .cook
        activeShareImportAcknowledgement = acknowledgement
        sharedImportRequest = SharedImportRequest(
            initialURL: url,
            initialText: nil,
            preparedRecipe: nil,
            preparedSourceInfo: nil,
            destinationRecipeID: acknowledgement?.durableJobID
        )
    }

    private func openImporter(withText text: String, acknowledgement: ShareImportAcknowledgement? = nil) {
        selectedTab = .cook
        activeShareImportAcknowledgement = acknowledgement
        sharedImportRequest = SharedImportRequest(
            initialURL: nil,
            initialText: text,
            preparedRecipe: nil,
            preparedSourceInfo: nil,
            destinationRecipeID: acknowledgement?.durableJobID
        )
    }

    private func openPreparedImporter(
        recipe: Recipe,
        sourceInfo: String,
        acknowledgement: ShareImportAcknowledgement? = nil
    ) {
        selectedTab = .cook
        activeShareImportAcknowledgement = acknowledgement
        sharedImportRequest = SharedImportRequest(
            initialURL: nil,
            initialText: nil,
            preparedRecipe: recipe,
            preparedSourceInfo: sourceInfo,
            destinationRecipeID: acknowledgement?.durableJobID
        )
    }

    @MainActor
    private func autoSavePreparedSharedRecipe(_ pending: ShareExtensionImportStore.PendingPreparedSharedRecipe) async {
        defer {
            isSavingPreparedSharedRecipe = false
            scheduleNextPendingImport()
        }
        let prepared = await pending.preparedRecipe.canonicalized(using: dependencies.textParser)
        let recipeForImport = prepared.recipe

        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("❌ Cannot auto-save prepared share recipe without a current user")
            openPreparedImporter(
                recipe: recipeForImport,
                sourceInfo: prepared.sourceInfo,
                acknowledgement: .prepared(pending.payloadData)
            )
            return
        }

        let recipeToSave = ImportedRecipeSaveBuilder.recipeForSave(from: recipeForImport, userId: userId)

        do {
            try await dependencies.recipeRepository.create(recipeToSave)
            Task {
                guard let stagedImage = await ImportedRecipeSaveBuilder.stageRemoteImage(
                    for: recipeToSave,
                    imageManager: dependencies.imageManager
                ), stagedImage.expectedModificationDate == nil else { return }
                guard CurrentUserSession.shared.userId == userId else { return }
                guard let savedImage = try? await dependencies.imageManager.saveDownloadedImageDataWithToken(
                    stagedImage.data,
                    recipeId: recipeToSave.id,
                    expectedModificationDate: stagedImage.expectedModificationDate
                ) else { return }
                let localizedImageURL = await dependencies.imageManager.imageURL(for: savedImage.filename)
                let promotedModificationDate = savedImage.modificationDate
                guard CurrentUserSession.shared.userId == userId else {
                    await dependencies.imageManager.deleteImageIfUnchanged(
                        recipeId: recipeToSave.id,
                        modificationDate: promotedModificationDate
                    )
                    return
                }
                do {
                    let promoted = try await dependencies.recipeRepository.promoteImportedImageIfCurrent(
                        recipeId: recipeToSave.id,
                        ownerId: userId,
                        expectedUpdatedAt: recipeToSave.updatedAt,
                        expectedImageURL: recipeToSave.imageURL,
                        localizedImageURL: localizedImageURL
                    )
                    guard promoted else {
                        await dependencies.imageManager.deleteImageIfUnchanged(
                            recipeId: recipeToSave.id,
                            modificationDate: promotedModificationDate
                        )
                        return
                    }
                } catch {
                    await dependencies.imageManager.deleteImageIfUnchanged(
                        recipeId: recipeToSave.id,
                        modificationDate: promotedModificationDate
                    )
                }
            }
            AppLogger.general.info("✅ Auto-saved prepared share recipe: \(recipeToSave.title)")
            ShareExtensionImportStore.acknowledgePreparedRecipe(matching: pending.payloadData)
            NotificationCenter.default.post(name: .recipeAdded, object: recipeToSave.id)
            selectedTab = .cook
            showSharedRecipeSavedToast = true
        } catch {
            AppLogger.general.error("❌ Failed to auto-save prepared share recipe: \(error.localizedDescription)")
            openPreparedImporter(
                recipe: recipeForImport,
                sourceInfo: prepared.sourceInfo,
                acknowledgement: .prepared(pending.payloadData)
            )
        }
    }

    private func acknowledgeActiveShareImport() {
        guard let acknowledgement = activeShareImportAcknowledgement else {
            return
        }

        switch acknowledgement {
        case .prepared(let payloadData):
            ShareExtensionImportStore.acknowledgePreparedRecipe(matching: payloadData)
        case .text(let text):
            ShareExtensionImportStore.acknowledgePendingRecipeText(matching: text)
        case .url(let url):
            ShareExtensionImportStore.acknowledgePendingRecipeURL(matching: url)
        case .durableJob:
            // Dismissal is not completion. The durable inbox entry remains
            // until a successful recipe save or an explicit discard.
            break
        }

        activeShareImportAcknowledgement = nil
        scheduleNextPendingImport()
    }

    private func completeActiveDurableImport() async -> Bool {
        guard case .durableJob(let id) = activeShareImportAcknowledgement else { return true }
        do {
            try await dependencies.recipeImportInboxStore.complete(id: id)
            return true
        } catch {
            AppLogger.general.error("Failed to mark import complete: \(error.localizedDescription)")
            return false
        }
    }

    private func scheduleNextPendingImport() {
        Task { @MainActor in
            await Task.yield()
            openPendingImporterIfNeeded()
        }
    }

    @MainActor
    private func refreshSidebarCollections() async {
        guard isRegularWidthLayout else {
            sidebarCollections = []
            if case .collection = selectedTab {
                selectedTab = .cook
            } else if selectedTab == .collections {
                selectedTab = .cook
            }
            return
        }

        do {
            let ownedCollections = try await dependencies.collectionRepository.fetchUserCollections(
                ownerId: CurrentUserSession.shared.userId
            )

            sidebarCollections = ownedCollections.sorted { $0.updatedAt > $1.updatedAt }

            if case let .collection(collectionID) = selectedTab,
               !sidebarCollections.contains(where: { $0.id == collectionID }) {
                selectedTab = .cook
            }
        } catch {
            AppLogger.general.warning("⚠️ Failed to refresh sidebar collections: \(error.localizedDescription)")
        }
    }

    private func scheduleSidebarCollectionsRefresh(delayNanoseconds: UInt64 = 150_000_000) {
        sidebarRefreshTask?.cancel()
        sidebarRefreshTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await refreshSidebarCollections()
        }
    }

    private func collectionSidebarLabel(for collection: Collection) -> String {
        collection.name
    }

    private func collectionSidebarSystemImage(for collection: Collection) -> String {
        collection.symbolName ?? "folder.fill"
    }

    @MainActor
    private func applyOptimisticSidebarCollectionUpdate(_ notification: Notification) {
        guard isRegularWidthLayout,
              let updatedCollection = notification.userInfo?["collection"] as? Collection else {
            return
        }

        if let currentUserID = CurrentUserSession.shared.userId,
           updatedCollection.userId != currentUserID {
            return
        }

        if let existingIndex = sidebarCollections.firstIndex(where: { $0.id == updatedCollection.id }) {
            sidebarCollections[existingIndex] = updatedCollection
        }

        sidebarCollections.sort { $0.updatedAt > $1.updatedAt }
    }

    @MainActor
    private func applyOptimisticSidebarCollectionInsert(_ notification: Notification) {
        guard isRegularWidthLayout,
              let insertedCollection = notification.userInfo?["collection"] as? Collection else {
            return
        }

        if let currentUserID = CurrentUserSession.shared.userId,
           insertedCollection.userId != currentUserID {
            return
        }

        guard !sidebarCollections.contains(where: { $0.id == insertedCollection.id }) else {
            return
        }

        sidebarCollections.insert(insertedCollection, at: 0)
        sidebarCollections.sort { $0.updatedAt > $1.updatedAt }
    }
}

private struct DesktopToolbarTitleRemovalModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if RuntimeEnvironment.prefersDesktopWorkspace {
            #if targetEnvironment(macCatalyst)
            content
                .toolbar(removing: .title)
                .background(CatalystWindowTitleHider())
            #else
            content.toolbar(removing: .title)
            #endif
        } else {
            content
        }
    }
}

#if targetEnvironment(macCatalyst)
private struct CatalystWindowTitleHider: UIViewRepresentable {
    func makeUIView(context: Context) -> TitlebarConfigurationView {
        TitlebarConfigurationView()
    }

    func updateUIView(_ uiView: TitlebarConfigurationView, context: Context) {
        uiView.configureTitlebar()
    }

    final class TitlebarConfigurationView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureTitlebar()
        }

        func configureTitlebar() {
            guard let titlebar = window?.windowScene?.titlebar else { return }
            titlebar.titleVisibility = .hidden
            titlebar.toolbarStyle = .unifiedCompact
        }
    }
}
#endif

#Preview {
    MainTabView(dependencies: .preview(), preloadedData: nil, pendingSharedContent: .constant(nil))
}
