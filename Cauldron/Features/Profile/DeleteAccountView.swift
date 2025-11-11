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

        do {
            // TODO: Implement account deletion
            // This should:
            // 1. Delete all user recipes from CloudKit
            // 2. Delete all user collections from CloudKit
            // 3. Delete user profile from CloudKit
            // 4. Clear local data
            // 5. Sign out

            AppLogger.general.warning("⚠️ Account deletion not yet implemented")
            errorMessage = "Account deletion is not yet available"
            showError = true
        }
    }
}

#Preview {
    DeleteAccountView(dependencies: .preview())
}
