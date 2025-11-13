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
                    .font(.title)
                    .fontWeight(.bold)

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
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()

                // Delete button
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Permanently Delete Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
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

        do {
            AppLogger.general.info("🗑️ Starting account deletion for user: \(userId)")

            // Step 1: Delete all user recipes from CloudKit and local storage
            AppLogger.general.info("Deleting all user recipes...")
            try await dependencies.recipeRepository.deleteAllUserRecipes(userId: userId)
            AppLogger.general.info("✅ All recipes deleted")

            // Step 2: Delete all user collections from CloudKit and local storage
            AppLogger.general.info("Deleting all user collections...")
            try await dependencies.collectionRepository.deleteAllUserCollections(userId: userId)
            AppLogger.general.info("✅ All collections deleted")

            // Step 3: Delete user profile from CloudKit
            AppLogger.general.info("Deleting user profile from CloudKit...")
            try await dependencies.cloudKitService.deleteUserProfile(userId: userId)
            AppLogger.general.info("✅ User profile deleted from CloudKit")

            // Step 4: Clear local user data and sign out
            AppLogger.general.info("Clearing local data and signing out...")
            await MainActor.run {
                CurrentUserSession.shared.signOut()
            }

            AppLogger.general.info("✅ Account deletion complete")

            // Dismiss view - user will be returned to onboarding
            dismiss()

        } catch {
            AppLogger.general.error("❌ Account deletion failed: \(error.localizedDescription)")
            errorMessage = "Failed to delete account: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    DeleteAccountView(dependencies: .preview())
}
