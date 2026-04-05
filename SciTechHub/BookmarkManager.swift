import SwiftUI
import FirebaseAuth

// MARK: - Bookmark ViewModel
class BookmarkManager: ObservableObject {
    @Published var bookmarks: [Topic] = []
    
    init() {
        loadBookmarks()
    }
    
    // Generate a unique storage key for the current user
    private var userBookmarksKey: String? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        return "bookmarks_\(userId)"
    }
    
    // Load bookmarks from UserDefaults for the specific user
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
    
    // Save current bookmarks to UserDefaults for the specific user
    private func saveBookmarks() {
        guard let key = userBookmarksKey else { return }
        
        if let encodedData = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(encodedData, forKey: key)
        }
    }
    
    // Check if a topic is already bookmarked
    func isBookmarked(topic: Topic) -> Bool {
        return bookmarks.contains { $0.id == topic.id }
    }
    
    // Add a topic to bookmarks
    func addBookmark(topic: Topic) {
        if !isBookmarked(topic: topic) {
            bookmarks.append(topic)
            saveBookmarks() // Save updated list
        }
    }
    
    // Remove a topic from bookmarks
    func removeBookmark(topic: Topic) {
        bookmarks.removeAll { $0.id == topic.id }
        saveBookmarks() // Save updated list
    }
    
    // Toggle bookmark status
    func toggleBookmark(topic: Topic) {
        if isBookmarked(topic: topic) {
            removeBookmark(topic: topic)
        } else {
            addBookmark(topic: topic)
        }
    }
}
