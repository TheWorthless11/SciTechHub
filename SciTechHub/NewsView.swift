import SwiftUI

struct NewsView: View {
    @StateObject private var viewModel = NewsViewModel()
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    // Show a simple loading indicator
                    ProgressView("Loading...")
                } else {
                    List {
                        // Science News Section
                        Section(header: Text("Science News")) {
                            ForEach(viewModel.scienceArticles) { article in
                                ArticleRow(article: article)
                            }
                        }
                        
                        // Technology News Section
                        Section(header: Text("Technology News")) {
                            ForEach(viewModel.techArticles) { article in
                                ArticleRow(article: article)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Top News")
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
}

// Extracted into a small subview to keep code clean and simple
struct ArticleRow: View {
    let article: Article
    
    var body: some View {
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
        .padding(.vertical, 4)
    }
}

struct NewsView_Previews: PreviewProvider {
    static var previews: some View {
        NewsView()
    }
}
