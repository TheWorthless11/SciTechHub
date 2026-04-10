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
    @Published var isLoggedIn: Bool = false
    @Published var errorMessage: String = ""
    
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    var isSignedIn: Bool {
        isLoggedIn
    }
    
    init() {
        observeAuthState()
    }
    
    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }
    
    private func observeAuthState() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isLoggedIn = (user != nil)
            }
        }
    }
    
    // MARK: - Sign Up
    func signUp(email: String, password: String) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                // Auth state listener updates user/login state.
                self?.user = result?.user
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
                
                // Auth state listener updates user/login state.
                self?.user = result?.user
                self?.errorMessage = "" // Clear any previous errors
            }
        }
    }
    
    // MARK: - Sign Out
    func signOut() {
        do {
            try Auth.auth().signOut()
            DispatchQueue.main.async {
                // Auth state listener updates user/login state.
                self.user = nil
                self.errorMessage = "" // Clear any previous errors
            }
        } catch let signOutError {
            DispatchQueue.main.async {
                self.errorMessage = signOutError.localizedDescription
            }
        }
    }
}
