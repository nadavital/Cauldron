import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isSignUpMode = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background using app's accent color scheme
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.accentColor.opacity(0.15),
                        Color.accentColor.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 40) {
                        Spacer(minLength: 60)
                        
                        // App branding section with cauldron image
                        VStack(spacing: 20) {
                            Image("cauldron_transparent")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .foregroundColor(.accentColor)
                            
                            Text("Cauldron")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Your magical recipe collection")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Auth card matching app style
                        VStack(spacing: 24) {
                            // Mode toggle with app styling
                            Picker(selection: $isSignUpMode, label: Text("")) {
                                Text("Sign In").tag(false)
                                Text("Sign Up").tag(true)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .padding(.horizontal, 20)
                            
                            // Form fields with consistent styling
                            VStack(spacing: 16) {
                                // Username field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Username")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("Enter your username", text: $authViewModel.username)
                                        .autocapitalization(.none)
                                        .textFieldStyle(AppTextFieldStyle())
                                }
                                
                                // Email field (only for sign up)
                                if isSignUpMode {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Email")
                                            .font(.callout)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                        
                                        TextField("Enter your email", text: $authViewModel.email)
                                            .autocapitalization(.none)
                                            .keyboardType(.emailAddress)
                                            .textFieldStyle(AppTextFieldStyle())
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                
                                // Password field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Password")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    SecureField("Enter your password", text: $authViewModel.password)
                                        .textFieldStyle(AppTextFieldStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Error message with consistent styling
                            if let error = authViewModel.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                    .transition(.opacity)
                            }
                            
                            // Action button matching app's save button style
                            Button(action: { 
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSignUpMode ? authViewModel.signUp() : authViewModel.signIn()
                                }
                            }) {
                                Text(isSignUpMode ? "Create Account" : "Sign In")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.accentColor)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 20)
                            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
                        }
                        .padding(.vertical, 32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.regularMaterial)
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                        )
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isSignUpMode)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
