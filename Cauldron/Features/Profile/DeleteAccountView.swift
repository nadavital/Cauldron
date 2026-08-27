//
//  DeleteAccountView.swift
//  Cauldron
//
//  Dedicated view for account deletion with confirmation
//

import SwiftUI

struct DeleteAccountView: View {
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.orange)
                    .padding(.bottom, 16)

                // Title
                Text("Delete Account")
                    .font(.system(.title, design: .serif).weight(.bold))

                // Warning text
                VStack(spacing: 16) {
                    Text("This action cannot be undone")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Deleting your account will permanently remove:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("All your recipes", systemImage: "book.closed")
                        Label("All your collections", systemImage: "folder")
                        Label("Your profile and account data", systemImage: "person.crop.circle")
                        Label("Access to your public recipes", systemImage: "globe")
                    }
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    Text("Cauldron may retain minimal deletion markers in your private iCloud database so an offline device cannot restore content you deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                Spacer()

                // Delete button
                PrimaryActionButton(
                    "Permanently Delete Account",
                    systemImage: "trash",
                    role: .destructive,
                    tint: .red,
                    isBusy: isDeleting
                ) {
                    showingDeleteConfirmation = true
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .appPageChrome()
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteAccount()
                    }
                }
            } message: {
                Text("This will permanently delete your account and all associated data. This action cannot be undone.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        guard let userId = CurrentUserSession.shared.userId else {
            errorMessage = "Unable to identify user account"
            showError = true
            return
        }
        guard let deletingUser = CurrentUserSession.shared.currentUser else {
            errorMessage = "Unable to load user account"
            showError = true
            return
        }

        let deletionLease = await AccountDeletionGate.shared.begin(ownerID: userId)

        do {
            try await AccountDeletionGate.withDeletionAuthority(deletionLease) {
                AppLogger.general.info("🗑️ Starting account deletion for user: \(userId)")

            if deletingUser.cloudRecordName != nil {
                // Remove hosted snapshots while their management capability is available.
                try await dependencies.externalShareService.removeAllShareMetadata(for: deletingUser)

                AppLogger.general.info("Deleting all user recipes...")
                try await dependencies.recipeRepository.deleteAllUserRecipes(userId: userId)
                AppLogger.general.info("✅ All recipes deleted")

                AppLogger.general.info("Deleting all user collections...")
                try await dependencies.collectionRepository.deleteAllUserCollections(userId: userId)
                AppLogger.general.info("✅ All collections deleted")

                try await dependencies.savedReferenceCloudService.deleteAllReferences(for: userId)

                AppLogger.general.info("Deleting all user connections...")
                try await dependencies.connectionRepository.deleteAllConnectionsForUser(userId: userId)
                try await dependencies.connectionCloudService.deleteAllConnectionsForUser(userId: userId)
                AppLogger.general.info("✅ All connections deleted")

                // Every remaining fallible local/private cleanup happens while
                // the public identity still exists, preserving retry authority.
                try await dependencies.userCloudService.deleteWebShareCapability(for: userId)
                try await dependencies.purgeAllLocalAccountData()

                do {
                    try await ShareCapabilityStore.shared.removeCapability(for: userId)
                } catch {
                    AppLogger.general.warning("Unable to clear obsolete web-share key: \(error.localizedDescription)")
                }

                AppLogger.general.info("Deleting user profile from CloudKit...")
                try await dependencies.userCloudService.deleteUserProfile(userId: userId)
                AppLogger.general.info("✅ User profile deleted from CloudKit")
            } else {
                // Onboarding intentionally supports a local-only fallback. With
                // no CloudKit identity there is no hosted authority to revoke.
                try await dependencies.purgeAllLocalAccountData()
            }

            AppLogger.general.info("Clearing local data and signing out...")
            await dependencies.profileImageManager.deleteImage(userId: userId)
            await dependencies.connectionManager.resetSessionState()
            await FriendsTabViewModel.shared.resetSessionState()
            await dependencies.sharingService.resetSharedRecipeCache()

            // Invalidate local identity synchronously before suspending in
            // system donation cleanup. Otherwise a donation for the deleted
            // owner could still pass its real-identity preflight and supersede
            // this nil-owner boundary while cleanup is in progress.
            await MainActor.run {
                ReferralManager.shared.reset()
                CurrentUserSession.shared.signOut()
            }

            // Recipe donations are system-wide. Remove only the two intents
            // carrying recipe entities after crossing the local identity
            // boundary; generic timer donations and App Shortcuts remain.
            await RecipeIntentDonation.reconcileAccountBoundary(currentOwnerID: nil)

                AppLogger.general.info("✅ Account deletion complete")
            }

            await AccountDeletionGate.shared.end(deletionLease)

            // Dismiss view - user will be returned to onboarding
            dismiss()

        } catch {
            AppLogger.general.error("❌ Account deletion failed: \(error.localizedDescription)")
            // Reopen normal publication before attempting compensating share
            // restoration; the deletion-authorized scope ended with the throw.
            await AccountDeletionGate.shared.end(deletionLease)
            if deletingUser.cloudRecordName != nil {
                do {
                    try await dependencies.externalShareService.restoreAccountShareMetadata(for: deletingUser)
                } catch {
                    AppLogger.general.error("Account deletion is paused and web sharing remains revoked: \(error.localizedDescription)")
                }
            }
            errorMessage = "Account deletion did not finish. No deleted web shares were restored; retry deletion to complete cleanup. \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    DeleteAccountView(dependencies: .preview())
}
