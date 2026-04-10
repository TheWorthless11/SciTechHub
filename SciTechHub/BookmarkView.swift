import SwiftUI

struct BookmarkView: View {
    // Access the shared bookmarks from the environment
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showLoginSheet = false
    
    var body: some View {
        Group {
            if !authViewModel.isLoggedIn {
                LoginRequiredView(
                    message: "Saved topics and bookmarked articles are available for logged-in users."
                ) {
                    showLoginSheet = true
                }
            } else if bookmarkManager.bookmarks.isEmpty && bookmarkManager.bookmarkedArticles.isEmpty {
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
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
    }
}

struct LoginRequiredView: View {
    let title: String
    let message: String
    let onLoginTap: () -> Void

    init(
        title: String = "Login to access this feature",
        message: String = "Please sign in to unlock this section.",
        onLoginTap: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.onLoginTap = onLoginTap
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 42))
                .foregroundColor(.orange)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onLoginTap) {
                Text("Login")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct BookmarkView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BookmarkView()
                .environmentObject(BookmarkManager())
                .environmentObject(AuthViewModel())
        }
    }
}
