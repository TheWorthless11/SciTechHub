//
//  AuthViewModel.swift
//  SciTechHub
//
//  Created by Sayaka Alam on 5/4/26.
//

import Foundation
import FirebaseAuth

class AuthViewModel: ObservableObject {
    // Published properties to update the UI
    @Published var user: User?
    @Published var isSignedIn: Bool = false
    @Published var errorMessage: String = ""
    
    // MARK: - Sign Up
    func signUp(email: String, password: String) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                // On success, store the user and update login state
                self?.user = result?.user
                self?.isSignedIn = true
                self?.errorMessage = "" // Clear any previous errors
            }
        }
    }
    
    // MARK: - Sign In
    func signIn(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                // On success, store the user and update login state
                self?.user = result?.user
                self?.isSignedIn = true
                self?.errorMessage = "" // Clear any previous errors
            }
        }
    }
    
    // MARK: - Sign Out
    func signOut() {
        do {
            try Auth.auth().signOut()
            DispatchQueue.main.async {
                // Clear state on successful sign out
                self.user = nil
                self.isSignedIn = false
                self.errorMessage = "" // Clear any previous errors
            }
        } catch let signOutError {
            DispatchQueue.main.async {
                self.errorMessage = signOutError.localizedDescription
            }
        }
    }
}
