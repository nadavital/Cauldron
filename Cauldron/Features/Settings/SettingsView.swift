//
//  SettingsView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// View for editing user profile
struct EditProfileView: View {
    let dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userSession = CurrentUserSession.shared
    
    @State private var username = ""
    @State private var displayName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var hasChanges: Bool {
        guard let user = userSession.currentUser else { return false }
        return username != user.username || displayName != user.displayName
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Profile preview
                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.cauldronOrange.gradient)
                            .frame(width: 60, height: 60)
                            .overlay {
                                Text(displayName.isEmpty ? "?" : displayName.prefix(1).uppercased())
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName.isEmpty ? "Display Name" : displayName)
                                .font(.headline)
                                .foregroundColor(displayName.isEmpty ? .secondary : .primary)
                            Text(username.isEmpty ? "@username" : "@\(username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Username")
                } footer: {
                    Text("Your unique identifier. Used for mentions and finding you on the platform.")
                        .font(.caption)
                }

                Section {
                    TextField("Display Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Display Name")
                } footer: {
                    Text("How others see you. This is what appears on your profile and shared recipes.")
                        .font(.caption)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
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
                    .disabled(!hasChanges || isSaving)
                }
            }
            .onAppear {
                if let user = userSession.currentUser {
                    username = user.username
                    displayName = user.displayName
                }
            }
        }
    }
    
    private func saveProfile() async {
        isSaving = true
        errorMessage = nil

        // Validate username
        if username.count < 3 || username.count > 20 {
            errorMessage = "Username must be between 3 and 20 characters"
            isSaving = false
            return
        }

        if !username.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
            errorMessage = "Username can only contain letters, numbers, and underscores"
            isSaving = false
            return
        }

        // Validate display name
        if displayName.count < 1 {
            errorMessage = "Display name cannot be empty"
            isSaving = false
            return
        }

        do {
            try await userSession.updateUser(
                username: username,
                displayName: displayName,
                dependencies: dependencies
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

#Preview {
    EditProfileView(dependencies: .preview())
}
