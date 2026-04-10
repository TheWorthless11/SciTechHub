import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

enum CommentSortOption: String, CaseIterable, Identifiable {
    case top
    case new

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .top:
            return "Top"
        case .new:
            return "New"
        }
    }
}

struct ArticleComment: Identifiable, Hashable {
    let id: String
    let articleId: String
    let parentId: String?
    let authorId: String
    let authorName: String
    let authorPhotoURL: String
    let text: String
    let createdAt: Date
    let likedBy: [String]

    var likesCount: Int {
        likedBy.count
    }
}

struct CommentThread: Identifiable, Hashable {
    let root: ArticleComment
    let replies: [ArticleComment]

    var id: String {
        root.id
    }
}

@MainActor
final class ArticleCommentViewModel: ObservableObject {
    @Published private(set) var comments: [ArticleComment] = []
    @Published var draftCommentText = ""
    @Published var sortOption: CommentSortOption = .top
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published private(set) var pendingLikeCommentIds: Set<String> = []
    @Published var errorMessage: String?
    @Published var replyingTo: ArticleComment?

    private let db = Firestore.firestore()
    private var commentsListener: ListenerRegistration?
    private var activeArticleId: String?

    var canPost: Bool {
        !draftCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
    }

    var threadedComments: [CommentThread] {
        var repliesByParentId: [String: [ArticleComment]] = [:]

        comments.forEach { comment in
            if let parentId = comment.parentId {
                repliesByParentId[parentId, default: []].append(comment)
            }
        }

        let roots = sortedRootComments(from: comments.filter { $0.parentId == nil })

        return roots.map { root in
            let replies = (repliesByParentId[root.id] ?? []).sorted { $0.createdAt < $1.createdAt }
            return CommentThread(root: root, replies: replies)
        }
    }

    var renderKey: String {
        comments.map { $0.id }.joined(separator: "|")
    }

    func startListening(for article: Article) {
        let articleId = articleDocumentId(for: article)

        if activeArticleId == articleId, commentsListener != nil {
            return
        }

        stopListening(clearState: false)

        activeArticleId = articleId
        isLoading = true
        errorMessage = nil

        commentsListener = commentsCollection(for: articleId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "load comments")
                        self.isLoading = false
                        return
                    }

                    let latestComments: [ArticleComment] = (snapshot?.documents ?? []).compactMap { document in
                        self.comment(from: document)
                    }

                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.comments = latestComments
                    }

                    self.errorMessage = nil
                    self.isLoading = false
                }
            }
    }

    func stopListening(clearState: Bool = true) {
        commentsListener?.remove()
        commentsListener = nil
        activeArticleId = nil

        if clearState {
            comments = []
            replyingTo = nil
            draftCommentText = ""
            pendingLikeCommentIds = []
            isLoading = false
            isPosting = false
            errorMessage = nil
        }
    }

    func beginReply(to comment: ArticleComment) {
        replyingTo = comment
    }

    func cancelReply() {
        replyingTo = nil
    }

    func postComment(for article: Article) {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Login required to post comments."
            return
        }

        guard let articleId = activeArticleId ?? Optional(articleDocumentId(for: article)) else {
            errorMessage = "Unable to resolve article comments."
            return
        }

        let trimmedText = draftCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        if isPosting {
            return
        }

        isPosting = true
        errorMessage = nil

        resolveCurrentUserProfile(for: user) { [weak self] authorName, authorPhotoURL in
            guard let self = self else { return }

            var payload: [String: Any] = [
                "articleId": articleId,
                "authorId": user.uid,
                "authorName": authorName,
                "authorPhotoURL": authorPhotoURL,
                "text": trimmedText,
                "createdAt": FieldValue.serverTimestamp(),
                "likedBy": []
            ]

            if let replyTarget = self.replyingTo {
                payload["parentId"] = self.rootParentId(for: replyTarget)
            }

            self.commentsCollection(for: articleId).addDocument(data: payload) { error in
                DispatchQueue.main.async {
                    self.isPosting = false

                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "post comment")
                        return
                    }

                    self.draftCommentText = ""
                    self.replyingTo = nil
                    self.errorMessage = nil
                }
            }
        }
    }

    func toggleLike(for comment: ArticleComment) {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Login required to like comments."
            return
        }

        guard let articleId = activeArticleId else {
            return
        }

        if pendingLikeCommentIds.contains(comment.id) {
            return
        }

        pendingLikeCommentIds.insert(comment.id)
        errorMessage = nil

        let isLiked = comment.likedBy.contains(userId)
        let updateValue = isLiked
            ? FieldValue.arrayRemove([userId])
            : FieldValue.arrayUnion([userId])

        commentsCollection(for: articleId)
            .document(comment.id)
            .updateData(["likedBy": updateValue]) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.pendingLikeCommentIds.remove(comment.id)

                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "like comment")
                    }
                }
            }
    }

    private func commentsCollection(for articleId: String) -> CollectionReference {
        db.collection("articles")
            .document(articleId)
            .collection("comments")
    }

    private func articleDocumentId(for article: Article) -> String {
        let source = article.id
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func rootParentId(for comment: ArticleComment) -> String {
        comment.parentId ?? comment.id
    }

    private func sortedRootComments(from roots: [ArticleComment]) -> [ArticleComment] {
        switch sortOption {
        case .top:
            return roots.sorted {
                if $0.likesCount == $1.likesCount {
                    return $0.createdAt > $1.createdAt
                }
                return $0.likesCount > $1.likesCount
            }
        case .new:
            return roots.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func comment(from document: QueryDocumentSnapshot) -> ArticleComment? {
        let data = document.data()

        guard let articleId = data["articleId"] as? String,
              let authorId = data["authorId"] as? String,
              let text = data["text"] as? String else {
            return nil
        }

        let authorName = data["authorName"] as? String ?? "User"
        let authorPhotoURL = data["authorPhotoURL"] as? String ?? ""
        let parentId = data["parentId"] as? String
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let likedBy = data["likedBy"] as? [String] ?? []

        return ArticleComment(
            id: document.documentID,
            articleId: articleId,
            parentId: parentId,
            authorId: authorId,
            authorName: authorName,
            authorPhotoURL: authorPhotoURL,
            text: text,
            createdAt: createdAt,
            likedBy: likedBy
        )
    }

    private func resolveCurrentUserProfile(for user: User, completion: @escaping (String, String) -> Void) {
        db.collection("users")
            .document(user.uid)
            .getDocument { snapshot, _ in
                let data = snapshot?.data() ?? [:]
                let name = (data["name"] as? String)
                    ?? user.displayName
                    ?? user.email
                    ?? "User"
                let photoURL = data["profileImageUrl"] as? String ?? ""
                completion(name, photoURL)
            }
    }

    private func friendlyErrorMessage(for error: Error, action: String) -> String {
        let nsError = error as NSError

        if nsError.domain == FirestoreErrorDomain {
            switch nsError.code {
            case FirestoreErrorCode.permissionDenied.rawValue:
                return "You do not have permission to \(action)."
            case FirestoreErrorCode.unavailable.rawValue:
                return "Network unavailable. Please try again shortly."
            default:
                return "Failed to \(action). Please try again."
            }
        }

        return "Failed to \(action). Please try again."
    }
}

@MainActor
final class ArticleNotesViewModel: ObservableObject {
    @Published var noteText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasSavedNote = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var showDeleteConfirmation = false

    private let db = Firestore.firestore()
    private var configuredUserId: String?
    private var configuredArticleRefId: String?
    private var configuredArticleTitle: String?
    private var configuredDocumentId: String?
    private var successWorkItem: DispatchWorkItem?

    private static var memoryCache: [String: String] = [:]
    private static var recentFetchTimestamps: [String: Date] = [:]
    private static let recentFetchTTL: TimeInterval = 20

    deinit {
        successWorkItem?.cancel()
    }

    func configure(for article: Article, currentUser: User?) {
        guard let userId = currentUser?.uid else {
            resetForGuest()
            return
        }

        let articleRefId = articleReferenceId(for: article)
        let documentId = safeDocumentId(from: articleRefId)

        if configuredUserId == userId,
           configuredDocumentId == documentId {
            return
        }

        configuredUserId = userId
        configuredArticleRefId = articleRefId
        configuredArticleTitle = article.title
        configuredDocumentId = documentId
        errorMessage = nil
        successMessage = nil
        isLoading = true

        if let cachedNote = cachedNote(for: userId, documentId: documentId) {
            noteText = cachedNote
            hasSavedNote = !cachedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            isLoading = false
        } else {
            noteText = ""
            hasSavedNote = false
        }

        let cacheKey = compositeCacheKey(userId: userId, documentId: documentId)
        if let lastFetch = Self.recentFetchTimestamps[cacheKey],
           Date().timeIntervalSince(lastFetch) < Self.recentFetchTTL {
            return
        }

        fetchRemoteNote(userId: userId, documentId: documentId, articleRefId: articleRefId)
    }

    func saveNote() {
        guard let userId = configuredUserId,
              let articleRefId = configuredArticleRefId,
              let articleTitle = configuredArticleTitle,
              let documentId = configuredDocumentId else {
            errorMessage = "Login required to save notes."
            return
        }

        if isSaving {
            return
        }

        isSaving = true
        errorMessage = nil

        let payload: [String: Any] = [
            "ownerId": userId,
            "articleRefId": articleRefId,
            "articleTitle": articleTitle,
            "text": noteText,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        notesDocument(userId: userId, documentId: documentId)
            .setData(payload, merge: true) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isSaving = false

                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "save note")
                        return
                    }

                    self.hasSavedNote = !self.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    self.storeNoteInCache(self.noteText, userId: userId, documentId: documentId)
                    self.bumpRecentFetchTimestamp(userId: userId, documentId: documentId)
                    self.showSuccessMessage("Note saved!")
                }
            }
    }

    func requestDelete() {
        showDeleteConfirmation = true
    }

    func deleteNote() {
        guard let userId = configuredUserId,
              let documentId = configuredDocumentId else {
            errorMessage = "Login required to delete notes."
            return
        }

        showDeleteConfirmation = false
        isSaving = true
        errorMessage = nil

        notesDocument(userId: userId, documentId: documentId)
            .delete { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isSaving = false

                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "delete note")
                        return
                    }

                    self.noteText = ""
                    self.hasSavedNote = false
                    self.removeNoteFromCache(userId: userId, documentId: documentId)
                    self.bumpRecentFetchTimestamp(userId: userId, documentId: documentId)
                    self.showSuccessMessage("Note deleted")
                }
            }
    }

    private func resetForGuest() {
        configuredUserId = nil
        configuredArticleRefId = nil
        configuredArticleTitle = nil
        configuredDocumentId = nil
        noteText = ""
        hasSavedNote = false
        isLoading = false
        isSaving = false
        errorMessage = nil
        successMessage = nil
    }

    private func fetchRemoteNote(userId: String, documentId: String, articleRefId: String) {
        notesDocument(userId: userId, documentId: documentId)
            .getDocument { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }

                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "load note")
                        self.isLoading = false
                        return
                    }

                    let cacheKey = self.compositeCacheKey(userId: userId, documentId: documentId)
                    Self.recentFetchTimestamps[cacheKey] = Date()

                    if let data = snapshot?.data(),
                       let remoteArticleRefId = data["articleRefId"] as? String,
                       remoteArticleRefId == articleRefId {
                        let remoteNote = data["text"] as? String ?? ""
                        self.noteText = remoteNote
                        self.hasSavedNote = !remoteNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        self.storeNoteInCache(remoteNote, userId: userId, documentId: documentId)
                    }

                    self.isLoading = false
                }
            }
    }

    private func notesDocument(userId: String, documentId: String) -> DocumentReference {
        db.collection("users")
            .document(userId)
            .collection("articleNotes")
            .document(documentId)
    }

    private func articleReferenceId(for article: Article) -> String {
        if let articleURL = article.url, !articleURL.isEmpty {
            return articleURL
        }

        return article.id
    }

    private func safeDocumentId(from rawValue: String) -> String {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func compositeCacheKey(userId: String, documentId: String) -> String {
        "\(userId)|\(documentId)"
    }

    private func userDefaultsCacheKey(for userId: String) -> String {
        "article_notes_cache_\(userId)"
    }

    private func cachedNote(for userId: String, documentId: String) -> String? {
        let cacheKey = compositeCacheKey(userId: userId, documentId: documentId)
        if let memoryValue = Self.memoryCache[cacheKey] {
            return memoryValue
        }

        let storedDictionary = readStoredNotesMap(userId: userId)
        if let storedValue = storedDictionary[documentId] {
            Self.memoryCache[cacheKey] = storedValue
            return storedValue
        }

        return nil
    }

    private func storeNoteInCache(_ note: String, userId: String, documentId: String) {
        let cacheKey = compositeCacheKey(userId: userId, documentId: documentId)
        Self.memoryCache[cacheKey] = note

        var storedDictionary = readStoredNotesMap(userId: userId)
        storedDictionary[documentId] = note
        writeStoredNotesMap(storedDictionary, userId: userId)
    }

    private func removeNoteFromCache(userId: String, documentId: String) {
        let cacheKey = compositeCacheKey(userId: userId, documentId: documentId)
        Self.memoryCache.removeValue(forKey: cacheKey)

        var storedDictionary = readStoredNotesMap(userId: userId)
        storedDictionary.removeValue(forKey: documentId)
        writeStoredNotesMap(storedDictionary, userId: userId)
    }

    private func readStoredNotesMap(userId: String) -> [String: String] {
        let key = userDefaultsCacheKey(for: userId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return map
    }

    private func writeStoredNotesMap(_ map: [String: String], userId: String) {
        let key = userDefaultsCacheKey(for: userId)
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func bumpRecentFetchTimestamp(userId: String, documentId: String) {
        let cacheKey = compositeCacheKey(userId: userId, documentId: documentId)
        Self.recentFetchTimestamps[cacheKey] = Date()
    }

    private func showSuccessMessage(_ message: String) {
        successWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            successMessage = message
        }

        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self?.successMessage = nil
                }
            }
        }

        successWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func friendlyErrorMessage(for error: Error, action: String) -> String {
        let nsError = error as NSError

        if nsError.domain == FirestoreErrorDomain {
            switch nsError.code {
            case FirestoreErrorCode.permissionDenied.rawValue:
                return "You do not have permission to \(action)."
            case FirestoreErrorCode.unavailable.rawValue:
                return "Network unavailable. Please try again shortly."
            default:
                return "Failed to \(action)."
            }
        }

        return "Failed to \(action)."
    }
}
