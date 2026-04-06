import SwiftUI
import FirebaseAuth

struct ChangePasswordView: View {
    @State private var email: String = ""
    @State private var isResetSent: Bool = false
    @State private var errorMessage: String?
    @State private var isLoading: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Reset Password"), footer: Text("We will send a password reset link to your email address.")) {
                TextField("Email Address", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if isResetSent {
                Text("Password reset email sent! Check your inbox.")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            
            Button(action: resetPassword) {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Send Reset Link")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(email.isEmpty || isLoading)
        }
        .navigationTitle("Change Password")
        .onAppear {
            if let user = Auth.auth().currentUser {
                self.email = user.email ?? ""
            }
        }
    }
    
    private func resetPassword() {
        isLoading = true
        errorMessage = nil
        isResetSent = false
        
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.isResetSent = true
                }
            }
        }
    }
}
