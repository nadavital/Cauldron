//
//  UserProfileView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import UniformTypeIdentifiers

private struct ProfileRecipeSearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $text, prompt: "Search recipes")
        } else {
            content
        }
    }
}

private actor ArchiveRestoreProgressTracker {
    private var latestReport: LibraryArchiveService.RestoreReport?

    func record(_ report: LibraryArchiveService.RestoreReport) {
        latestReport = report
    }

    func latest() -> LibraryArchiveService.RestoreReport? {
        latestReport
    }
}

/// User profile view - displays user information and manages connections
struct UserProfileView: View {
    let user: User
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: UserProfileViewModel
    @StateObject private var currentUserSession = CurrentUserSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditProfile = false
    @State private var hasLoadedInitialData = false
    
    // External sharing
    @State private var shareLink: ShareableLink?
    @State private var isGeneratingShareLink = false

    // Tier & icons
    @State private var showTierRoadmap = false
    @State private var showAppIconPicker = false
    @StateObject private var appIconManager = AppIconManager.shared

    // Referral
    @StateObject private var referralManager = ReferralManager.shared
    @State private var codeCopied = false

    // Library backup and recovery
    @State private var archiveDocument: LibraryArchiveDocument?
    @State private var showingArchiveExporter = false
    @State private var showingArchiveImporter = false
    @State private var isPreparingArchive = false
    @State private var isRestoringArchive = false
    @State private var archiveStatusMessage: String?
    @Namespace private var recipeTransition

    init(user: User, dependencies: DependencyContainer) {
        self.user = user
        _viewModel = State(initialValue: UserProfileViewModel(
            user: user,
            dependencies: dependencies
        ))
    }

    // Use the live current user from session if viewing own profile
    // This enables optimistic UI updates to show immediately
    private var displayUser: User {
        if viewModel.isCurrentUser, let currentUser = currentUserSession.currentUser {
            return currentUser
        }
        return user
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 2) {
                VStack(spacing: Theme.Spacing.lg) {
                    // Profile Header
                    profileHeader

                    if viewModel.isCurrentUser {
                        profileQuickActions
                    }

                    // Connection Management Section
                    if !viewModel.isCurrentUser {
                        connectionSection
                    }

                    // Recipes Section
                    recipesSection

                    // Collections Section (only show if user has collections OR still loading the first time)
                    if !viewModel.userCollections.isEmpty || viewModel.isColdLoadingCollections || RuntimeEnvironment.forceSkeletonLoading {
                        collectionsSection
                    }
                }
            }
            .padding()
        }
        .appPageChrome()
        .frame(minWidth: catalystMinimumWidth, minHeight: catalystMinimumHeight)
        .navigationTitle(displayUser.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ProfileRecipeSearchModifier(
            isEnabled: !viewModel.isCurrentUser,
            text: $viewModel.searchText
        ))
        .refreshable {
            await viewModel.refreshProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
            // Only refresh if viewing own profile
            if viewModel.isCurrentUser {
                Task {
                    await viewModel.loadUserRecipes()
                }
            }
        }
        .onAppear {
            // Only load initial data once - the viewModel's cache will handle subsequent requests
            if !hasLoadedInitialData {
                hasLoadedInitialData = true
                Task {
                    await viewModel.loadProfileData()
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $showingEditProfile) {
            ProfileEditView(dependencies: viewModel.dependencies)
                .appSheetSizing(.large)
        }
        .sheet(item: $shareLink) { link in
            ShareSheet(items: [link])
        }
        .sheet(isPresented: $showTierRoadmap) {
            TierRoadmapView(
                currentTier: viewModel.userTier,
                recipeCount: viewModel.userRecipeCount,
                dependencies: viewModel.dependencies,
                showsAddRecipeActions: viewModel.isCurrentUser
            )
                .appSheetSizing(.standard)
        }
        .sheet(isPresented: $showAppIconPicker) {
            AppIconPickerView()
                .appSheetSizing(.large)
        }
        .fileExporter(
            isPresented: $showingArchiveExporter,
            document: archiveDocument,
            contentType: .cauldronLibraryArchive,
            defaultFilename: "Cauldron Library.cauldron"
        ) { result in
            archiveDocument = nil
            if case .failure(let error) = result,
               !Self.archivePickerWasCancelled(error) {
                archiveStatusMessage = "Cauldron couldn't export your library. Your recipes were not changed."
            }
        }
        .fileImporter(
            isPresented: $showingArchiveImporter,
            // The legacy app.cauldron.library-archive identifier is imported
            // in Info.plist as JSON, so .json also admits existing backups.
            allowedContentTypes: [.cauldronLibraryArchive, .json],
            allowsMultipleSelection: false
        ) { result in
            Task { await restoreArchive(result) }
        }
        .alert("Library Backup", isPresented: Binding(
            get: { archiveStatusMessage != nil },
            set: { if !$0 { archiveStatusMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(archiveStatusMessage ?? "")
        }
        .toolbar {
            if viewModel.isCurrentUser {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await generateShareLink() }
                    } label: {
                        if isGeneratingShareLink {
                            ProgressView()
                        } else {
                            Label("Share Profile", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isGeneratingShareLink || !viewModel.canShareProfile)
                    .accessibilityLabel("Share profile")
                }
            }
        }
    }

    private var profileQuickActions: some View {
        GlassEffectContainer(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                profileActionButton("Edit", systemImage: "pencil") {
                    showingEditProfile = true
                }

                profileActionButton("Invite", systemImage: "person.badge.plus") {
                    shareWithFriends()
                }

                if appIconManager.supportsAlternateIcons {
                    profileActionButton("App Icons", systemImage: "app.dashed") {
                        showAppIconPicker = true
                    }
                } else {
                    profileActionButton("Progress", systemImage: viewModel.userTier.icon) {
                        showTierRoadmap = true
                    }
                }
            }
        }
    }

    private func profileActionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
        }
        .buttonStyle(.glass)
    }

    private var profileHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ProfileAvatar(user: displayUser, size: 70, dependencies: viewModel.dependencies)
                profileIdentityInfo
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ProfileAvatar(user: displayUser, size: 70, dependencies: viewModel.dependencies)
                profileIdentityInfo
            }
        }
        .padding()
        .glassCard(cornerRadius: 16)
    }

    private var profileIdentityInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayUser.displayName)
                    .font(.system(.title2, design: .serif).weight(.bold))

            }

            Text("@\(displayUser.username)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                profileRelationshipRow
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    profileTierControl
                    profileConnectionControl
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileRelationshipRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            profileTierControl
            profileConnectionControl
        }
    }

    @ViewBuilder
    private var profileTierControl: some View {
        Button {
            showTierRoadmap = true
        } label: {
            TierBadgeView(tier: viewModel.userTier, style: .standard)
        }
        .accessibilityLabel("View tier progress")
    }

    @ViewBuilder
    private var profileConnectionControl: some View {
        if viewModel.isCurrentUser {
            NavigationLink(destination: ConnectionsView(dependencies: viewModel.dependencies)) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Text("\(viewModel.connections.count) \(viewModel.connections.count == 1 ? "friend" : "friends")")
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(Color.cauldronOrange)
            }
        } else {
            connectionActionBadge
        }
    }

    private var catalystMinimumWidth: CGFloat? {
        #if targetEnvironment(macCatalyst)
        680
        #else
        nil
        #endif
    }

    private var catalystMinimumHeight: CGFloat? {
        #if targetEnvironment(macCatalyst)
        640
        #else
        nil
        #endif
    }

    // MARK: - Library Backups

    private var libraryBackupSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeaderLabel(title: "Library Backups", systemImage: "externaldrive")

            Button {
                Task { await prepareArchiveExport() }
            } label: {
                settingsRow(
                    title: isPreparingArchive ? "Preparing Backup…" : "Back Up Library",
                    detail: "Recipes, collections, and saved images",
                    systemImage: "square.and.arrow.up",
                    showsProgress: isPreparingArchive
                )
            }
            .buttonStyle(.plain)
            .disabled(isPreparingArchive || isRestoringArchive)
            .accessibilityHint("Creates a portable Cauldron library archive")

            Divider()

            Button {
                showingArchiveImporter = true
            } label: {
                settingsRow(
                    title: isRestoringArchive ? "Restoring Backup…" : "Restore Library Backup",
                    detail: "Merge a backup without removing newer items",
                    systemImage: "square.and.arrow.down",
                    showsProgress: isRestoringArchive
                )
            }
            .buttonStyle(.plain)
            .disabled(isPreparingArchive || isRestoringArchive)
            .accessibilityHint("Selects a Cauldron library archive to merge into this account")
        }
        .padding()
        .glassCard(cornerRadius: 16)
    }

    private func settingsRow(
        title: String,
        detail: String,
        systemImage: String,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.cauldronOrange)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    @MainActor
    private func prepareArchiveExport() async {
        guard !isPreparingArchive && !isRestoringArchive else { return }

        guard let userID = currentUserSession.userId else {
            archiveStatusMessage = "Sign in to iCloud before backing up your library."
            return
        }

        isPreparingArchive = true
        defer { isPreparingArchive = false }
        do {
            guard let accountScope = currentUserSession.syncOperationAccountScope(ownerID: userID) else {
                throw LibraryArchiveService.ArchiveError.accountAuthorizationUnavailable
            }
            let data = try await viewModel.dependencies.libraryArchiveService.export(ownerID: userID)
            guard currentUserSession.syncOperationAccountScope(ownerID: userID) == accountScope else {
                throw LibraryArchiveService.ArchiveError.accountAuthorizationChanged
            }
            archiveDocument = LibraryArchiveDocument(data: data)
            showingArchiveExporter = true
        } catch {
            archiveStatusMessage = "Cauldron couldn't prepare your library backup. Your recipes were not changed."
        }
    }

    @MainActor
    private func restoreArchive(_ result: Result<[URL], Error>) async {
        guard !isPreparingArchive && !isRestoringArchive else { return }

        if case .failure(let error) = result {
            guard !Self.archivePickerWasCancelled(error) else { return }
            archiveStatusMessage = "Cauldron couldn't open that backup. Your existing library was not changed."
            return
        }

        guard let userID = currentUserSession.userId else {
            archiveStatusMessage = "Sign in to iCloud before restoring a library backup."
            return
        }

        isRestoringArchive = true
        defer { isRestoringArchive = false }
        let progressTracker = ArchiveRestoreProgressTracker()
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try await Task.detached(priority: .userInitiated) {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize <= LibraryArchiveService.defaultMaximumArchiveBytes else {
                    throw CocoaError(.fileReadTooLarge)
                }
                return try Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            let report = try await viewModel.dependencies.libraryArchiveService.restore(
                data,
                ownerID: userID,
                progress: { report in
                    await progressTracker.record(report)
                }
            )
            archiveStatusMessage = Self.archiveRestoreMessage(report)
            await viewModel.refreshProfile()
        } catch {
            if let partialReport = await progressTracker.latest(),
               Self.archiveRestoreDidChangeLibrary(partialReport) {
                archiveStatusMessage = Self.archivePartialRestoreMessage(partialReport)
                await viewModel.refreshProfile()
            } else {
                archiveStatusMessage = "Cauldron couldn't restore that backup. Your existing library was not removed."
            }
        }
    }

    nonisolated static func archivePickerWasCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain &&
            nsError.code == CocoaError.Code.userCancelled.rawValue
    }

    nonisolated static func archiveRestoreMessage(_ report: LibraryArchiveService.RestoreReport) -> String {
        let added = report.recipesInserted + report.collectionsInserted
        let updated = report.recipesUpdated + report.collectionsUpdated
        let kept = report.recipesKept + report.collectionsKept
        let skippedMemberships = report.membershipsSkipped
        var message = "Restore complete: \(added) added, \(updated) updated, and \(kept) kept."
        if skippedMemberships > 0 {
            message += " \(skippedMemberships) collection links were skipped because their recipes were not in this account."
        }
        return message
    }

    nonisolated static func archiveRestoreDidChangeLibrary(
        _ report: LibraryArchiveService.RestoreReport
    ) -> Bool {
        report.recipesInserted + report.recipesUpdated +
            report.collectionsInserted + report.collectionsUpdated +
            report.imagesRestored > 0
    }

    nonisolated static func archivePartialRestoreMessage(
        _ report: LibraryArchiveService.RestoreReport
    ) -> String {
        let added = report.recipesInserted + report.collectionsInserted
        let updated = report.recipesUpdated + report.collectionsUpdated
        return "Restore stopped after partially completing: \(added) added and \(updated) updated. " +
            "Your existing library was not removed, and it is safe to select the same backup again."
    }

    // MARK: - App Icons Section

    private var rewardsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Header
            HStack {
                Text("App Icons")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Button {
                    showAppIconPicker = true
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Text("\(appIconManager.unlockedIcons.count)/\(appIconManager.availableIcons.count)")
                            .font(.caption)
                        Text("View All")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.cauldronOrange)
                }
            }

            // Horizontal scrolling icons with progress
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(appIconManager.availableIcons) { theme in
                        iconCellWithProgress(theme: theme)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
        .padding()
        .glassCard(cornerRadius: 16)
    }

    private func iconCellWithProgress(theme: AppIconTheme) -> some View {
        let isSelected = appIconManager.currentTheme.id == theme.id
        let isUnlocked = appIconManager.isUnlocked(theme)
        let progress = iconUnlockProgress(for: theme)

        return Button {
            showAppIconPicker = true
        } label: {
            VStack(spacing: 6) {
                // Icon with overlay
                ZStack {
                    Image(iconPreviewAssetName(for: theme))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .cornerRadius(Theme.Radius.card)
                        .blur(radius: isUnlocked ? 0 : 3)
                        .opacity(isUnlocked ? 1.0 : 0.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .stroke(isSelected ? Color.cauldronOrange : Color.clear, lineWidth: 2)
                        )

                    // Checkmark for selected
                    if isSelected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.cauldronOrange)
                                    .background(Circle().fill(Color.appSurface).padding(1))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .frame(width: 56, height: 56)
                    }
                }

                // Progress bar for locked icons
                if !isUnlocked {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.cauldronOrange)
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(width: 56, height: 4)
                } else {
                    // Spacer for consistent height
                    Color.clear.frame(width: 56, height: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Calculate progress towards unlocking an icon (0.0 to 1.0)
    private func iconUnlockProgress(for theme: AppIconTheme) -> Double {
        guard let unlock = IconUnlock.unlock(for: theme.id) else { return 1.0 }

        let required = unlock.requiredReferrals
        if required == 0 { return 1.0 }

        let current = referralManager.referralCount
        return min(1.0, Double(current) / Double(required))
    }

    private func shareWithFriends() {
        guard let user = currentUserSession.currentUser else { return }
        let shareURL = referralManager.getShareURL(for: user)
        let shareText = referralManager.getShareText(for: user)
        // Setting shareLink triggers the sheet via .sheet(item:)
        shareLink = ShareableLink(
            url: shareURL,
            previewText: shareText
        )
    }

    private var referralQuickSection: some View {
        Group {
            if let user = currentUserSession.currentUser {
                let code = referralManager.generateReferralCode(for: user)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Referral code")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.cauldronOrange)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = code
                            withAnimation {
                                codeCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    codeCopied = false
                                }
                            }
                        } label: {
                            Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(codeCopied ? .green : .cauldronOrange)
                        }
                        .buttonStyle(.plain)
                    }

                    if codeCopied {
                        Text("Copied!")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                }
                .padding(.top, 2)
            }
        }
    }

    private func iconPreviewAssetName(for theme: AppIconTheme) -> String {
        switch theme.id {
        case "default":
            return "BrandMarks/CauldronIcon"
        case "wicked":
            return "IconPreviews/IconPreviewWicked"
        case "goodwitch":
            return "IconPreviews/IconPreviewGoodWitch"
        case "maleficent":
            return "IconPreviews/IconPreviewMaleficent"
        case "ursula":
            return "IconPreviews/IconPreviewUrsula"
        case "agatha":
            return "IconPreviews/IconPreviewAgatha"
        case "scarletwitch":
            return "IconPreviews/IconPreviewScarletWitch"
        case "lion":
            return "IconPreviews/IconPreviewLion"
        case "serpent":
            return "IconPreviews/IconPreviewSerpent"
        case "badger":
            return "IconPreviews/IconPreviewBadger"
        case "eagle":
            return "IconPreviews/IconPreviewEagle"
        default:
            return "BrandMarks/CauldronIcon"
        }
    }

    // MARK: - Connection Action Badge (interactive)

    @ViewBuilder
    private var connectionActionBadge: some View {
        if viewModel.isProcessing || viewModel.isLoadingConnectionState {
            ProgressView()
                .scaleEffect(0.8)
        } else {
            switch viewModel.connectionState {
            case .connected:
                // Friends badge - tap to show menu with remove option
                Menu {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.removeConnection()
                        }
                    } label: {
                        Label("Remove Friend", systemImage: "person.badge.minus")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Friends")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(Theme.Radius.small)
                }

            case .pendingOutgoing:
                // Pending badge - tap to cancel
                Menu {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.cancelConnectionRequest()
                        }
                    } label: {
                        Label("Cancel Request", systemImage: "xmark.circle")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text("Pending")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.cauldronOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cauldronOrange.opacity(0.15))
                    .cornerRadius(Theme.Radius.small)
                }

            case .pendingIncoming:
                // Request received badge - shown in header, actions below
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "person.badge.clock")
                        .font(.caption)
                    Text("Respond")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(Theme.Radius.small)

            case .none:
                // Add Friend badge - tap to send request
                Button {
                    Task {
                        await viewModel.sendConnectionRequest()
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "person.badge.plus")
                            .font(.caption)
                        Text("Add Friend")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.cauldronOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cauldronOrange.opacity(0.15))
                    .cornerRadius(Theme.Radius.small)
                }

            case .syncing:
                ProgressView()
                    .scaleEffect(0.8)

            case .failed:
                Button {
                    Task {
                        await viewModel.loadConnectionStatus()
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Retry")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.cauldronOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cauldronOrange.opacity(0.15))
                    .cornerRadius(Theme.Radius.small)
                }

            case .currentUser:
                EmptyView()
            }
        }
    }

    // MARK: - Connection Section (only for pending received - needs Accept/Reject buttons)

    @ViewBuilder
    private var connectionSection: some View {
        if viewModel.connectionState == .pendingIncoming && !viewModel.isProcessing && !viewModel.isLoadingConnectionState {
            VStack(spacing: Theme.Spacing.sm) {
                Text("\(user.displayName) wants to be friends")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        Task {
                            await viewModel.acceptConnection()
                        }
                    } label: {
                        Label("Accept", systemImage: "checkmark")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button {
                        Task {
                            await viewModel.rejectConnection()
                        }
                    } label: {
                        Label("Decline", systemImage: "xmark")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
            .glassCard(cornerRadius: 16)
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Section header
            HStack {
                SectionHeaderLabel(title: "Collections", systemImage: "folder.fill", iconColor: .purple)

                Spacer()

                if !viewModel.userCollections.isEmpty {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }

            // Content
            if RuntimeEnvironment.forceSkeletonLoading || viewModel.isColdLoadingCollections {
                CollectionCardSkeletonRail(count: 2, horizontalPadding: 0)
            } else if viewModel.userCollections.isEmpty {
                emptyCollectionsState
            } else {
                if viewModel.isLoadingCollections {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(viewModel.userCollections.prefix(10), id: \.id) { collection in
                            NavigationLink(destination: CollectionDetailView(
                                collection: collection,
                                dependencies: viewModel.dependencies,
                                initialOwner: user,
                                initialRecipeImages: viewModel.getRecipeImages(for: collection),
                                initialRecipeImageSources: viewModel.getRecipeImageSources(for: collection),
                                initialRelation: viewModel.isCurrentUser ? .owned : .unknown
                            )) {
                                CollectionCardView(
                                    collection: collection,
                                    recipeImages: viewModel.getRecipeImages(for: collection),
                                    recipeImageSources: viewModel.getRecipeImageSources(for: collection),
                                    dependencies: viewModel.dependencies
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var emptyCollectionsState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "folder")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple, Color.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text(viewModel.isCurrentUser ? "No Collections Yet" : "No Shared Collections")
                .font(.subheadline)
                .fontWeight(.medium)

            Text(viewModel.isCurrentUser ? "Create collections to organize recipes" : "\(user.displayName) hasn't shared any collections")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Section header
            HStack {
                SectionHeaderLabel(
                    title: viewModel.searchText.isEmpty ? "Recipes" : "Search Results",
                    systemImage: "book.fill"
                )

                Spacer()

                if !viewModel.filteredRecipes.isEmpty && viewModel.searchText.isEmpty {
                    NavigationLink(destination: AllProfileRecipesListView(
                        recipes: viewModel.filteredRecipes,
                        user: user,
                        dependencies: viewModel.dependencies
                    )) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundColor(.cauldronOrange)
                    }
                }
            }

            // Content
            if RuntimeEnvironment.forceSkeletonLoading || viewModel.isColdLoadingRecipes {
                if horizontalSizeClass == .regular {
                    RecipeCardSkeletonGrid(columns: RecipeLayoutMode.defaultGridColumns, count: 4)
                } else {
                    RecipeCardSkeletonRail(count: 2, horizontalPadding: 0)
                }
            } else if viewModel.filteredRecipes.isEmpty {
                emptyRecipesState
            } else {
                if viewModel.isLoadingRecipes {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if horizontalSizeClass == .regular {
                    LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: Theme.Spacing.md) {
                        ForEach(displayedRecipes, id: \.id) { sharedRecipe in
                            let transitionID = "profile-grid-\(sharedRecipe.recipe.id.uuidString)"
                            NavigationLink {
                                RecipeDetailView(
                                    recipe: sharedRecipe.recipe,
                                    dependencies: viewModel.dependencies,
                                    sharedBy: viewModel.isCurrentUser ? nil : sharedRecipe.sharedBy,
                                    sharedAt: viewModel.isCurrentUser ? nil : sharedRecipe.sharedAt
                                )
                                .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                            } label: {
                                profileRecipeCard(sharedRecipe)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: transitionID, in: recipeTransition)
                        }
                    }
                } else {
                    if viewModel.searchText.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.md) {
                                ForEach(displayedRecipes, id: \.id) { sharedRecipe in
                                    let transitionID = "profile-rail-\(sharedRecipe.recipe.id.uuidString)"
                                    NavigationLink {
                                        RecipeDetailView(
                                            recipe: sharedRecipe.recipe,
                                            dependencies: viewModel.dependencies,
                                            sharedBy: viewModel.isCurrentUser ? nil : sharedRecipe.sharedBy,
                                            sharedAt: viewModel.isCurrentUser ? nil : sharedRecipe.sharedAt
                                        )
                                        .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                                    } label: {
                                        profileRecipeCard(sharedRecipe)
                                    }
                                    .buttonStyle(.plain)
                                    .matchedTransitionSource(id: transitionID, in: recipeTransition)
                                }
                            }
                        }
                    } else {
                        // List view for search results (matches Search tab style)
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(viewModel.filteredRecipes, id: \.id) { sharedRecipe in
                                let transitionID = "profile-search-\(sharedRecipe.recipe.id.uuidString)"
                                NavigationLink {
                                    RecipeDetailView(
                                        recipe: sharedRecipe.recipe,
                                        dependencies: viewModel.dependencies,
                                        sharedBy: viewModel.isCurrentUser ? nil : sharedRecipe.sharedBy,
                                        sharedAt: viewModel.isCurrentUser ? nil : sharedRecipe.sharedAt
                                    )
                                    .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                                } label: {
                                    RecipeRowView(recipe: sharedRecipe.recipe, dependencies: viewModel.dependencies)
                                }
                                .buttonStyle(.plain)
                                .matchedTransitionSource(id: transitionID, in: recipeTransition)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func profileRecipeCard(_ sharedRecipe: SharedRecipe) -> some View {
        if viewModel.isCurrentUser {
            RecipeCardView(
                recipe: sharedRecipe.recipe,
                dependencies: viewModel.dependencies
            )
        } else {
            RecipeCardView(
                sharedRecipe: sharedRecipe,
                dependencies: viewModel.dependencies
            )
        }
    }

    private var displayedRecipes: [SharedRecipe] {
        if viewModel.searchText.isEmpty {
            return Array(viewModel.filteredRecipes.prefix(10))
        }
        return viewModel.filteredRecipes
    }

    private var emptyRecipesState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.cauldronOrange.opacity(0.2), Color.cauldronOrange.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: viewModel.searchText.isEmpty ? "book.closed" : "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cauldronOrange, Color.cauldronOrange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text(emptyStateMessage)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            if viewModel.searchText.isEmpty && !viewModel.isCurrentUser && viewModel.connectionState != .connected {
                Text("Connect with \(user.displayName) to see their recipes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var emptyStateMessage: String {
        if !viewModel.searchText.isEmpty {
            return "No recipes match '\(viewModel.searchText)'"
        } else if viewModel.isCurrentUser {
            return "You haven't saved any recipes yet"
        } else if viewModel.connectionState == .connected {
            return "\(user.displayName) hasn't shared any recipes yet"
        } else {
            return "No Public Recipes"
        }
    }

    private func generateShareLink() async {
        isGeneratingShareLink = true
        defer { isGeneratingShareLink = false }

        do {
            await viewModel.loadUserRecipes(forceRefresh: true)
            guard viewModel.canShareProfile else {
                throw ExternalShareError.invalidProfile
            }
            // Count public recipes
            let publicRecipeCount = viewModel.userRecipes.filter { $0.recipe.visibility == .publicRecipe }.count
            
            let link = try await viewModel.dependencies.externalShareService.shareProfile(
                displayUser,
                recipeCount: publicRecipeCount
            )
            shareLink = link
        } catch {
            AppLogger.general.error("Failed to generate profile share link: \(error.localizedDescription)")
            viewModel.errorMessage = "Failed to generate share link: \(error.localizedDescription)"
            viewModel.showError = true
        }
    }
}

// MARK: - All Profile Recipes List View

struct AllProfileRecipesListView: View {
    let recipes: [SharedRecipe]
    let user: User
    let dependencies: DependencyContainer
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(RecipeLayoutMode.appStorageKey) private var storedRecipeLayoutMode = RecipeLayoutMode.auto.rawValue
    @Namespace private var recipeTransition

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        return storedMode.resolved(for: horizontalSizeClass)
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }

    var body: some View {
        contentView
        .appPageChrome()
        .navigationTitle("\(user.displayName)'s Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
                    storedRecipeLayoutMode = mode.rawValue
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if usesGridRecipeLayout {
            gridContent
        } else {
            listContent
        }
    }

    private var listContent: some View {
        List {
            ForEach(recipes) { sharedRecipe in
                let transitionID = "profile-list-\(sharedRecipe.recipe.id.uuidString)"
                NavigationLink {
                    RecipeDetailView(
                        recipe: sharedRecipe.recipe,
                        dependencies: dependencies,
                        sharedBy: user.id == CurrentUserSession.shared.userId ? nil : sharedRecipe.sharedBy,
                        sharedAt: user.id == CurrentUserSession.shared.userId ? nil : sharedRecipe.sharedAt
                    )
                    .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                } label: {
                    if user.id == CurrentUserSession.shared.userId {
                        RecipeRowView(recipe: sharedRecipe.recipe, dependencies: dependencies)
                    } else {
                        SharedRecipeRowView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                    }
                }
                .matchedTransitionSource(id: transitionID, in: recipeTransition)
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: Theme.Spacing.md) {
                ForEach(recipes) { sharedRecipe in
                    let transitionID = "profile-all-grid-\(sharedRecipe.recipe.id.uuidString)"
                    NavigationLink {
                        RecipeDetailView(
                            recipe: sharedRecipe.recipe,
                            dependencies: dependencies,
                            sharedBy: user.id == CurrentUserSession.shared.userId ? nil : sharedRecipe.sharedBy,
                            sharedAt: user.id == CurrentUserSession.shared.userId ? nil : sharedRecipe.sharedAt
                        )
                        .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                    } label: {
                        if user.id == CurrentUserSession.shared.userId {
                            RecipeCardView(recipe: sharedRecipe.recipe, dependencies: dependencies)
                        } else {
                            RecipeCardView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                        }
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: transitionID, in: recipeTransition)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    NavigationStack {
        UserProfileView(
            user: User(username: "chef_julia", displayName: "Julia Child"),
            dependencies: .preview()
        )
    }
}
