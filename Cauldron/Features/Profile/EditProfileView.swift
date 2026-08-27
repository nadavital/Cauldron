//
//  EditProfileView.swift
//  Cauldron
//
//  Comprehensive profile editing view with account deletion
//

import SwiftUI

enum ProfileEditChangePolicy {
    nonisolated static func didEditBasicInfo(
        initialUser: User?,
        username: String,
        displayName: String
    ) -> Bool {
        username != initialUser?.username || displayName != initialUser?.displayName
    }
}

struct ProfileEditView: View {
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @StateObject private var userSession = CurrentUserSession.shared
    @State private var username: String
    @State private var displayName: String
    @State private var profileEmoji: String?
    @State private var profileColor: String?
    @State private var profileImage: UIImage?
    @State private var selectedAvatarType: AvatarType
    @State private var isAvatarDirty = false

    @State private var showingAvatarPicker = false
    @State private var showingImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showError = false

    private let initialUser: User?

    init(dependencies: DependencyContainer, previewUser: User? = nil) {
        self.dependencies = dependencies

        // Use preview user for SwiftUI previews, otherwise use current user (may be nil after account deletion)
        let user: User? = previewUser ?? CurrentUserSession.shared.currentUser
        self.initialUser = user

        // Initialize state from current user (use defaults if nil)
        _username = State(initialValue: user?.username ?? "")
        _displayName = State(initialValue: user?.displayName ?? "")
        _profileEmoji = State(initialValue: user?.profileEmoji)
        _profileColor = State(initialValue: user?.profileColor)

        // Determine avatar type
        if user?.profileImageURL != nil {
            _selectedAvatarType = State(initialValue: .photo)
        } else {
            _selectedAvatarType = State(initialValue: .emoji)
        }
    }

    /// The current user, preferring the live session value over the initial snapshot
    private var currentUser: User? {
        userSession.currentUser ?? initialUser
    }

    var isValid: Bool {
        username.count >= 3 && username.count <= 20 &&
        displayName.count >= 1 &&
        username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    var hasChanges: Bool {
        guard let initialUser else { return false }
        return username != initialUser.username ||
            displayName != initialUser.displayName ||
            isAvatarDirty
    }

    var body: some View {
        // If user is nil (e.g., after account deletion), show nothing - view will be dismissed
        if currentUser == nil {
            Color.clear
                .onAppear { dismiss() }
        } else {
            mainContent
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        // Guard is safe here since we check for nil in body
        let currentUser = self.currentUser!
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Profile Preview with an inline edit menu on the avatar
                    VStack(spacing: 16) {
                        ZStack(alignment: .bottomTrailing) {
                        Group {
                        // Avatar Display
                        if selectedAvatarType == .photo {
                            if let profileImage = profileImage {
                                Image(uiImage: profileImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.appSurface)
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Image(systemName: "person.crop.circle")
                                            .font(.system(size: 50))
                                            .foregroundColor(.secondary)
                                    )
                            }
                        } else {
                            Circle()
                                .fill((profileColor.flatMap { Color(hex: $0) } ?? .cauldronOrange).opacity(0.15))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Group {
                                        if let emoji = profileEmoji {
                                            Text(emoji)
                                                .font(.system(size: 50))
                                        } else {
                                            Text(displayName.isEmpty ? "?" : String(displayName.prefix(2)).uppercased())
                                                .font(.title)
                                                .fontWeight(.semibold)
                                                .foregroundColor(profileColor.flatMap { Color(hex: $0) } ?? .cauldronOrange)
                                        }
                                    }
                                )
                        }

                        }

                        // Inline avatar edit menu
                        Menu {
                            Button {
                                selectedAvatarType = .emoji
                                profileImage = nil
                                showingAvatarPicker = true
                            } label: {
                                Label("Choose Emoji", systemImage: "face.smiling")
                            }
                            Button {
                                selectedAvatarType = .photo
                                imagePickerSourceType = .photoLibrary
                                showingImagePicker = true
                            } label: {
                                Label("Photo Library", systemImage: "photo.on.rectangle")
                            }
                            Button {
                                selectedAvatarType = .photo
                                imagePickerSourceType = .camera
                                showingImagePicker = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                            }
                            if profileImage != nil || (selectedAvatarType == .photo && currentUser.profileImageURL != nil) {
                                Divider()
                                Button(role: .destructive) {
                                    profileImage = nil
                                    selectedAvatarType = .emoji
                                    isAvatarDirty = true
                                } label: {
                                    Label("Remove Photo", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.cauldronOrange, in: Circle())
                                .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2))
                        }
                        .accessibilityLabel("Edit avatar")
                        }

                        Text(displayName.isEmpty ? "Your Name" : displayName)
                            .font(.system(.title2, design: .serif).weight(.bold))

                        Text("@\(username.isEmpty ? "username" : username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Profile form (matching onboarding style)
                    VStack(spacing: 24) {
                        // Username field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            TextField("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textCase(.lowercase)
                                .padding()
                                .background(Color.cauldronSecondaryBackground)
                                .cornerRadius(Theme.Radius.card)

                            Text("3-20 characters, letters, numbers, and underscores only")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Display Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Display Name")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            TextField("Your Name", text: $displayName)
                                .textInputAutocapitalization(.words)
                                .padding()
                                .background(Color.cauldronSecondaryBackground)
                                .cornerRadius(Theme.Radius.card)

                            Text("This is how others will see you")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // App Icon Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Appearance")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            NavigationLink {
                                AppIconPickerView()
                            } label: {
                                HStack(spacing: 12) {
                                    Image("BrandMarks/CauldronIcon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 44, height: 44)
                                        .cornerRadius(10)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("App Icon")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        Text(AppIconManager.shared.currentTheme.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.cauldronSecondaryBackground)
                                .cornerRadius(Theme.Radius.card)
                            }
                            .buttonStyle(.plain)
                        }

                        // Delete Account Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Account")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            NavigationLink {
                                DeleteAccountView(dependencies: dependencies)
                            } label: {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.cauldronOrange)
                                    Text("Delete Account")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.cauldronSecondaryBackground)
                                .cornerRadius(Theme.Radius.card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .appPageChrome()
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .disabled(!isValid || !hasChanges || isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingAvatarPicker) {
                AvatarCustomizationSheet(
                    selectedEmoji: $profileEmoji,
                    selectedColor: $profileColor
                )
                .appSheetSizing(.standard)
            }
            // Use fullScreenCover for camera to prevent white bar at bottom of viewfinder
            .fullScreenCover(isPresented: $showingImagePicker) {
                ImagePicker(
                    image: Binding(
                        get: { profileImage },
                        set: { image in
                            profileImage = image
                            isAvatarDirty = true
                        }
                    ),
                    sourceType: imagePickerSourceType
                )
                    .ignoresSafeArea()
            }
            .onChange(of: profileEmoji) { _, _ in isAvatarDirty = true }
            .onChange(of: profileColor) { _, _ in isAvatarDirty = true }
            .task {
                // Load existing profile image if available
                if selectedAvatarType == .photo,
                   currentUser.profileImageURL != nil,
                   profileImage == nil {
                    profileImage = await dependencies.profileImageManager.loadImage(userId: currentUser.id)
                }
            }
            .onChange(of: userSession.currentUser) { _, newUser in
                // Dismiss if user signs out (e.g., account deleted)
                if newUser == nil {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Actions

    private func saveProfile() async {
        guard let currentUser = currentUser else {
            // User signed out (e.g., account deleted), dismiss
            dismiss()
            return
        }
        guard let mutationContext = userSession.verifiedMutationContext(ownerID: currentUser.id) else {
            dismiss()
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            // Normalize inputs: trim whitespace and lowercase username
            let normalizedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
            let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespaces)
            let didEditBasicInfo = ProfileEditChangePolicy.didEditBasicInfo(
                initialUser: initialUser,
                username: normalizedUsername,
                displayName: normalizedDisplayName
            )
            if didEditBasicInfo, normalizedUsername != currentUser.username.lowercased() {
                try await dependencies.userCloudService.prepareUsernameChange(
                    normalizedUsername,
                    for: currentUser.id
                )
            }
            // Handle avatar update
            if isAvatarDirty, selectedAvatarType == .photo, let image = profileImage {
                let avatarIntent = ProfileMutationCoordinator.shared.reserveAvatarIntent()
                let basicIntent = didEditBasicInfo
                    ? ProfileMutationCoordinator.shared.reserveBasicIntent()
                    : nil
                let preparedImageData = try await dependencies.profileImageManager
                    .prepareImageData(image)
                let stagedImage = try await dependencies.profileImageManager
                    .stagePreparedImageData(preparedImageData, userId: currentUser.id)
                guard ProfileMutationCoordinator.shared.isCurrentAvatarIntent(avatarIntent) else {
                    await dependencies.profileImageManager.deleteStagedImage(
                        stagedImage,
                        userId: currentUser.id
                    )
                    return
                }
                // Compression and staging do not mutate shared profile state.
                // The avatar intent reserved above preserves action ordering;
                // basic-info commits use an independent latest-wins stream.
                guard let commitResult = try await ProfileMutationCoordinator.shared.performCommit(
                    avatarIntent: avatarIntent,
                    operation: { () async throws -> (SavedImageReplacement, StagedImageReplacement, ProfileAvatarMutationToken, ProfileBasicInfoMutationToken?, User, User, UUID)? in
                    guard let commitBaseUser = userSession.currentUser,
                          commitBaseUser.id == mutationContext.ownerID else { return nil }
                    let profileImageURL = await dependencies.profileImageManager.imageURL(for: currentUser.id)
                    guard ProfileMutationCoordinator.shared.beginAvatarPublication(avatarIntent) else {
                        return nil
                    }
                    let shouldCommitBasicInfo = basicIntent.map {
                        ProfileMutationCoordinator.shared.isCurrentBasicIntent($0)
                    } ?? false
                    guard let pendingCommit = userSession.prepareAuthorizedAvatarPendingSync(
                        context: mutationContext,
                        replacing: commitBaseUser,
                        profileImageURL: profileImageURL,
                        profileImageLocalRevision: stagedImage.generation,
                        stagedImageURL: stagedImage.url,
                        username: shouldCommitBasicInfo ? normalizedUsername : nil,
                        displayName: shouldCommitBasicInfo ? normalizedDisplayName : nil
                    ) else {
                        await dependencies.profileImageManager.deleteStagedImage(stagedImage, userId: currentUser.id)
                        return nil
                    }
                    let savedImage = try await dependencies.profileImageManager
                        .promoteStagedImage(
                            stagedImage,
                            userId: currentUser.id,
                            knownPreviousGeneration: commitBaseUser.profileImageLocalRevision
                        )
                    guard let avatarToken = userSession.reserveProfileAvatarMutation(
                        context: mutationContext,
                        replacing: commitBaseUser
                    ) else {
                        // The durable marker and staged bytes intentionally remain
                        // queued for the owning account to reconcile on next launch.
                        throw CancellationError()
                    }
                    // Do not supersede a valid earlier basic-info save until the
                    // fallible local image write has succeeded. If a newer window
                    // edited the name while this write was suspended, its edit wins.
                    let basicInfoToken = shouldCommitBasicInfo
                        ? userSession.reserveProfileBasicInfoMutation(
                            context: mutationContext,
                            replacing: commitBaseUser
                        )
                        : nil
                    guard let optimisticUser = userSession.publishAuthorizedAvatarPendingSync(
                        transactionID: pendingCommit.transactionID,
                        context: mutationContext,
                        token: avatarToken,
                        whileAvatarMatches: commitBaseUser,
                        profileImageURL: savedImage.url,
                        profileImageLocalRevision: savedImage.file.generation,
                        basicInfoToken: basicInfoToken,
                        username: shouldCommitBasicInfo ? normalizedUsername : nil,
                        displayName: shouldCommitBasicInfo ? normalizedDisplayName : nil
                    ) else {
                        throw CancellationError()
                    }
                    if let supersededURL = pendingCommit.supersededStagedImageURL {
                        await dependencies.profileImageManager.deleteStagedImage(
                            at: supersededURL,
                            userId: currentUser.id
                        )
                    }
                        return (
                            savedImage,
                            stagedImage,
                            avatarToken,
                            basicInfoToken,
                            commitBaseUser,
                            optimisticUser,
                            pendingCommit.transactionID
                        )
                    }
                ) else {
                    await dependencies.profileImageManager.deleteStagedImage(stagedImage, userId: currentUser.id)
                    return
                }
                let (savedImage, _, avatarToken, basicInfoToken, commitBaseUser, optimisticUser, pendingProfileSync) = commitResult
                let profileImageURL = savedImage.url
                AppLogger.general.info("✅ Updated profile locally (optimistic)")

                // Dismiss sheet immediately for snappy UX
                dismiss()

                // Background sync to CloudKit
                ProfileEditSyncCoordinator.shared.enqueue { [dependencies, currentUser = commitBaseUser, mutationContext, avatarToken] in
                    do {
                        guard CurrentUserSession.shared.permitsProfileAvatarMutation(
                            avatarToken,
                            context: mutationContext,
                            whileAvatarMatches: optimisticUser
                        ) else { return }
                        let uploadOutcome = try await dependencies.profileImageManager.uploadImageToCloud(
                            userId: currentUser.id,
                            expectedGeneration: savedImage.file.generation,
                            authorization: {
                                await CurrentUserSession.shared.permitsProfileAvatarMutation(
                                    avatarToken,
                                    context: mutationContext,
                                    whileAvatarMatches: optimisticUser
                                )
                            }
                        )
                        let cloudProfileImageRecordName: String
                        switch uploadOutcome {
                        case .staleBeforeUpload, .staleAfterUpload:
                            // The durable pending transaction (or its successor)
                            // owns retrying the deterministic profile-image record.
                            return
                        case .uploaded(let recordName):
                            cloudProfileImageRecordName = recordName
                        }
                        guard CurrentUserSession.shared.permitsProfileAvatarMutation(
                            avatarToken,
                            context: mutationContext,
                            whileAvatarMatches: optimisticUser
                        ) else {
                                await Self.retryStaleProfileAssetCleanup(
                                    userID: currentUser.id,
                                    dependencies: dependencies,
                                    mutationContext: mutationContext
                            )
                            return
                        }
                        let profileImageModifiedAt = Date()
                        AppLogger.general.info("☁️ Uploaded profile image to CloudKit in background")

                        guard let finalUser = CurrentUserSession.shared.userByMergingAuthorizedAvatar(
                            context: mutationContext,
                            token: avatarToken,
                            whileAvatarMatches: optimisticUser,
                            profileEmoji: nil,
                            profileColor: nil,
                            profileImageURL: profileImageURL,
                            cloudProfileImageRecordName: cloudProfileImageRecordName,
                            profileImageModifiedAt: profileImageModifiedAt,
                            profileImageLocalRevision: savedImage.file.generation,
                            basicInfoToken: basicInfoToken,
                            username: didEditBasicInfo ? normalizedUsername : nil,
                            displayName: didEditBasicInfo ? normalizedDisplayName : nil
                        ) else { return }

                        try await dependencies.userCloudService.saveUser(finalUser)
                        let didUpdateWebSnapshot = await dependencies.externalShareService.updateProfileShareMetadata(
                            for: finalUser
                        )
                        guard didUpdateWebSnapshot else { return }
                        guard CurrentUserSession.shared.permitsProfileAvatarMutation(
                            avatarToken,
                            context: mutationContext,
                            whileAvatarMatches: optimisticUser
                        ) else { return }

                        CurrentUserSession.shared.commitAuthorizedAvatar(
                            context: mutationContext,
                            token: avatarToken,
                            whileAvatarMatches: optimisticUser,
                            profileEmoji: nil,
                            profileColor: nil,
                            profileImageURL: profileImageURL,
                            cloudProfileImageRecordName: cloudProfileImageRecordName,
                            profileImageModifiedAt: profileImageModifiedAt,
                            profileImageLocalRevision: savedImage.file.generation,
                            basicInfoToken: basicInfoToken,
                            username: didEditBasicInfo ? normalizedUsername : nil,
                            displayName: didEditBasicInfo ? normalizedDisplayName : nil
                        )
                        CurrentUserSession.shared.clearPendingProfileSync(
                            transactionID: pendingProfileSync
                        )
                        await dependencies.profileImageManager.deleteStagedImage(
                            stagedImage,
                            userId: currentUser.id
                        )
                    } catch {
                        AppLogger.general.error("❌ Background CloudKit sync failed: \(error.localizedDescription)")
                        // Note: UI already updated optimistically, so user doesn't see this error
                        // Could add a notification or retry mechanism here
                    }
                }

            } else if isAvatarDirty, selectedAvatarType == .emoji {
                let avatarIntent = ProfileMutationCoordinator.shared.reserveAvatarIntent()
                let basicIntent = didEditBasicInfo
                    ? ProfileMutationCoordinator.shared.reserveBasicIntent()
                    : nil
                guard let commitResult = await ProfileMutationCoordinator.shared.performCommit(
                    avatarIntent: avatarIntent,
                    operation: { () async -> (ProfileBasicInfoMutationToken?, ProfileAvatarMutationToken, User, User, UUID, URL?)? in
                    guard let commitBaseUser = userSession.currentUser,
                          commitBaseUser.id == mutationContext.ownerID,
                          ProfileMutationCoordinator.shared.beginAvatarPublication(avatarIntent) else {
                        return nil
                    }
                    let shouldCommitBasicInfo = basicIntent.map {
                        ProfileMutationCoordinator.shared.isCurrentBasicIntent($0)
                    } ?? false
                    let basicInfoToken = shouldCommitBasicInfo
                        ? userSession.reserveProfileBasicInfoMutation(
                        context: mutationContext,
                        replacing: commitBaseUser
                    )
                        : nil
                    guard !shouldCommitBasicInfo || basicInfoToken != nil,
                          let avatarToken = userSession.reserveProfileAvatarMutation(
                            context: mutationContext,
                            replacing: commitBaseUser
                          ),
                          let optimisticCommit = userSession.commitAuthorizedAvatarWithPendingSync(
                            context: mutationContext,
                            token: avatarToken,
                            whileAvatarMatches: commitBaseUser,
                            profileEmoji: profileEmoji,
                            profileColor: profileColor,
                            profileImageURL: nil,
                            cloudProfileImageRecordName: nil,
                            profileImageModifiedAt: nil,
                            profileImageLocalRevision: nil,
                            basicInfoToken: basicInfoToken,
                            username: shouldCommitBasicInfo ? normalizedUsername : nil,
                            displayName: shouldCommitBasicInfo ? normalizedDisplayName : nil
                          ) else { return nil }
                    return (
                        basicInfoToken,
                        avatarToken,
                        commitBaseUser,
                        optimisticCommit.user,
                        optimisticCommit.transactionID,
                        optimisticCommit.supersededStagedImageURL
                    )
                    }
                ) else { return }
                let (basicInfoToken, avatarToken, commitBaseUser, updatedUser, pendingProfileSync, supersededStagedImageURL) = commitResult
                if let supersededStagedImageURL {
                    await dependencies.profileImageManager.deleteStagedImage(
                        at: supersededStagedImageURL,
                        userId: currentUser.id
                    )
                }
                AppLogger.general.info("✅ Updated profile locally with emoji (optimistic)")

                // Dismiss immediately
                dismiss()

                // Background sync
                ProfileEditSyncCoordinator.shared.enqueue { [dependencies, currentUser = commitBaseUser, mutationContext, avatarToken] in
                    guard CurrentUserSession.shared.permitsProfileAvatarMutation(
                        avatarToken,
                        context: mutationContext,
                        whileAvatarMatches: updatedUser
                    ) else { return }
                    // Clear existing profile image
                    await dependencies.profileImageManager.deleteImage(userId: currentUser.id)
                    guard CurrentUserSession.shared.permitsProfileAvatarMutation(
                        avatarToken,
                        context: mutationContext,
                        whileAvatarMatches: updatedUser
                    ) else { return }

                    do {
                        // Delete from CloudKit if exists
                        if currentUser.cloudProfileImageRecordName != nil || currentUser.profileImageURL != nil {
                            guard CurrentUserSession.shared.permitsProfileAvatarMutation(
                                avatarToken,
                                context: mutationContext,
                                whileAvatarMatches: updatedUser
                            ) else { return }
                            try await dependencies.profileImageManager.deleteImageFromCloud(
                                userId: currentUser.id,
                                authorization: {
                                    await CurrentUserSession.shared.permitsProfileAvatarMutation(
                                        avatarToken,
                                        context: mutationContext,
                                        whileAvatarMatches: updatedUser
                                    )
                                }
                            )
                            guard CurrentUserSession.shared.permitsProfileAvatarMutation(
                                avatarToken,
                                context: mutationContext,
                                whileAvatarMatches: updatedUser
                            ) else { return }
                        }

                        // Save updated user to CloudKit
                        guard let latestUser = CurrentUserSession.shared.userByMergingAuthorizedAvatar(
                            context: mutationContext,
                            token: avatarToken,
                            whileAvatarMatches: updatedUser,
                            profileEmoji: updatedUser.profileEmoji,
                            profileColor: updatedUser.profileColor,
                            profileImageURL: nil,
                            cloudProfileImageRecordName: nil,
                            profileImageModifiedAt: nil,
                            profileImageLocalRevision: nil,
                            basicInfoToken: basicInfoToken,
                            username: didEditBasicInfo ? normalizedUsername : nil,
                            displayName: didEditBasicInfo ? normalizedDisplayName : nil
                        ) else { return }
                        try await dependencies.userCloudService.saveUser(latestUser)
                        let didUpdateWebSnapshot = await dependencies.externalShareService.updateProfileShareMetadata(
                            for: latestUser
                        )
                        guard didUpdateWebSnapshot else { return }
                        CurrentUserSession.shared.clearPendingProfileSync(
                            transactionID: pendingProfileSync
                        )
                        AppLogger.general.info("☁️ Synced emoji profile to CloudKit in background")
                    } catch {
                        AppLogger.general.error("❌ Background CloudKit sync failed: \(error.localizedDescription)")
                    }
                }

            } else if didEditBasicInfo {
                let basicIntent = ProfileMutationCoordinator.shared.reserveBasicIntent()
                guard let commitResult = await ProfileMutationCoordinator.shared.performCommit(
                    basicIntent: basicIntent,
                    operation: { () async -> (ProfileBasicInfoMutationToken, UUID)? in
                    guard let commitBaseUser = userSession.currentUser,
                          commitBaseUser.id == mutationContext.ownerID else { return nil }
                    guard let basicInfoToken = userSession.reserveProfileBasicInfoMutation(
                        context: mutationContext,
                        replacing: commitBaseUser
                    ), let optimisticCommit = userSession.commitAuthorizedBasicInfoWithPendingSync(
                        context: mutationContext,
                        token: basicInfoToken,
                        username: normalizedUsername,
                        displayName: normalizedDisplayName
                    ) else { return nil }
                    return (basicInfoToken, optimisticCommit.transactionID)
                    }
                ) else { return }
                let (basicInfoToken, pendingProfileSync) = commitResult
                AppLogger.general.info("✅ Updated basic profile info locally (optimistic)")

                dismiss()

                // Background sync
                ProfileEditSyncCoordinator.shared.enqueue { [dependencies, mutationContext] in
                    guard CurrentUserSession.shared.permitsProfileBasicInfoMutation(
                        basicInfoToken,
                        context: mutationContext
                    ) else { return }
                    await CurrentUserSession.shared.reconcilePendingProfileSync(
                        transactionID: pendingProfileSync,
                        dependencies: dependencies
                    )
                }
            }

        } catch {
            AppLogger.general.error("❌ Failed to save profile locally: \(error.localizedDescription)")
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
            showError = true
        }
    }

    private static func retryStaleProfileAssetCleanup(
        userID: UUID,
        dependencies: DependencyContainer,
        mutationContext: VerifiedAccountMutationContext
    ) async {
        for attempt in 0..<3 {
            do {
                try await dependencies.profileImageManager.deleteImageFromCloud(
                    userId: userID,
                    authorization: {
                        await CurrentUserSession.shared.permitsMutation(mutationContext)
                    }
                )
                return
            } catch {
                guard attempt < 2 else {
                    AppLogger.general.error("Unable to clean up superseded profile asset: \(error.localizedDescription)")
                    return
                }
                try? await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
            }
        }
    }

}

/// Serializes profile CloudKit writes so a newer same-account edit always runs
/// after any already-started older write. Snapshot guards skip queued stale
/// work before it can touch local images or remote profile metadata.
@MainActor
private final class ProfileEditSyncCoordinator {
    static let shared = ProfileEditSyncCoordinator()

    private var tail: Task<Void, Never>?

    func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = task
    }
}

/// Orders local profile commits without superseding the logical avatar until
/// image preparation and any transactional local replacement have succeeded.
struct ProfileMutationOrderingGate {
    private var avatarIntentRevision: UInt64 = 0
    private var basicIntentRevision: UInt64 = 0
    private var publishingAvatarIntent: UInt64?

    mutating func reserveAvatarIntent() -> UInt64 {
        avatarIntentRevision &+= 1
        return avatarIntentRevision
    }

    mutating func reserveBasicIntent() -> UInt64 {
        basicIntentRevision &+= 1
        return basicIntentRevision
    }

    func permitsCommit(avatarIntent: UInt64?, basicIntent: UInt64?) -> Bool {
        if let avatarIntent {
            return isCurrentAvatarIntent(avatarIntent)
        }
        if let basicIntent {
            return isCurrentBasicIntent(basicIntent)
        }
        return true
    }

    func isCurrentAvatarIntent(_ intent: UInt64) -> Bool {
        intent == avatarIntentRevision
    }

    func isCurrentBasicIntent(_ intent: UInt64) -> Bool {
        intent == basicIntentRevision
    }

    mutating func beginAvatarPublication(_ intent: UInt64) -> Bool {
        guard publishingAvatarIntent == nil,
              isCurrentAvatarIntent(intent) else { return false }
        publishingAvatarIntent = intent
        return true
    }

    mutating func endAvatarPublication(_ intent: UInt64) {
        guard publishingAvatarIntent == intent else { return }
        publishingAvatarIntent = nil
    }
}

@MainActor
private final class ProfileMutationCoordinator {
    static let shared = ProfileMutationCoordinator()

    private var orderingGate = ProfileMutationOrderingGate()
    private var isCommitting = false
    private var commitWaiters: [CheckedContinuation<Void, Never>] = []

    func reserveAvatarIntent() -> UInt64 {
        orderingGate.reserveAvatarIntent()
    }

    func isCurrentAvatarIntent(_ intent: UInt64) -> Bool {
        orderingGate.isCurrentAvatarIntent(intent)
    }

    func reserveBasicIntent() -> UInt64 {
        orderingGate.reserveBasicIntent()
    }

    func isCurrentBasicIntent(_ intent: UInt64) -> Bool {
        orderingGate.isCurrentBasicIntent(intent)
    }

    func beginAvatarPublication(_ intent: UInt64) -> Bool {
        orderingGate.beginAvatarPublication(intent)
    }

    func performCommit<Result>(
        avatarIntent: UInt64? = nil,
        basicIntent: UInt64? = nil,
        operation: @escaping @MainActor () async throws -> Result?
    ) async rethrows -> Result? {
        await acquireCommitLock()
        defer {
            if let avatarIntent {
                orderingGate.endAvatarPublication(avatarIntent)
            }
            releaseCommitLock()
        }
        guard orderingGate.permitsCommit(
            avatarIntent: avatarIntent,
            basicIntent: basicIntent
        ) else { return nil }
        return try await operation()
    }

    private func acquireCommitLock() async {
        guard isCommitting else {
            isCommitting = true
            return
        }
        await withCheckedContinuation { commitWaiters.append($0) }
    }

    private func releaseCommitLock() {
        guard !commitWaiters.isEmpty else {
            isCommitting = false
            return
        }
        commitWaiters.removeFirst().resume()
    }
}

#Preview {
    let previewUser = User(username: "chef_julia", displayName: "Julia Child", profileEmoji: "👨‍🍳", profileColor: Color.cauldronOrange.toHex())
    return NavigationStack {
        ProfileEditView(dependencies: .preview(), previewUser: previewUser)
    }
}
