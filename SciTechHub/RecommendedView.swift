import SwiftUI

struct RecommendedView: View {
    @ObservedObject var recommendationViewModel: RecommendationViewModel

    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager

    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            content
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

    @ViewBuilder
    private var content: some View {
        if recommendationViewModel.isLoading && visibleArticles.isEmpty {
            loadingState
        } else if authViewModel.isLoggedIn,
                  bookmarkManager.likedArticles.isEmpty,
                  bookmarkManager.bookmarkedArticles.isEmpty,
                  bookmarkManager.bookmarks.isEmpty {
            emptyPreferenceState
        } else if visibleArticles.isEmpty {
            emptyRecommendationState
        } else {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(visibleArticles, id: \.id) { article in
                        recommendationCard(for: article)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .animation(.easeInOut(duration: 0.24), value: visibleArticles.map(\.id))
        }
    }

    private var visibleArticles: [Article] {
        if authViewModel.isLoggedIn {
            return recommendationViewModel.recommendedArticles
        }
        return recommendationViewModel.sourceArticles
    }

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(0..<4, id: \.self) { _ in
                    ArticleCardSkeletonView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func recommendationCard(for article: Article) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(destination: NewsArticleDetailView(article: article)) {
                ArticleCardView(article: article)
            }
            .buttonStyle(.plain)

            quickActionBar(for: article)
                .padding(.top, 16)
                .padding(.trailing, 16)
        }
    }

    private func quickActionBar(for article: Article) -> some View {
        VStack(spacing: 8) {
            Button {
                handleLoveTap(for: article)
            } label: {
                Image(systemName: bookmarkManager.isArticleLoved(article: article) ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(bookmarkManager.isArticleLoved(article: article) ? .red : .white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.38))
                    .clipShape(Circle())
            }
            .buttonStyle(SpringyButtonStyle())

            Button {
                handleBookmarkTap(for: article)
            } label: {
                Image(systemName: bookmarkManager.isArticleBookmarked(article: article) ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(bookmarkManager.isArticleBookmarked(article: article) ? AppTheme.accentSecondary : .white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.38))
                    .clipShape(Circle())
            }
            .buttonStyle(SpringyButtonStyle())
        }
    }

    private var emptyPreferenceState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 42))
                .foregroundColor(AppTheme.accentPrimary)

            Text("No recommendations yet")
                .font(.headline)
                .foregroundColor(AppTheme.titleText)

            Text("Love or bookmark articles to build your recommendations.")
                .font(.subheadline)
                .foregroundColor(AppTheme.subtitleText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 22)
        .padding(20)
    }

    private var emptyRecommendationState: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 42))
                .foregroundColor(AppTheme.subtitleText)

            Text("No recommendations available")
                .font(.headline)
                .foregroundColor(AppTheme.titleText)

            Text("Try again in a moment while we load more articles.")
                .font(.subheadline)
                .foregroundColor(AppTheme.subtitleText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 22)
        .padding(20)
    }

    private func handleLoveTap(for article: Article) {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

        HapticFeedback.tap(.light)
        bookmarkManager.toggleArticleLove(article: article)
    }

    private func handleBookmarkTap(for article: Article) {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

        HapticFeedback.tap(.light)
        bookmarkManager.toggleArticleBookmark(article: article)
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
