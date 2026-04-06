import SwiftUI
import FirebaseAuth

// MARK: - Bookmark ViewModel
class BookmarkManager: ObservableObject {
    @Published var bookmarks: [Topic] = []
    @Published var bookmarkedArticles: [Article] = []
    
    init() {
        loadBookmarks()
        loadBookmarkedArticles()
    }
    
    // Generate a unique storage key for the current user
    private var userBookmarksKey: String? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        return "bookmarks_\(userId)"
    }
    
    private var userArticleBookmarksKey: String? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        return "article_bookmarks_\(userId)"
    }
    
    // Load topics
    func loadBookmarks() {
        guard let key = userBookmarksKey else {
            bookmarks = []
            return
        }
        
        if let data = UserDefaults.standard.data(forKey: key),
           let decodedTopics = try? JSONDecoder().decode([Topic].self, from: data) {
            bookmarks = decodedTopics
        } else {
            bookmarks = []
        }
    }
    
    // Load articles
    func loadBookmarkedArticles() {
        guard let key = userArticleBookmarksKey else {
            bookmarkedArticles = []
            return
        }
        
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Article].self, from: data) {
            bookmarkedArticles = decoded
        } else {
            bookmarkedArticles = []
        }
    }
    
    // Save topics
    private func saveBookmarks() {
        guard let key = userBookmarksKey else { return }
        
        if let encodedData = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(encodedData, forKey: key)
        }
    }
    
    // Save articles
    private func saveBookmarkedArticles() {
        guard let key = userArticleBookmarksKey else { return }
        
        if let encoded = try? JSONEncoder().encode(bookmarkedArticles) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // --- Topic Methods ---
    func isBookmarked(topic: Topic) -> Bool {
        return bookmarks.contains { $0.id == topic.id }
    }
    
    func addBookmark(topic: Topic) {
        if !isBookmarked(topic: topic) {
            bookmarks.append(topic)
            saveBookmarks()
        }
    }
    
    func removeBookmark(topic: Topic) {
        bookmarks.removeAll { $0.id == topic.id }
        saveBookmarks()
    }
    
    func toggleBookmark(topic: Topic) {
        if isBookmarked(topic: topic) {
            removeBookmark(topic: topic)
        } else {
            addBookmark(topic: topic)
        }
    }
    
    // --- Article Methods ---
    func isArticleBookmarked(article: Article) -> Bool {
        // Because the API generates a new UUID each time, we rely on the URL to see if it's the exact same news story
        return bookmarkedArticles.contains { $0.url == article.url && article.url != nil }
    }
    
    func addArticleBookmark(article: Article) {
        if !isArticleBookmarked(article: article) {
            bookmarkedArticles.append(article)
            saveBookmarkedArticles()
        }
    }
    
    func removeArticleBookmark(article: Article) {
        bookmarkedArticles.removeAll { $0.url == article.url }
        saveBookmarkedArticles()
    }
    
    func toggleArticleBookmark(article: Article) {
        if isArticleBookmarked(article: article) {
            removeArticleBookmark(article: article)
        } else {
            addArticleBookmark(article: article)
        }
    }
}
