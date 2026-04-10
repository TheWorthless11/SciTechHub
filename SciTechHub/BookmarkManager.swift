import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Bookmark ViewModel
class BookmarkManager: ObservableObject {
    @Published var bookmarks: [Topic] = []
    @Published var bookmarkedArticles: [Article] = []
    @Published var likedArticles: [Article] = []
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var bookmarksListener: ListenerRegistration?
    private var likesListener: ListenerRegistration?
    private var bookmarksListenerUserId: String?
    private var likesListenerUserId: String?

    init() {
        startBookmarksListener()
        startLikesListener()
    }

    deinit {
        bookmarksListener?.remove()
        likesListener?.remove()
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var userBookmarksCollection: CollectionReference? {
        guard let uid = currentUserId else { return nil }
        return db.collection("users").document(uid).collection("bookmarks")
    }

    private var userLikesCollection: CollectionReference? {
        guard let uid = currentUserId else { return nil }
        return db.collection("users").document(uid).collection("likedArticles")
    }

    private func friendlyErrorMessage(for error: Error, feature: String) -> String {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "Permission denied for \(feature). Update Firestore Rules to allow users to access only their own data."
        }
        return error.localizedDescription
    }

    // Kept for compatibility with existing call sites.
    func loadBookmarks() {
        startBookmarksListener()
    }

    // Kept for compatibility with existing call sites.
    func loadBookmarkedArticles() {
        startBookmarksListener()
    }

    // Kept for compatibility with existing call sites.
    func loadLikedArticles() {
        startLikesListener()
    }

    private func startBookmarksListener() {
        guard let uid = currentUserId, let collection = userBookmarksCollection else {
            clearBookmarks()
            return
        }

        if bookmarksListener != nil && bookmarksListenerUserId == uid {
            return
        }

        bookmarksListener?.remove()
        bookmarksListenerUserId = uid
        bookmarksListener = collection
            .whereField("ownerId", isEqualTo: uid)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = self.friendlyErrorMessage(for: error, feature: "bookmarks")
                    }
                    return
                }

                guard let documents = querySnapshot?.documents else {
                    DispatchQueue.main.async {
                        self.bookmarks = []
                        self.bookmarkedArticles = []
                    }
                    return
                }

                var loadedTopics: [Topic] = []
                var loadedArticles: [Article] = []

                for document in documents {
                    let data = document.data()
                    let type = data["type"] as? String ?? ""

                    if type == "topic" {
                        let topicId = data["topicId"] as? String ?? ""
                        let title = data["title"] as? String ?? ""
                        let description = data["description"] as? String ?? ""
                        let category = data["category"] as? String ?? ""

                        if !topicId.isEmpty {
                            loadedTopics.append(
                                Topic(
                                    id: topicId,
                                    title: title,
                                    description: description,
                                    category: category
                                )
                            )
                        }
                    }

                    if type == "article" {
                        if let article = article(from: data) {
                            loadedArticles.append(article)
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.bookmarks = loadedTopics
                    self.bookmarkedArticles = loadedArticles
                    self.errorMessage = nil
                }
            }
    }

    private func startLikesListener() {
        guard let uid = currentUserId, let collection = userLikesCollection else {
            clearLikes()
            return
        }

        if likesListener != nil && likesListenerUserId == uid {
            return
        }

        likesListener?.remove()
        likesListenerUserId = uid
        likesListener = collection
            .whereField("ownerId", isEqualTo: uid)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = self.friendlyErrorMessage(for: error, feature: "likes")
                    }
                    return
                }

                guard let documents = querySnapshot?.documents else {
                    DispatchQueue.main.async {
                        self.likedArticles = []
                    }
                    return
                }

                let loadedLikes = documents.compactMap { document in
                    self.article(from: document.data())
                }

                DispatchQueue.main.async {
                    self.likedArticles = loadedLikes
                    self.errorMessage = nil
                }
            }
    }

    private func clearBookmarks() {
        bookmarksListener?.remove()
        bookmarksListener = nil
        bookmarksListenerUserId = nil
        bookmarks = []
        bookmarkedArticles = []
    }

    private func clearLikes() {
        likesListener?.remove()
        likesListener = nil
        likesListenerUserId = nil
        likedArticles = []
    }

    private func article(from data: [String: Any]) -> Article? {
        let title = data["title"] as? String ?? ""
        let description = data["description"] as? String
        let urlToImage = data["image"] as? String ?? data["urlToImage"] as? String
        let url = data["url"] as? String

        guard !title.isEmpty else { return nil }
        return Article(
            title: title,
            description: description,
            urlToImage: urlToImage,
            url: url
        )
    }

    private func safeDocumentId(from rawValue: String) -> String {
        let encoded = Data(rawValue.utf8).base64EncodedString()
        return encoded
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func topicDocumentId(for topic: Topic) -> String {
        "topic_\(safeDocumentId(from: topic.id))"
    }

    private func articleDocumentId(for article: Article) -> String {
        if let url = article.url, !url.isEmpty {
            return "article_\(safeDocumentId(from: url))"
        }
        return "article_\(safeDocumentId(from: article.title.lowercased()))"
    }

    private func doesArticle(_ savedArticle: Article, match targetArticle: Article) -> Bool {
        if let savedURL = savedArticle.url, !savedURL.isEmpty,
           let targetURL = targetArticle.url, !targetURL.isEmpty {
            return savedURL == targetURL
        }
        return savedArticle.title == targetArticle.title
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

    // --- Topic Methods ---
    func isBookmarked(topic: Topic) -> Bool {
        bookmarks.contains { $0.id == topic.id }
    }

    func addBookmark(topic: Topic) {
        guard let uid = currentUserId, let collection = userBookmarksCollection else {
            errorMessage = "Login required to save bookmarks."
            return
        }

        let data: [String: Any] = [
            "type": "topic",
            "topicId": topic.id,
            "title": topic.title,
            "description": topic.description,
            "category": topic.category,
            "ownerId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]

        collection.document(topicDocumentId(for: topic)).setData(data, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = self?.friendlyErrorMessage(for: error, feature: "bookmarks")
                }
            }
        }
    }

    func removeBookmark(topic: Topic) {
        guard let collection = userBookmarksCollection else {
            errorMessage = "Login required to remove bookmarks."
            return
        }

        collection.document(topicDocumentId(for: topic)).delete { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = self?.friendlyErrorMessage(for: error, feature: "bookmarks")
                }
            }
        }
    }

    func toggleBookmark(topic: Topic) {
        guard currentUserId != nil else {
            errorMessage = "Login required to update bookmarks."
            return
        }

        if isBookmarked(topic: topic) {
            removeBookmark(topic: topic)
        } else {
            addBookmark(topic: topic)
        }
    }

    // --- Article Methods ---
    func isArticleBookmarked(article: Article) -> Bool {
        bookmarkedArticles.contains { doesArticle($0, match: article) }
    }

    func addArticleBookmark(article: Article) {
        guard let uid = currentUserId, let collection = userBookmarksCollection else {
            errorMessage = "Login required to save bookmarks."
            return
        }

        let data: [String: Any] = [
            "type": "article",
            "title": article.title,
            "description": article.description as Any,
            "urlToImage": article.urlToImage as Any,
            "url": article.url as Any,
            "ownerId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]

        collection.document(articleDocumentId(for: article)).setData(data, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = self?.friendlyErrorMessage(for: error, feature: "bookmarks")
                }
            }
        }
    }

    func removeArticleBookmark(article: Article) {
        guard let collection = userBookmarksCollection else {
            errorMessage = "Login required to remove bookmarks."
            return
        }

        collection.document(articleDocumentId(for: article)).delete { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = self?.friendlyErrorMessage(for: error, feature: "bookmarks")
                }
            }
        }
    }

    func toggleArticleBookmark(article: Article) {
        guard currentUserId != nil else {
            errorMessage = "Login required to update bookmarks."
            return
        }

        if isArticleBookmarked(article: article) {
            removeArticleBookmark(article: article)
        } else {
            addArticleBookmark(article: article)
        }
    }

    func isArticleLoved(article: Article) -> Bool {
        likedArticles.contains { doesArticle($0, match: article) }
    }

    func addArticleLove(article: Article) {
        guard let uid = currentUserId, let collection = userLikesCollection else {
            errorMessage = "Login required to react to articles."
            return
        }

        let data: [String: Any] = [
            "type": "article",
            "title": article.title,
            "description": article.description as Any,
            "image": article.urlToImage as Any,
            "urlToImage": article.urlToImage as Any,
            "url": article.url as Any,
            "source": sourceName(from: article.url),
            "timestamp": FieldValue.serverTimestamp(),
            "ownerId": uid,
            "createdAt": FieldValue.serverTimestamp()
        ]

        collection.document(articleDocumentId(for: article)).setData(data, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = self?.friendlyErrorMessage(for: error, feature: "likes")
                }
            }
        }
    }

    func removeArticleLove(article: Article) {
        guard let collection = userLikesCollection else {
            errorMessage = "Login required to remove reactions."
            return
        }

        collection.document(articleDocumentId(for: article)).delete { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = self?.friendlyErrorMessage(for: error, feature: "likes")
                }
            }
        }
    }

    func toggleArticleLove(article: Article) {
        guard currentUserId != nil else {
            errorMessage = "Login required to react to articles."
            return
        }

        if isArticleLoved(article: article) {
            removeArticleLove(article: article)
        } else {
            addArticleLove(article: article)
        }
    }
}
