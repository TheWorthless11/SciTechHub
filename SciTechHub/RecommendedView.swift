import SwiftUI

struct RecommendedView: View {
    @ObservedObject var recommendationViewModel: RecommendationViewModel

    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager

    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false

    var body: some View {
        Group {
            if recommendationViewModel.isLoading && visibleArticles.isEmpty {
                ProgressView("Loading recommendations...")
            } else if authViewModel.isLoggedIn,
                      bookmarkManager.likedArticles.isEmpty,
                      bookmarkManager.bookmarkedArticles.isEmpty,
                      bookmarkManager.bookmarks.isEmpty {
                emptyPreferenceState
            } else if visibleArticles.isEmpty {
                emptyRecommendationState
            } else {
                List {
                    ForEach(visibleArticles, id: \.id) { article in
                        NavigationLink(destination: NewsArticleDetailView(article: article)) {
                            ArticleRow(
                                article: article,
                                isLoggedIn: authViewModel.isLoggedIn,
                                onRestrictedAction: {
                                    showLoginPrompt = true
                                }
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Recommended")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            bookmarkManager.loadBookmarks()
            bookmarkManager.loadBookmarkedArticles()
            bookmarkManager.loadLikedArticles()
            recommendationViewModel.fetchCandidateArticlesIfNeeded()
            recommendationViewModel.observeUserInterests()
            refreshRecommendations()
        }
        .onChange(of: authViewModel.isLoggedIn) { _ in
            bookmarkManager.loadBookmarks()
            bookmarkManager.loadBookmarkedArticles()
            bookmarkManager.loadLikedArticles()
            refreshRecommendations()
        }
        .onChange(of: recommendationViewModel.sourceArticles.map(\.id)) { _ in
            refreshRecommendations()
        }
        .onChange(of: recommendationViewModel.userInterests) { _ in
            refreshRecommendations()
        }
        .alert("Login to access this feature", isPresented: $showLoginPrompt) {
            Button("Not Now", role: .cancel) { }
            Button("Login") {
                showLoginSheet = true
            }
        } message: {
            Text("Login to react or save articles.")
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
    }

    private var visibleArticles: [Article] {
        if authViewModel.isLoggedIn {
            return recommendationViewModel.recommendedArticles
        }
        return recommendationViewModel.sourceArticles
    }

    private var emptyPreferenceState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 42))
                .foregroundColor(.blue)

            Text("No recommendations yet")
                .font(.headline)

            Text("Love or bookmark articles to build your recommendations.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyRecommendationState: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 42))
                .foregroundColor(.gray)

            Text("No recommendations available")
                .font(.headline)

            Text("Try again in a moment while we load more articles.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func refreshRecommendations() {
        recommendationViewModel.refreshRecommendations(using: bookmarkManager)
    }
}

struct RecommendedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RecommendedView(recommendationViewModel: RecommendationViewModel())
                .environmentObject(AuthViewModel())
                .environmentObject(BookmarkManager())
                .environmentObject(UserActivityViewModel())
        }
    }
}
