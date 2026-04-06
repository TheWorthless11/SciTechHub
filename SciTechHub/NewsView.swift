import SwiftUI

struct NewsView: View {
    @StateObject private var viewModel = NewsViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                // Show a simple loading indicator
                ProgressView("Loading...")
            } else {
                List {
                    // Science News Section
                    Section(header: Text("Science News")) {
                        ForEach(viewModel.scienceArticles) { article in
                            if let urlString = article.url, let url = URL(string: urlString) {
                                Link(destination: url) {
                                    ArticleRow(article: article)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                ArticleRow(article: article)
                            }
                        }
                    }
                    
                    // Technology News Section
                    Section(header: Text("Technology News")) {
                        ForEach(viewModel.techArticles) { article in
                            if let urlString = article.url, let url = URL(string: urlString) {
                                Link(destination: url) {
                                    ArticleRow(article: article)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                ArticleRow(article: article)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Top News")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Fetch news when the screen appears
            // We check if it's empty to prevent re-fetching every time you switch tabs or screens
            if viewModel.scienceArticles.isEmpty {
                viewModel.fetchScienceNews()
            }
            if viewModel.techArticles.isEmpty {
                viewModel.fetchTechNews()
            }
        }
    }
}

// Extracted into a small subview to keep code clean and simple
struct ArticleRow: View {
    let article: Article
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Article Image
            if let imageString = article.urlToImage, let imageUrl = URL(string: imageString) {
                AsyncImage(url: imageUrl) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .cornerRadius(8)
                            .clipped()
                    } else if phase.error != nil {
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .frame(width: 80, height: 80)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    } else {
                        ProgressView()
                            .frame(width: 80, height: 80)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Article Title
                Text(article.title)
                    .font(.headline)
                
                // Article Description (Since it's optional, we safely unwrap it)
                if let description = article.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(3) // Keeps the cards from getting too long
                }
            }
            
            Spacer()
            
            // Bookmark Action Button
            Button(action: {
                bookmarkManager.toggleArticleBookmark(article: article)
            }) {
                Image(systemName: bookmarkManager.isArticleBookmarked(article: article) ? "bookmark.fill" : "bookmark")
                    .foregroundColor(bookmarkManager.isArticleBookmarked(article: article) ? .blue : .gray)
                    .padding(8) // Increases tap area
            }
            // We use BorderlessButtonStyle so the button intercepts taps instead of the whole row Link navigating
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

struct NewsView_Previews: PreviewProvider {
    static var previews: some View {
        NewsView()
    }
}
