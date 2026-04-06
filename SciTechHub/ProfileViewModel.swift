import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

class ProfileViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var userEmail: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    private let db = Firestore.firestore()
    
    init() {
        fetchUserInfo()
    }
    
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
    
    func fetchUserInfo() {
        guard let user = Auth.auth().currentUser else { return }
        self.userEmail = user.email ?? ""
        
        // Fetch name from Firestore or Auth
        db.collection("users").document(user.uid).getDocument { [weak self] document, error in
            if let document = document, document.exists {
                self?.userName = document.data()?["name"] as? String ?? "User"
            } else {
                self?.userName = user.displayName ?? "User"
            }
        }
    }
    
    func updateProfile(name: String) {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        guard let user = Auth.auth().currentUser else {
            isLoading = false
            return
        }
        
        // Update Firebase Auth Profile
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name
        changeRequest.commitChanges { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                return
            }
            
            // Update Firestore
            self.db.collection("users").document(user.uid).setData(["name": name], merge: true) { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.userName = name
                        self.successMessage = "Profile updated successfully!"
                    }
                }
            }
        }
    }
    
    func reportIssue(message: String) {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        guard let user = Auth.auth().currentUser else {
            isLoading = false
            return
        }
        
        let reportData: [String: Any] = [
            "uid": user.uid,
            "email": user.email ?? "",
            "message": message,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        db.collection("reports").addDocument(data: reportData) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.successMessage = "Issue reported successfully. Thank you!"
                }
            }
        }
    }
}
