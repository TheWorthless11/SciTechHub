//
//  AuthView.swift
//  SciTechHub
//
//  Created by Sayaka Alam on 5/4/26.
//

import SwiftUI



struct AuthView: View {
    // ViewModel to handle logic
    @EnvironmentObject private var viewModel: AuthViewModel
    
    // State variables for user input
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 20)
            
            // Email Input
            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
            
            // Password Input
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            // Basic error message display
            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            
            VStack(spacing: 15) {
                // Sign In Button
                Button(action: {
                    viewModel.signIn(email: email, password: password)
                }) {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                // Sign Up Button
                Button(action: {
                    viewModel.signUp(email: email, password: password)
                }) {
                    Text("Sign Up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
            .padding(.top, 10)
        }
        .padding()
        // Center the VStack on the screen
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
            .environmentObject(AuthViewModel())
    }
}
