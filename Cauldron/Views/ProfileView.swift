import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingSignOutAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    VStack(spacing: 16) {
                        // Profile Image Placeholder
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.accentColor)
                            )
                        
                        // User Info
                        VStack(spacing: 8) {
                            if let user = authViewModel.user {
                                if let displayName = user.displayName, !displayName.isEmpty {
                                    Text(displayName)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                } else {
                                    Text("Recipe Chef")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(user.email ?? "No email")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 20)
                    
                    // Settings Sections
                    VStack(spacing: 20) {
                        // Account Section
                        SettingsSection(title: "Account") {
                            SettingsRow(
                                title: "Sign Out",
                                icon: "rectangle.portrait.and.arrow.right",
                                iconColor: .red
                            ) {
                                showingSignOutAlert = true
                            }
                        }
                        
                        // App Info Section
                        SettingsSection(title: "About") {
                            SettingsRow(
                                title: "Version",
                                icon: "info.circle",
                                iconColor: .blue,
                                trailing: { 
                                    Text("1.0.0")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            ) {
                                // No action for version
                            }
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
}

// Helper Views for Settings
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
            )
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let trailing: Trailing
    let action: () -> Void
    
    init(
        title: String,
        icon: String,
        iconColor: Color = .primary,
        @ViewBuilder trailing: @escaping () -> Trailing,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.trailing = trailing()
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                trailing
                
                if !(trailing is EmptyView) {
                    // Don't show chevron if there's custom trailing content
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Convenience initializer for rows without trailing content
extension SettingsRow where Trailing == EmptyView {
    init(
        title: String,
        icon: String,
        iconColor: Color = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.trailing = EmptyView()
        self.action = action
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
} 