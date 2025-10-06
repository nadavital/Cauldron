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
    
    var isValid: Bool {
        username.count >= 3 && username.count <= 20 &&
        displayName.count >= 1 &&
        username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
    
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
                    
                    TextField("Display Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Profile Information")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username: 3-20 characters, letters, numbers, and underscores only")
                        Text("Display Name: How others see you")
                    }
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .disabled(!isValid || !hasChanges || isSaving)
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
