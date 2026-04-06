import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    // MARK: - State Properties
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var isSignUp = false // Toggle between Sign In and Sign Up
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                
                // MARK: - Header
                VStack(spacing: 8) {
                    Image(systemName: "atom")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.blue)
                        .padding(.bottom, 10)
                    
                    Text("SciTech Hub")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Explore Science & Technology")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top, 40)
                
                // MARK: - Error Message
                if !authViewModel.errorMessage.isEmpty {
                    Text(authViewModel.errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .transition(.opacity)
                }
                
                // MARK: - Input Fields
                VStack(spacing: 16) {
                    // Email Field
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        
                        TextField("Email Address", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Password Field
                    VStack(alignment: .trailing, spacing: 12) {
                        HStack {
                            Image(systemName: "lock")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            
                            if showPassword {
                                TextField("Password", text: $password)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } else {
                                SecureField("Password", text: $password)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            Button(action: {
                                showPassword.toggle()
                            }) {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                        // Forgot Password Link
                        Button(action: {
                            // Only visible in Sign In mode normally (or if you add a specific method in AuthViewModel)
                        }) {
                            Text("Forgot Password?")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        .opacity(isSignUp ? 0 : 1) // Hide when switching to Sign Up
                    }
                }
                .padding(.horizontal, 24)
                
                // MARK: - Sign In/Up Button
                Button(action: handleAuth) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFormValid ? Color.blue : Color.blue.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    // Add subtle shadow for modern feel
                    .shadow(color: Color.blue.opacity(isFormValid ? 0.3 : 0), radius: 5, x: 0, y: 3)
                }
                .disabled(!isFormValid || isLoading)
                .padding(.horizontal, 24)
                
                Spacer()
                
                // MARK: - Footer (Switch Mode)
                HStack {
                    Text(isSignUp ? "Already have an account?" : "Don’t have an account?")
                        .foregroundColor(.gray)
                    
                    Button(action: {
                        withAnimation {
                            isSignUp.toggle()
                            authViewModel.errorMessage = "" // Clear errors when switching
                        }
                    }) {
                        Text(isSignUp ? "Sign In" : "Sign Up")
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
                .font(.footnote)
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Validation & Actions
    
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private func handleAuth() {
        authViewModel.errorMessage = ""
        isLoading = true
        
        // Start actual Firebase Auth operations
        if isSignUp {
            authViewModel.signUp(email: email, password: password)
        } else {
            authViewModel.signIn(email: email, password: password)
        }
        
        // Add a slight visual delay strictly for the neat UI loading spinner, since auth can be instantaneous.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isLoading = false
        }
    }
}

// MARK: - Preview
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthViewModel()) // Injected For Preview
    }
}
