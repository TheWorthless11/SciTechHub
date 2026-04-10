import Foundation
import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct ActivityHistoryItem: Identifiable {
    let id: String
    let article: Article
    let source: String
    let timestamp: Date?
}

enum MessagePermission: String, CaseIterable, Identifiable, Codable {
    case everyone
    case friends

    var id: String {
        rawValue
    }

    var displayTitle: String {
        switch self {
        case .everyone:
            return "Everyone"
        case .friends:
            return "Friends"
        }
    }

    var helperText: String {
        switch self {
        case .everyone:
            return "Any user can send you a message."
        case .friends:
            return "Only users in your friend list can send messages."
        }
    }
}

struct AppUser: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String
    let profileImageURL: String
    let isProfilePublic: Bool
    let messagePermission: MessagePermission
    let interests: [String]
    let likesCount: Int
    let bookmarksCount: Int
    let readsCount: Int
    let mutualFriendsCount: Int
    let recommendationScore: Double
    let recentActivityAt: Date?

    init(
        id: String,
        name: String,
        email: String,
        profileImageURL: String,
        isProfilePublic: Bool,
        messagePermission: MessagePermission,
        interests: [String] = [],
        likesCount: Int = 0,
        bookmarksCount: Int = 0,
        readsCount: Int = 0,
        mutualFriendsCount: Int = 0,
        recommendationScore: Double = 0,
        recentActivityAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.profileImageURL = profileImageURL
        self.isProfilePublic = isProfilePublic
        self.messagePermission = messagePermission
        self.interests = interests
        self.likesCount = likesCount
        self.bookmarksCount = bookmarksCount
        self.readsCount = readsCount
        self.mutualFriendsCount = mutualFriendsCount
        self.recommendationScore = recommendationScore
        self.recentActivityAt = recentActivityAt
    }
}

enum FriendActionState {
    case addFriend
    case requested
    case friends
}

struct FriendRequestItem: Identifiable {
    let id: String
    let senderId: String
    let receiverId: String
    let senderName: String
    let senderEmail: String
    let senderPhotoURL: String
    let receiverName: String
    let receiverEmail: String
    let receiverPhotoURL: String
    let status: String
    let timestamp: Date?
}

class ProfileViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var userEmail: String = ""
    @Published var profileImageURL: String = ""
    @Published var selectedInterests: [String] = []
    @Published var isLoading: Bool = false
    @Published var isUploadingPhoto: Bool = false
    @Published var isSavingInterests: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
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

        db.collection("users").document(user.uid).setData([
            "name": user.displayName ?? "User",
            "email": user.email ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        // Fetch name from Firestore or Auth
        db.collection("users").document(user.uid).getDocument { [weak self] document, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                if let document = document, document.exists {
                    let data = document.data() ?? [:]
                    self.userName = data["name"] as? String ?? user.displayName ?? "User"
                    self.userEmail = data["email"] as? String ?? user.email ?? ""
                    self.profileImageURL = data["profileImageUrl"] as? String ?? ""
                    self.selectedInterests = data["interests"] as? [String] ?? []
                    self.errorMessage = nil
                } else {
                    self.userName = user.displayName ?? "User"
                    self.userEmail = user.email ?? ""
                    self.profileImageURL = ""
                    self.selectedInterests = []
                    self.errorMessage = nil
                }
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

    func updateProfilePhoto(image: UIImage) {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Login required to update profile photo."
            return
        }

        guard let imageData = image.jpegData(compressionQuality: 0.75) else {
            errorMessage = "Failed to prepare image for upload."
            return
        }

        isUploadingPhoto = true
        errorMessage = nil
        successMessage = nil

        let imageRef = storage.reference().child("users/\(user.uid)/profile.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        imageRef.putData(imageData, metadata: metadata) { [weak self] _, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.isUploadingPhoto = false
                    self.errorMessage = error.localizedDescription
                }
                return
            }

            self.resolveProfilePhotoURL(for: imageRef, retriesRemaining: 3) { [weak self] url, urlError in
                guard let self = self else { return }

                if let urlError = urlError {
                    DispatchQueue.main.async {
                        self.isUploadingPhoto = false
                        self.errorMessage = self.friendlyProfilePhotoErrorMessage(from: urlError)
                    }
                    return
                }

                guard let downloadURL = url else {
                    DispatchQueue.main.async {
                        self.isUploadingPhoto = false
                        self.errorMessage = "Unable to resolve uploaded image URL."
                    }
                    return
                }

                self.db.collection("users").document(user.uid).setData([
                    "profileImageUrl": downloadURL.absoluteString
                ], merge: true) { [weak self] saveError in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.isUploadingPhoto = false

                        if let saveError = saveError {
                            self.errorMessage = saveError.localizedDescription
                        } else {
                            self.profileImageURL = downloadURL.absoluteString
                            self.successMessage = "Profile photo updated successfully!"
                        }
                    }
                }
            }
        }
    }

    private func resolveProfilePhotoURL(
        for imageRef: StorageReference,
        retriesRemaining: Int,
        completion: @escaping (URL?, Error?) -> Void
    ) {
        imageRef.downloadURL { [weak self] url, error in
            guard let self = self else { return }

            if let error = error {
                if self.isStorageObjectNotFound(error), retriesRemaining > 0 {
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35) {
                        self.resolveProfilePhotoURL(
                            for: imageRef,
                            retriesRemaining: retriesRemaining - 1,
                            completion: completion
                        )
                    }
                    return
                }

                completion(nil, error)
                return
            }

            completion(url, nil)
        }
    }

    private func isStorageObjectNotFound(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == StorageErrorDomain
            && nsError.code == StorageErrorCode.objectNotFound.rawValue
    }

    private func friendlyProfilePhotoErrorMessage(from error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == StorageErrorDomain {
            switch nsError.code {
            case StorageErrorCode.objectNotFound.rawValue:
                return "Profile photo is still processing. Please try again in a moment."
            case StorageErrorCode.unauthorized.rawValue:
                return "Could not access profile photo. Check Firebase Storage rules."
            default:
                return "Profile photo upload failed. Please try again."
            }
        }

        return "Profile photo upload failed. Please try again."
    }

    func toggleInterest(_ interest: String) {
        if selectedInterests.contains(interest) {
            selectedInterests.removeAll { $0 == interest }
        } else {
            selectedInterests.append(interest)
        }
    }

    func saveInterests() {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Login required to update interests."
            return
        }

        isSavingInterests = true
        errorMessage = nil
        successMessage = nil

        db.collection("users").document(user.uid).setData([
            "interests": selectedInterests
        ], merge: true) { [weak self] error in
            DispatchQueue.main.async {
                self?.isSavingInterests = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.successMessage = "Interests saved successfully!"
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

class PrivacyViewModel: ObservableObject {
    @Published var isProfilePublic: Bool = true
    @Published var messagePermission: MessagePermission = .everyone
    @Published var isLoadingSettings: Bool = false
    @Published var isSavingSettings: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let db = Firestore.firestore()

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    func loadSettings() {
        guard let uid = currentUserId else {
            errorMessage = "Login required to load privacy settings."
            return
        }

        isLoadingSettings = true
        errorMessage = nil

        db.collection("users").document(uid).getDocument { [weak self] document, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.isLoadingSettings = false

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                let data = document?.data() ?? [:]

                // Default behavior: public profile and everyone can message.
                self.isProfilePublic = data["isProfilePublic"] as? Bool ?? true

                let permissionRaw = data["messagePermission"] as? String ?? MessagePermission.everyone.rawValue
                self.messagePermission = MessagePermission(rawValue: permissionRaw) ?? .everyone

                self.ensureDefaultsExistForMissingFields(existingData: data, userId: uid)
            }
        }
    }

    func updateProfileVisibility(isPublic: Bool) {
        isProfilePublic = isPublic
        saveSettings()
    }

    func updateMessagePermission(_ permission: MessagePermission) {
        messagePermission = permission
        saveSettings()
    }

    private func saveSettings() {
        guard let uid = currentUserId else {
            errorMessage = "Login required to save privacy settings."
            return
        }

        isSavingSettings = true
        errorMessage = nil

        let payload: [String: Any] = [
            "isProfilePublic": isProfilePublic,
            "messagePermission": messagePermission.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        db.collection("users").document(uid).setData(payload, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSavingSettings = false

                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.successMessage = "Privacy settings updated."
                }
            }
        }
    }

    private func ensureDefaultsExistForMissingFields(existingData: [String: Any], userId: String) {
        var defaultsToSave: [String: Any] = [:]

        if existingData["isProfilePublic"] == nil {
            defaultsToSave["isProfilePublic"] = true
        }

        if existingData["messagePermission"] == nil {
            defaultsToSave["messagePermission"] = MessagePermission.everyone.rawValue
        }

        guard !defaultsToSave.isEmpty else { return }

        db.collection("users").document(userId).setData(defaultsToSave, merge: true)
    }
}

class FriendsViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var searchResults: [AppUser] = []
    @Published var incomingRequests: [FriendRequestItem] = []
    @Published var sentRequests: [FriendRequestItem] = []
    @Published var friends: [AppUser] = []
    @Published var isLoadingSearch: Bool = false
    @Published var isLoadingRequests: Bool = false
    @Published var isLoadingFriends: Bool = false
    @Published var isLoadingDiscovery: Bool = false
    @Published var allDiscoveredUsers: [AppUser] = []
    @Published var filteredAllUsers: [AppUser] = []
    @Published var suggestedForYouUsers: [AppUser] = []
    @Published var peopleYouMayKnowUsers: [AppUser] = []
    @Published var searchText: String = ""
    @Published var processingUserIds: Set<String> = []
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private struct SocialUserSignals {
        var likedArticleKeys: Set<String> = []
        var bookmarkedArticleKeys: Set<String> = []
        var friendIds: Set<String> = []
        var recentActivityCount: Int = 0
        var latestActivityAt: Date?
        var likesCount: Int = 0
        var bookmarksCount: Int = 0
        var readsCount: Int = 0
    }

    private let db = Firestore.firestore()
    private var incomingRequestsListener: ListenerRegistration?
    private var sentRequestsListener: ListenerRegistration?
    private var friendsListener: ListenerRegistration?
    private var usersListener: ListenerRegistration?
    private var currentUserProfileListener: ListenerRegistration?
    private var myLikesListener: ListenerRegistration?
    private var myBookmarksListener: ListenerRegistration?
    private var myReadsListener: ListenerRegistration?

    private var discoveredUsersById: [String: AppUser] = [:]
    private var enrichedUsersById: [String: AppUser] = [:]
    private var signalsByUserId: [String: SocialUserSignals] = [:]
    private var usersBeingScored: Set<String> = []

    private var myFriendIds: Set<String> = []
    private var myInterestKeywords: Set<String> = []
    private var myLikedArticleKeys: Set<String> = []
    private var myBookmarkedArticleKeys: Set<String> = []

    private var didAttemptLegacyFriendMigration = false

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    deinit {
        stopListening()
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    func startListening() {
        guard let uid = currentUserId else {
            clearData()
            return
        }

        stopListening()
        isLoadingRequests = true
        isLoadingFriends = true
        isLoadingDiscovery = true
        didAttemptLegacyFriendMigration = false

        attachRequestListeners(for: uid)
        attachFriendsListener(for: uid)
        attachDiscoveryListeners(for: uid)
    }

    func stopListening() {
        incomingRequestsListener?.remove()
        incomingRequestsListener = nil
        sentRequestsListener?.remove()
        sentRequestsListener = nil
        friendsListener?.remove()
        friendsListener = nil
        usersListener?.remove()
        usersListener = nil
        currentUserProfileListener?.remove()
        currentUserProfileListener = nil
        myLikesListener?.remove()
        myLikesListener = nil
        myBookmarksListener?.remove()
        myBookmarksListener = nil
        myReadsListener?.remove()
        myReadsListener = nil
    }

    func searchUsers() {
        searchUsers(query: searchQuery)
    }

    func searchUsers(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isLoadingSearch = false
            return
        }

        isLoadingSearch = true
        let normalized = trimmed.lowercased()

        let filtered = allDiscoveredUsers.filter { user in
            user.name.lowercased().contains(normalized) ||
            user.email.lowercased().contains(normalized)
        }

        DispatchQueue.main.async {
            self.searchResults = filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            self.isLoadingSearch = false
        }
    }

    func updateDiscoverySearch(_ value: String) {
        searchText = value
        applyDiscoveryFilter()
    }

    func friendActionState(for user: AppUser) -> FriendActionState {
        if isFriend(userId: user.id) {
            return .friends
        }

        if hasPendingRequest(with: user.id) {
            return .requested
        }

        return .addFriend
    }

    func enrichedUser(for userId: String) -> AppUser? {
        if let enriched = enrichedUsersById[userId] {
            return enriched
        }

        if let base = discoveredUsersById[userId] {
            return base
        }

        return friends.first { $0.id == userId }
    }

    func prefetchUserDetails(for userId: String) {
        if discoveredUsersById[userId] == nil {
            db.collection("users").document(userId).getDocument { [weak self] snapshot, _ in
                guard let self = self, let snapshot = snapshot, snapshot.exists else { return }

                let data = snapshot.data() ?? [:]
                let permissionRaw = data["messagePermission"] as? String ?? MessagePermission.everyone.rawValue
                let permission = MessagePermission(rawValue: permissionRaw) ?? .everyone

                let user = AppUser(
                    id: snapshot.documentID,
                    name: data["name"] as? String ?? "User",
                    email: data["email"] as? String ?? "",
                    profileImageURL: data["profileImageUrl"] as? String ?? "",
                    isProfilePublic: data["isProfilePublic"] as? Bool ?? true,
                    messagePermission: permission,
                    interests: data["interests"] as? [String] ?? []
                )

                DispatchQueue.main.async {
                    self.discoveredUsersById[user.id] = user
                    self.refreshRecommendationSections()
                }
            }
        }

        prefetchSignalsIfNeeded(for: userId)
    }

    func recentActivityDescription(for user: AppUser) -> String {
        guard let recent = user.recentActivityAt else {
            return "No recent activity captured yet."
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: recent, relativeTo: Date())
        return "Last active \(relative)."
    }

    func sendFriendRequest(to user: AppUser) {
        guard let sender = Auth.auth().currentUser else {
            errorMessage = "Login required to send friend requests."
            return
        }

        if isFriend(userId: user.id) {
            successMessage = "You are already friends."
            return
        }

        if hasPendingRequest(with: user.id) {
            successMessage = "Friend request already pending."
            return
        }

        processingUserIds.insert(user.id)
        clearMessages()

        let senderToReceiverId = friendRequestId(senderId: sender.uid, receiverId: user.id)
        let receiverToSenderId = friendRequestId(senderId: user.id, receiverId: sender.uid)

        let senderRequestRef = db.collection("friendRequests").document(senderToReceiverId)
        let reverseRequestRef = db.collection("friendRequests").document(receiverToSenderId)

        reverseRequestRef.getDocument { reverseDoc, reverseError in
            if let reverseError = reverseError {
                DispatchQueue.main.async {
                    self.errorMessage = reverseError.localizedDescription
                    self.processingUserIds.remove(user.id)
                }
                return
            }

            if let reverseData = reverseDoc?.data(),
               let status = reverseData["status"] as? String,
               status == "pending" {
                DispatchQueue.main.async {
                    self.errorMessage = "This user has already sent you a request. Check Friend Requests."
                    self.processingUserIds.remove(user.id)
                }
                return
            }

            senderRequestRef.getDocument { existingDoc, existingError in
                if let existingError = existingError {
                    DispatchQueue.main.async {
                        self.errorMessage = existingError.localizedDescription
                        self.processingUserIds.remove(user.id)
                    }
                    return
                }

                if let existingData = existingDoc?.data(),
                   let status = existingData["status"] as? String {
                    DispatchQueue.main.async {
                        if status == "pending" {
                            self.successMessage = "Friend request already pending."
                        } else if status == "accepted" {
                            self.successMessage = "You are already friends."
                        } else {
                            self.createFriendRequest(to: user, senderRequestRef: senderRequestRef, sender: sender)
                            return
                        }
                        self.processingUserIds.remove(user.id)
                    }
                    return
                }

                self.createFriendRequest(to: user, senderRequestRef: senderRequestRef, sender: sender)
            }
        }
    }

    func accept(request: FriendRequestItem) {
        guard currentUserId != nil else {
            errorMessage = "Login required to accept requests."
            return
        }

        processingUserIds.insert(request.senderId)
        let requestRef = db.collection("friendRequests").document(request.id)

        let senderMirrorRequestRef = db.collection("users")
            .document(request.senderId)
            .collection("friendRequests")
            .document(request.receiverId)

        let receiverMirrorRequestRef = db.collection("users")
            .document(request.receiverId)
            .collection("friendRequests")
            .document(request.senderId)

        let receiverFriendRef = db.collection("users")
            .document(request.receiverId)
            .collection("friends")
            .document(request.senderId)

        let senderFriendRef = db.collection("users")
            .document(request.senderId)
            .collection("friends")
            .document(request.receiverId)

        let acceptedStatus: [String: Any] = [
            "status": "accepted",
            "respondedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let batch = db.batch()
        batch.setData(acceptedStatus, forDocument: requestRef, merge: true)
        batch.setData(acceptedStatus, forDocument: senderMirrorRequestRef, merge: true)
        batch.setData(acceptedStatus, forDocument: receiverMirrorRequestRef, merge: true)

        batch.setData([
            "friendId": request.senderId,
            "friendName": request.senderName,
            "friendEmail": request.senderEmail,
            "friendPhotoURL": request.senderPhotoURL,
            "since": FieldValue.serverTimestamp()
        ], forDocument: receiverFriendRef, merge: true)

        batch.setData([
            "friendId": request.receiverId,
            "friendName": request.receiverName,
            "friendEmail": request.receiverEmail,
            "friendPhotoURL": request.receiverPhotoURL,
            "since": FieldValue.serverTimestamp()
        ], forDocument: senderFriendRef, merge: true)

        batch.commit { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.processingUserIds.remove(request.senderId)
                }
                return
            }

            let updatesGroup = DispatchGroup()

            updatesGroup.enter()
            self.addFriend(for: request.senderId, friendId: request.receiverId) { _ in
                updatesGroup.leave()
            }

            updatesGroup.enter()
            self.addFriend(for: request.receiverId, friendId: request.senderId) { _ in
                updatesGroup.leave()
            }

            updatesGroup.notify(queue: .main) {
                self.successMessage = "Friend request accepted."
                self.processingUserIds.remove(request.senderId)
                self.startListening()
            }
        }
    }

    func reject(request: FriendRequestItem) {
        processingUserIds.insert(request.senderId)

        let rejectedStatus: [String: Any] = [
            "status": "rejected",
            "respondedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let batch = db.batch()
        let requestRef = db.collection("friendRequests").document(request.id)
        let senderMirrorRequestRef = db.collection("users")
            .document(request.senderId)
            .collection("friendRequests")
            .document(request.receiverId)
        let receiverMirrorRequestRef = db.collection("users")
            .document(request.receiverId)
            .collection("friendRequests")
            .document(request.senderId)

        batch.setData(rejectedStatus, forDocument: requestRef, merge: true)
        batch.setData(rejectedStatus, forDocument: senderMirrorRequestRef, merge: true)
        batch.setData(rejectedStatus, forDocument: receiverMirrorRequestRef, merge: true)

        batch.commit { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.successMessage = "Friend request rejected."
                }
                self.processingUserIds.remove(request.senderId)
            }
        }
    }

    func isFriend(userId: String) -> Bool {
        myFriendIds.contains(userId) || friends.contains { $0.id == userId }
    }

    func canViewProfile(of user: AppUser) -> Bool {
        guard let uid = currentUserId else { return false }
        if user.id == uid { return true }
        return user.isProfilePublic || isFriend(userId: user.id)
    }

    func canMessage(user: AppUser) -> Bool {
        guard let uid = currentUserId else { return false }
        if user.id == uid { return false }

        switch user.messagePermission {
        case .everyone:
            return true
        case .friends:
            return isFriend(userId: user.id)
        }
    }

    func messagingPermissionText(for user: AppUser) -> String {
        user.messagePermission.helperText
    }

    func hasPendingRequest(with userId: String) -> Bool {
        incomingRequests.contains { $0.status == "pending" && $0.senderId == userId } ||
        sentRequests.contains { $0.status == "pending" && $0.receiverId == userId }
    }

    private enum RequestsTarget {
        case incoming
        case sent
    }

    private func attachRequestListeners(for uid: String) {
        incomingRequestsListener = db.collection("friendRequests")
            .whereField("receiverId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                self.handleRequestsSnapshot(snapshot, error: error, target: .incoming)
            }

        sentRequestsListener = db.collection("friendRequests")
            .whereField("senderId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                self.handleRequestsSnapshot(snapshot, error: error, target: .sent)
            }
    }

    private func attachFriendsListener(for uid: String) {
        friendsListener = db.collection("users")
            .document(uid)
            .collection("friends")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.isLoadingFriends = false
                    }
                    return
                }

                let friendIds = snapshot?.documents.compactMap { document -> String? in
                    let explicitId = document.data()["friendId"] as? String
                    return explicitId ?? document.documentID
                } ?? []

                if friendIds.isEmpty, !self.didAttemptLegacyFriendMigration {
                    self.didAttemptLegacyFriendMigration = true
                    self.loadLegacyFriendIds(for: uid)
                    return
                }

                self.updateFriendState(with: friendIds)
            }
    }

    private func attachDiscoveryListeners(for uid: String) {
        currentUserProfileListener = db.collection("users")
            .document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self else { return }
                let interests = snapshot?.data()?["interests"] as? [String] ?? []
                self.myInterestKeywords = self.normalizedKeywords(from: interests)
                self.refreshRecommendationSections()
            }

        myLikesListener = db.collection("users")
            .document(uid)
            .collection("likedArticles")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self else { return }
                let keys = Set((snapshot?.documents ?? []).map { document in
                    self.articleKey(from: document.data(), fallbackDocumentId: document.documentID)
                })
                self.myLikedArticleKeys = keys
                self.refreshRecommendationSections()
            }

        myBookmarksListener = db.collection("users")
            .document(uid)
            .collection("bookmarks")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self = self else { return }
                var keys: Set<String> = []
                (snapshot?.documents ?? []).forEach { document in
                    let data = document.data()
                    let type = (data["type"] as? String ?? "article").lowercased()
                    if type == "article" {
                        keys.insert(self.articleKey(from: data, fallbackDocumentId: document.documentID))
                    }
                }
                self.myBookmarkedArticleKeys = keys
                self.refreshRecommendationSections()
            }

        myReadsListener = db.collection("users")
            .document(uid)
            .collection("readArticles")
            .addSnapshotListener { [weak self] _, _ in
                self?.refreshRecommendationSections()
            }

        usersListener = db.collection("users")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.isLoadingDiscovery = false
                    }
                    return
                }

                var latestUsers: [String: AppUser] = [:]
                (snapshot?.documents ?? []).forEach { document in
                    if document.documentID == uid {
                        return
                    }
                    let user = self.user(from: document)
                    latestUsers[user.id] = user
                }

                let missingIds = Set(self.signalsByUserId.keys).subtracting(latestUsers.keys)
                missingIds.forEach { removedId in
                    self.signalsByUserId.removeValue(forKey: removedId)
                    self.enrichedUsersById.removeValue(forKey: removedId)
                }

                self.discoveredUsersById = latestUsers

                latestUsers.values.forEach { user in
                    self.prefetchSignalsIfNeeded(for: user.id)
                }

                DispatchQueue.main.async {
                    self.isLoadingDiscovery = false
                }

                self.refreshRecommendationSections()
            }
    }

    private func loadLegacyFriendIds(for uid: String) {
        db.collection("friends").document(uid).getDocument { snapshot, _ in
            let legacyIds = snapshot?.data()?["friendIds"] as? [String] ?? []

            if !legacyIds.isEmpty {
                self.mirrorLegacyFriendsToSubcollection(ownerId: uid, friendIds: legacyIds)
            }

            self.updateFriendState(with: legacyIds)
        }
    }

    private func mirrorLegacyFriendsToSubcollection(ownerId: String, friendIds: [String]) {
        let now = FieldValue.serverTimestamp()
        friendIds.forEach { friendId in
            db.collection("users")
                .document(ownerId)
                .collection("friends")
                .document(friendId)
                .setData([
                    "friendId": friendId,
                    "since": now
                ], merge: true)
        }
    }

    private func updateFriendState(with friendIds: [String]) {
        myFriendIds = Set(friendIds)
        fetchFriendsDetails(friendIds: friendIds)
        refreshRecommendationSections()
    }

    private func createFriendRequest(to user: AppUser, senderRequestRef: DocumentReference, sender: User) {
        db.collection("users").document(sender.uid).getDocument { currentUserDoc, currentUserError in
            if let currentUserError = currentUserError {
                DispatchQueue.main.async {
                    self.errorMessage = currentUserError.localizedDescription
                    self.processingUserIds.remove(user.id)
                }
                return
            }

            let currentData = currentUserDoc?.data() ?? [:]
            let senderName = currentData["name"] as? String ?? sender.displayName ?? "User"
            let senderEmail = currentData["email"] as? String ?? sender.email ?? ""
            let senderPhoto = currentData["profileImageUrl"] as? String ?? ""

            let canonicalData: [String: Any] = [
                "senderId": sender.uid,
                "receiverId": user.id,
                "senderName": senderName,
                "senderEmail": senderEmail,
                "senderPhotoURL": senderPhoto,
                "receiverName": user.name,
                "receiverEmail": user.email,
                "receiverPhotoURL": user.profileImageURL,
                "status": "pending",
                "timestamp": FieldValue.serverTimestamp()
            ]

            let senderSubcollectionRef = self.db.collection("users")
                .document(sender.uid)
                .collection("friendRequests")
                .document(user.id)

            let receiverSubcollectionRef = self.db.collection("users")
                .document(user.id)
                .collection("friendRequests")
                .document(sender.uid)

            let senderMirrorData: [String: Any] = [
                "senderId": sender.uid,
                "receiverId": user.id,
                "peerId": user.id,
                "peerName": user.name,
                "peerEmail": user.email,
                "peerPhotoURL": user.profileImageURL,
                "direction": "sent",
                "status": "pending",
                "timestamp": FieldValue.serverTimestamp(),
                "requestId": senderRequestRef.documentID
            ]

            let receiverMirrorData: [String: Any] = [
                "senderId": sender.uid,
                "receiverId": user.id,
                "peerId": sender.uid,
                "peerName": senderName,
                "peerEmail": senderEmail,
                "peerPhotoURL": senderPhoto,
                "direction": "received",
                "status": "pending",
                "timestamp": FieldValue.serverTimestamp(),
                "requestId": senderRequestRef.documentID
            ]

            let batch = self.db.batch()
            batch.setData(canonicalData, forDocument: senderRequestRef, merge: true)
            batch.setData(senderMirrorData, forDocument: senderSubcollectionRef, merge: true)
            batch.setData(receiverMirrorData, forDocument: receiverSubcollectionRef, merge: true)

            batch.commit { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.successMessage = "Friend request sent."
                        self.startListening()
                    }
                    self.processingUserIds.remove(user.id)
                }
            }
        }
    }

    private func addFriend(for userId: String, friendId: String, completion: @escaping (Error?) -> Void) {
        db.collection("friends").document(userId).setData([
            "userId": userId,
            "friendIds": FieldValue.arrayUnion([friendId]),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true, completion: completion)
    }

    private func handleRequestsSnapshot(_ snapshot: QuerySnapshot?, error: Error?, target: RequestsTarget) {
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoadingRequests = false
            }
            return
        }

        let requests = snapshot?.documents.compactMap { document -> FriendRequestItem? in
            let data = document.data()
            guard
                let senderId = data["senderId"] as? String,
                let receiverId = data["receiverId"] as? String,
                let status = data["status"] as? String
            else {
                return nil
            }

            return FriendRequestItem(
                id: document.documentID,
                senderId: senderId,
                receiverId: receiverId,
                senderName: data["senderName"] as? String ?? "User",
                senderEmail: data["senderEmail"] as? String ?? "",
                senderPhotoURL: data["senderPhotoURL"] as? String ?? "",
                receiverName: data["receiverName"] as? String ?? "User",
                receiverEmail: data["receiverEmail"] as? String ?? "",
                receiverPhotoURL: data["receiverPhotoURL"] as? String ?? "",
                status: status,
                timestamp: (data["timestamp"] as? Timestamp)?.dateValue()
            )
        } ?? []

        DispatchQueue.main.async {
            switch target {
            case .incoming:
                self.incomingRequests = requests.sorted {
                    ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
                }
            case .sent:
                self.sentRequests = requests.sorted {
                    ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
                }
            }

            self.isLoadingRequests = false
            self.refreshRecommendationSections()
        }
    }

    private func fetchFriendsDetails(friendIds: [String]) {
        guard !friendIds.isEmpty else {
            DispatchQueue.main.async {
                self.friends = []
                self.isLoadingFriends = false
            }
            return
        }

        let chunks = chunked(friendIds, size: 10)
        var collected: [String: AppUser] = [:]
        let group = DispatchGroup()

        for chunk in chunks {
            group.enter()
            db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments { snapshot, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.errorMessage = error.localizedDescription
                        }
                    } else {
                        snapshot?.documents.forEach { document in
                            let user = self.user(from: document)
                            collected[user.id] = self.enrichedUsersById[user.id] ?? user
                        }
                    }
                    group.leave()
                }
        }

        group.notify(queue: .main) {
            self.friends = collected.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            self.isLoadingFriends = false
        }
    }

    private func prefetchSignalsIfNeeded(for userId: String) {
        if signalsByUserId[userId] != nil || usersBeingScored.contains(userId) {
            return
        }

        usersBeingScored.insert(userId)

        fetchSocialSignals(for: userId) { signals in
            DispatchQueue.main.async {
                self.signalsByUserId[userId] = signals
                self.usersBeingScored.remove(userId)
                self.refreshRecommendationSections()
            }
        }
    }

    private func fetchSocialSignals(for userId: String, completion: @escaping (SocialUserSignals) -> Void) {
        var signals = SocialUserSignals()
        let threshold = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date().addingTimeInterval(-1_209_600)
        let group = DispatchGroup()

        func registerRecentActivity(_ value: Any?) {
            guard let date = timestampDate(from: value) else { return }
            if date >= threshold {
                signals.recentActivityCount += 1
            }
            if let latest = signals.latestActivityAt {
                if date > latest {
                    signals.latestActivityAt = date
                }
            } else {
                signals.latestActivityAt = date
            }
        }

        group.enter()
        db.collection("users")
            .document(userId)
            .collection("likedArticles")
            .limit(to: 200)
            .getDocuments { snapshot, _ in
                let docs = snapshot?.documents ?? []
                signals.likesCount = docs.count
                docs.forEach { document in
                    let data = document.data()
                    signals.likedArticleKeys.insert(self.articleKey(from: data, fallbackDocumentId: document.documentID))
                    registerRecentActivity(data["timestamp"])
                }
                group.leave()
            }

        group.enter()
        db.collection("users")
            .document(userId)
            .collection("bookmarks")
            .limit(to: 200)
            .getDocuments { snapshot, _ in
                let docs = snapshot?.documents ?? []
                var bookmarkCount = 0
                docs.forEach { document in
                    let data = document.data()
                    let type = (data["type"] as? String ?? "article").lowercased()
                    if type == "article" {
                        bookmarkCount += 1
                        signals.bookmarkedArticleKeys.insert(self.articleKey(from: data, fallbackDocumentId: document.documentID))
                        registerRecentActivity(data["timestamp"])
                    }
                }
                signals.bookmarksCount = bookmarkCount
                group.leave()
            }

        group.enter()
        db.collection("users")
            .document(userId)
            .collection("readArticles")
            .limit(to: 200)
            .getDocuments { snapshot, _ in
                let docs = snapshot?.documents ?? []
                signals.readsCount = docs.count
                docs.forEach { document in
                    let data = document.data()
                    registerRecentActivity(data["timestamp"])
                }
                group.leave()
            }

        group.enter()
        db.collection("users")
            .document(userId)
            .collection("friends")
            .getDocuments { snapshot, _ in
                let docs = snapshot?.documents ?? []
                if !docs.isEmpty {
                    signals.friendIds = Set(docs.compactMap { document in
                        (document.data()["friendId"] as? String) ?? document.documentID
                    })
                    group.leave()
                    return
                }

                self.db.collection("friends").document(userId).getDocument { legacySnapshot, _ in
                    let friendIds = legacySnapshot?.data()?["friendIds"] as? [String] ?? []
                    signals.friendIds = Set(friendIds)
                    group.leave()
                }
            }

        group.notify(queue: .global(qos: .userInitiated)) {
            completion(signals)
        }
    }

    private func refreshRecommendationSections() {
        DispatchQueue.main.async {
            let enrichedUsers = self.discoveredUsersById.values.map { user -> AppUser in
                let signals = self.signalsByUserId[user.id] ?? SocialUserSignals()
                let mutualCount = self.myFriendIds.intersection(signals.friendIds).count
                let score = self.recommendationScore(for: user, with: signals, mutualFriendCount: mutualCount)

                return AppUser(
                    id: user.id,
                    name: user.name,
                    email: user.email,
                    profileImageURL: user.profileImageURL,
                    isProfilePublic: user.isProfilePublic,
                    messagePermission: user.messagePermission,
                    interests: user.interests,
                    likesCount: signals.likesCount,
                    bookmarksCount: signals.bookmarksCount,
                    readsCount: signals.readsCount,
                    mutualFriendsCount: mutualCount,
                    recommendationScore: score,
                    recentActivityAt: signals.latestActivityAt
                )
            }

            self.enrichedUsersById = Dictionary(uniqueKeysWithValues: enrichedUsers.map { ($0.id, $0) })

            self.allDiscoveredUsers = enrichedUsers.sorted { lhs, rhs in
                if lhs.recommendationScore == rhs.recommendationScore {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.recommendationScore > rhs.recommendationScore
            }

            let discoveryPool = self.allDiscoveredUsers.filter { candidate in
                !self.isFriend(userId: candidate.id) && !self.hasPendingRequest(with: candidate.id)
            }

            self.suggestedForYouUsers = Array(discoveryPool.prefix(8))
            self.peopleYouMayKnowUsers = Array(
                discoveryPool
                    .filter { $0.mutualFriendsCount > 0 }
                    .sorted { lhs, rhs in
                        if lhs.mutualFriendsCount == rhs.mutualFriendsCount {
                            return lhs.recommendationScore > rhs.recommendationScore
                        }
                        return lhs.mutualFriendsCount > rhs.mutualFriendsCount
                    }
                    .prefix(8)
            )

            self.applyDiscoveryFilter()

            let trimmedSearch = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSearch.isEmpty {
                self.searchUsers(query: trimmedSearch)
            }
        }
    }

    private func recommendationScore(for user: AppUser, with signals: SocialUserSignals, mutualFriendCount: Int) -> Double {
        let userInterests = normalizedKeywords(from: user.interests)
        let sharedInterests = userInterests.intersection(myInterestKeywords).count

        let likedOverlap = signals.likedArticleKeys.intersection(myLikedArticleKeys).count
        let bookmarkedOverlap = signals.bookmarkedArticleKeys.intersection(myBookmarkedArticleKeys).count

        let mutualBoost = Double(mutualFriendCount) * 14.0
        let interestBoost = Double(sharedInterests) * 25.0
        let behavioralBoost = Double(likedOverlap) * 8.0 + Double(bookmarkedOverlap) * 6.0

        let recencyBoost: Double
        if let latest = signals.latestActivityAt {
            let days = max(0, Date().timeIntervalSince(latest) / 86_400)
            recencyBoost = max(0, 12 - days)
        } else {
            recencyBoost = 0
        }

        let activityBoost = Double(signals.recentActivityCount) * 1.5

        return interestBoost + behavioralBoost + mutualBoost + activityBoost + recencyBoost
    }

    private func applyDiscoveryFilter() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            filteredAllUsers = allDiscoveredUsers
            return
        }

        let normalized = trimmed.lowercased()
        filteredAllUsers = allDiscoveredUsers.filter { user in
            if user.name.lowercased().contains(normalized) || user.email.lowercased().contains(normalized) {
                return true
            }

            return user.interests.contains { interest in
                interest.lowercased().contains(normalized)
            }
        }
    }

    private func normalizedKeywords(from values: [String]) -> Set<String> {
        Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }

    private func articleKey(from data: [String: Any], fallbackDocumentId: String) -> String {
        if let url = data["url"] as? String, !url.isEmpty {
            return "url::\(url.lowercased())"
        }

        if let title = data["title"] as? String, !title.isEmpty {
            return "title::\(title.lowercased())"
        }

        return "doc::\(fallbackDocumentId.lowercased())"
    }

    private func timestampDate(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }

        if let date = value as? Date {
            return date
        }

        return nil
    }

    private func user(from document: QueryDocumentSnapshot) -> AppUser {
        let data = document.data()
        let name = data["name"] as? String ?? "User"
        let email = data["email"] as? String ?? ""
        let photoURL = data["profileImageUrl"] as? String ?? ""
        let isProfilePublic = data["isProfilePublic"] as? Bool ?? true
        let permissionRaw = data["messagePermission"] as? String ?? MessagePermission.everyone.rawValue
        let messagePermission = MessagePermission(rawValue: permissionRaw) ?? .everyone
        let interests = data["interests"] as? [String] ?? []

        return AppUser(
            id: document.documentID,
            name: name,
            email: email,
            profileImageURL: photoURL,
            isProfilePublic: isProfilePublic,
            messagePermission: messagePermission,
            interests: interests
        )
    }

    private func friendRequestId(senderId: String, receiverId: String) -> String {
        "\(senderId)_\(receiverId)"
    }

    private func clearData() {
        searchResults = []
        incomingRequests = []
        sentRequests = []
        friends = []
        allDiscoveredUsers = []
        filteredAllUsers = []
        suggestedForYouUsers = []
        peopleYouMayKnowUsers = []
        isLoadingSearch = false
        isLoadingRequests = false
        isLoadingFriends = false
        isLoadingDiscovery = false
        processingUserIds = []

        discoveredUsersById.removeAll()
        enrichedUsersById.removeAll()
        signalsByUserId.removeAll()
        usersBeingScored.removeAll()
        myFriendIds.removeAll()
        myInterestKeywords.removeAll()
        myLikedArticleKeys.removeAll()
        myBookmarkedArticleKeys.removeAll()
        didAttemptLegacyFriendMigration = false
    }

    private func chunked(_ source: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [source] }
        var result: [[String]] = []
        var index = 0

        while index < source.count {
            let end = min(index + size, source.count)
            result.append(Array(source[index..<end]))
            index += size
        }

        return result
    }

}

class UserActivityViewModel: ObservableObject {
    @Published var likedHistory: [ActivityHistoryItem] = []
    @Published var readingHistory: [ActivityHistoryItem] = []
    @Published var isLoadingActivity: Bool = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var likedListener: ListenerRegistration?
    private var readingListener: ListenerRegistration?

    var likesCount: Int {
        likedHistory.count
    }

    var readCount: Int {
        readingHistory.count
    }

    deinit {
        stopListening()
    }

    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else {
            clearActivity()
            return
        }

        stopListening()
        isLoadingActivity = true

        let userDocument = db.collection("users").document(userId)

        likedListener = userDocument.collection("likedArticles")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                self.handleActivitySnapshot(
                    snapshot,
                    error: error,
                    target: .liked
                )
            }

        readingListener = userDocument.collection("readArticles")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                self.handleActivitySnapshot(
                    snapshot,
                    error: error,
                    target: .reading
                )
            }
    }

    func stopListening() {
        likedListener?.remove()
        likedListener = nil
        readingListener?.remove()
        readingListener = nil
    }

    func trackArticleRead(article: Article) {
        guard let userId = Auth.auth().currentUser?.uid else {
            return
        }

        let readData: [String: Any] = [
            "title": article.title,
            "url": article.url as Any,
            "image": article.urlToImage as Any,
            "source": sourceName(from: article.url),
            "timestamp": FieldValue.serverTimestamp(),
            "ownerId": userId
        ]

        db.collection("users")
            .document(userId)
            .collection("readArticles")
            .document(articleDocumentId(for: article))
            .setData(readData, merge: true) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
    }

    private enum ActivityTarget {
        case liked
        case reading
    }

    private func handleActivitySnapshot(
        _ snapshot: QuerySnapshot?,
        error: Error?,
        target: ActivityTarget
    ) {
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoadingActivity = false
            }
            return
        }

        let entries = snapshot?.documents.compactMap { historyItem(from: $0) } ?? []

        DispatchQueue.main.async {
            switch target {
            case .liked:
                self.likedHistory = entries
            case .reading:
                self.readingHistory = entries
            }
            self.errorMessage = nil
            self.isLoadingActivity = false
        }
    }

    private func historyItem(from document: QueryDocumentSnapshot) -> ActivityHistoryItem? {
        let data = document.data()
        let title = data["title"] as? String ?? ""

        guard !title.isEmpty else {
            return nil
        }

        let url = data["url"] as? String
        let image = data["image"] as? String ?? data["urlToImage"] as? String
        let source = data["source"] as? String ?? sourceName(from: url)
        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue()

        let article = Article(
            title: title,
            description: data["description"] as? String,
            urlToImage: image,
            url: url
        )

        return ActivityHistoryItem(
            id: document.documentID,
            article: article,
            source: source,
            timestamp: timestamp
        )
    }

    private func clearActivity() {
        likedHistory = []
        readingHistory = []
        errorMessage = nil
        isLoadingActivity = false
    }

    private func sourceName(from urlString: String?) -> String {
        guard
            let urlString,
            let host = URL(string: urlString)?.host
        else {
            return "Unknown Source"
        }

        let cleanedHost = host.replacingOccurrences(of: "www.", with: "")
        return cleanedHost.capitalized
    }

    private func articleDocumentId(for article: Article) -> String {
        if let url = article.url, !url.isEmpty {
            return safeDocumentId(from: url)
        }
        return safeDocumentId(from: article.title.lowercased())
    }

    private func safeDocumentId(from rawValue: String) -> String {
        let encoded = Data(rawValue.utf8).base64EncodedString()
        return encoded
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
