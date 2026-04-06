import SwiftUI

struct BookmarkView: View {
    // Access the shared bookmarks from the environment
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        Group {
            if bookmarkManager.bookmarks.isEmpty && bookmarkManager.bookmarkedArticles.isEmpty {
                // Empty state view
                VStack(spacing: 20) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 80))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No bookmarks yet!")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Tap the heart/bookmark icon on any topic or trending news to save it here.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List {
                    if !bookmarkManager.bookmarks.isEmpty {
                        Section(header: Text("Topics")) {
                            ForEach(bookmarkManager.bookmarks) { topic in
                                NavigationLink(destination: TopicDetailView(topic: topic)) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(topic.title)
                                            .font(.headline)
                                        Text(topic.category)
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            // Simple swipe removal directly from the list
                            .onDelete { indexSet in
                                for index in indexSet {
                                    let topic = bookmarkManager.bookmarks[index]
                                    bookmarkManager.removeBookmark(topic: topic)
                                }
                            }
                        }
                    }
                    
                    if !bookmarkManager.bookmarkedArticles.isEmpty {
                        Section(header: Text("Trending News")) {
                            ForEach(bookmarkManager.bookmarkedArticles) { article in
                                if let urlString = article.url, let url = URL(string: urlString) {
                                    HStack(alignment: .top, spacing: 12) {
                                        // Article Image
                                        if let imageString = article.urlToImage, let imageUrl = URL(string: imageString) {
                                            AsyncImage(url: imageUrl) { phase in
                                                if let image = phase.image {
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 60, height: 60)
                                                        .cornerRadius(8)
                                                        .clipped()
                                                } else if phase.error != nil {
                                                    Image(systemName: "photo")
                                                        .foregroundColor(.gray)
                                                        .frame(width: 60, height: 60)
                                                        .background(Color.gray.opacity(0.2))
                                                        .cornerRadius(8)
                                                } else {
                                                    ProgressView()
                                                        .frame(width: 60, height: 60)
                                                }
                                            }
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Link(destination: url) {
                                                Text(article.title)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    let article = bookmarkManager.bookmarkedArticles[index]
                                    bookmarkManager.removeArticleBookmark(article: article)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
    }
}

struct BookmarkView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BookmarkView()
                .environmentObject(BookmarkManager())
        }
    }
}
