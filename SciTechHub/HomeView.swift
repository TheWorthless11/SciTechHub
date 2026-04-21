//
//  HomeView.swift
//  SciTechHub
//
//  Created by Sayaka Alam on 5/4/26.
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// 1. Simple Category Model
struct Category: Identifiable {
    let name: String
    let icon: String

    var id: String {
        name
    }
}

final class RecommendationViewModel: ObservableObject {
    @Published var sourceArticles: [Article] = []
    @Published var trendingArticles: [Article] = []
    @Published var recommendedArticles: [Article] = []
    @Published var userInterests: [String] = []
    @Published var isLoading = false

    private let apiKey = "635dcde799d14101b7b967df87c7106e"
    private let db = Firestore.firestore()
    private var interestsListener: ListenerRegistration?
    private let stopWords: Set<String> = [
        "about", "after", "again", "also", "among", "been", "being", "between",
        "could", "from", "have", "into", "just", "more", "most", "other", "over",
        "some", "than", "that", "their", "there", "these", "they", "this", "through",
        "very", "what", "when", "where", "which", "with", "will", "would", "your"
    ]

    deinit {
        interestsListener?.remove()
    }

    func observeUserInterests() {
        interestsListener?.remove()

        guard let userId = Auth.auth().currentUser?.uid else {
            userInterests = []
            return
        }

        interestsListener = db.collection("users").document(userId).addSnapshotListener { [weak self] snapshot, _ in
            let interests = snapshot?.data()?["interests"] as? [String] ?? []
            DispatchQueue.main.async {
                self?.userInterests = interests
            }
        }
    }

    func fetchCandidateArticlesIfNeeded() {
        if !sourceArticles.isEmpty || isLoading {
            return
        }

        isLoading = true
        let categories = ["science", "technology", "health"]
        let group = DispatchGroup()
        var fetched: [Article] = []

        for category in categories {
            group.enter()
            fetchArticles(for: category) { articles in
                fetched.append(contentsOf: articles)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.sourceArticles = self.uniqueArticles(from: fetched)
            self.isLoading = false
        }
    }

    func refreshRecommendations(using manager: BookmarkManager) {
        let keywordWeights = preferenceKeywords(from: manager)

        guard !keywordWeights.isEmpty else {
            recommendedArticles = []
            return
        }

        let scoredArticles = sourceArticles.compactMap { article -> (Article, Int)? in
            let articleKeywords = Set(keywords(from: "\(article.title) \(article.description ?? "")"))
            let score = articleKeywords.reduce(0) { partial, word in
                partial + (keywordWeights[word] ?? 0)
            }

            return score > 0 ? (article, score) : nil
        }

        recommendedArticles = scoredArticles
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title < rhs.0.title
                }
                return lhs.1 > rhs.1
            }
            .map { $0.0 }
    }

    func refreshTrending(using manager: BookmarkManager) {
        let likedIds = Set(manager.likedArticles.map(\.id))
        let bookmarkedIds = Set(manager.bookmarkedArticles.map(\.id))
        let interactionKeywords = preferenceKeywords(from: manager)

        let ranked = sourceArticles.enumerated().map { index, article in
            (
                article,
                trendingScore(
                    for: article,
                    at: index,
                    likedIds: likedIds,
                    bookmarkedIds: bookmarkedIds,
                    interactionKeywords: interactionKeywords
                )
            )
        }

        trendingArticles = ranked
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title < rhs.0.title
                }
                return lhs.1 > rhs.1
            }
            .map { $0.0 }
    }

    private func fetchArticles(for category: String, completion: @escaping ([Article]) -> Void) {
        let urlString = "https://newsapi.org/v2/top-headlines?category=\(category)&apiKey=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if error != nil {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            guard let data = data,
                  let decoded = try? JSONDecoder().decode(NewsResponse.self, from: data) else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            DispatchQueue.main.async {
                completion(decoded.articles)
            }
        }.resume()
    }

    private func uniqueArticles(from articles: [Article]) -> [Article] {
        var seen = Set<String>()
        var unique: [Article] = []

        for article in articles where !seen.contains(article.id) {
            seen.insert(article.id)
            unique.append(article)
        }

        return unique
    }

    private func trendingScore(
        for article: Article,
        at index: Int,
        likedIds: Set<String>,
        bookmarkedIds: Set<String>,
        interactionKeywords: [String: Int]
    ) -> Int {
        let recencyBoost = max(0, sourceArticles.count - index)
        let likedBoost = likedIds.contains(article.id) ? 40 : 0
        let bookmarkedBoost = bookmarkedIds.contains(article.id) ? 25 : 0

        let articleKeywords = Set(keywords(from: "\(article.title) \(article.description ?? "")"))
        let momentumBoost = articleKeywords.reduce(0) { partial, word in
            partial + (interactionKeywords[word] ?? 0)
        }

        return recencyBoost + likedBoost + bookmarkedBoost + momentumBoost
    }

    private func preferenceKeywords(from manager: BookmarkManager) -> [String: Int] {
        var frequencies: [String: Int] = [:]

        for article in manager.likedArticles {
            for word in keywords(from: "\(article.title) \(article.description ?? "")") {
                frequencies[word, default: 0] += 2
            }
        }

        for article in manager.bookmarkedArticles {
            for word in keywords(from: "\(article.title) \(article.description ?? "")") {
                frequencies[word, default: 0] += 1
            }
        }

        for topic in manager.bookmarks {
            for word in keywords(from: "\(topic.title) \(topic.description) \(topic.category)") {
                frequencies[word, default: 0] += 1
            }
        }

        for interest in userInterests {
            for word in keywords(from: interest) {
                frequencies[word, default: 0] += 4
            }

            for mappedWord in mappedInterestKeywords(for: interest) {
                frequencies[mappedWord, default: 0] += 3
            }
        }

        return frequencies
    }

    private func mappedInterestKeywords(for interest: String) -> [String] {
        switch interest.lowercased() {
        case "ai", "artificial intelligence":
            return ["ai", "artificial", "intelligence", "machine", "learning", "robot", "neural"]
        case "space":
            return ["space", "nasa", "orbit", "planet", "mars", "moon", "rocket", "satellite"]
        case "technology":
            return ["technology", "tech", "software", "hardware", "device", "startup", "innovation"]
        case "health":
            return ["health", "medical", "medicine", "doctor", "hospital", "wellness", "disease"]
        case "science":
            return ["science", "research", "study", "discovery", "laboratory", "physics", "biology"]
        default:
            return []
        }
    }

    private func keywords(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count > 2 && !stopWords.contains(token)
            }
    }
}

// 2. Main Home Screen
struct HomeView: View {
    // Access the shared authentication ViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager // Add bookmarkManager access
    @StateObject private var recommendationViewModel = RecommendationViewModel()
    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false
    @State private var loginPromptMessage = "Personalized topics and profile tools are available for logged-in users."
    @State private var selectedTopicId: String?
    @State private var activeTopicCategoryName: String?
    
    // Sample categories
    let categories = [
        Category(name: "Science", icon: "atom"),
        Category(name: "Artificial Intelligence", icon: "brain.head.profile"),
        Category(name: "Space", icon: "sparkles"),
        Category(name: "Health", icon: "cross.case.fill")
    ]
    
    // Grid layout configuration
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            content
            .navigationTitle("Home")
            // Profile Icon
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    profileToolbarButton
                }
            }
            // Reload bookmarks based on current user
            .onAppear {
                bookmarkManager.loadBookmarks()
                bookmarkManager.loadBookmarkedArticles()
                bookmarkManager.loadLikedArticles()
                recommendationViewModel.fetchCandidateArticlesIfNeeded()
                recommendationViewModel.observeUserInterests()
                refreshPersonalizedSections()
            }
            .onChange(of: authViewModel.isLoggedIn) { _ in
                bookmarkManager.loadBookmarks()
                bookmarkManager.loadBookmarkedArticles()
                bookmarkManager.loadLikedArticles()
                recommendationViewModel.observeUserInterests()
                refreshPersonalizedSections()
            }
            .onChange(of: recommendationViewModel.sourceArticles.map(\.id)) { _ in
                refreshPersonalizedSections()
            }
            .onChange(of: recommendationViewModel.userInterests) { _ in
                refreshPersonalizedSections()
            }
            .alert("Login to access this feature", isPresented: $showLoginPrompt) {
                Button("Not Now", role: .cancel) { }
                Button("Login") {
                    showLoginSheet = true
                }
            } message: {
                Text(loginPromptMessage)
            }
            .sheet(isPresented: $showLoginSheet) {
                LoginView(showGuestDismiss: true)
                    .environmentObject(authViewModel)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                guestBanner
                
                // MARK: - Topics Grid Section
                Text("Explore Topics")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.titleText)
                    .padding(.horizontal)
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        categoryActionView(for: category, index: index)
                    }
                }
                .padding(.horizontal)

                trendingSection

                recommendationsSection
            }
            .padding(.vertical)
            .tabBarOverlayBottomPadding()
        }
        .background(AppTheme.background.ignoresSafeArea())
    }
    
    @ViewBuilder
    private var guestBanner: some View {
        if !authViewModel.isLoggedIn {
            Text("Login to access this feature")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.accentPrimary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.accentPrimary.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var profileToolbarButton: some View {
        if authViewModel.isLoggedIn {
            NavigationLink(destination: ProfileView().environmentObject(authViewModel)) {
                Image(systemName: "person.circle")
                    .font(.title2)
            }
        } else {
            Button(action: {
                presentLoginPrompt(message: "Personalized topics and profile tools are available for logged-in users.")
            }) {
                Image(systemName: "lock.person")
                    .font(.title2)
            }
        }
    }
    
    @ViewBuilder
    private func categoryActionView(for category: Category, index: Int) -> some View {
        let isSelected = selectedTopicId == category.id
        let appearDelay = Double(index) * 0.055

        Button {
            handleTopicTap(category)

            if authViewModel.isLoggedIn {
                activeTopicCategoryName = category.name
            } else {
                presentLoginPrompt(message: "Personalized topics and profile tools are available for logged-in users.")
            }
        } label: {
            TopicCardView(
                title: category.name,
                icon: category.icon,
                isSelected: isSelected,
                isLocked: !authViewModel.isLoggedIn,
                appearDelay: appearDelay
            )
        }
        .buttonStyle(TopicCardButtonStyle())
        .background {
            NavigationLink(
                destination: TopicListView(categoryName: category.name),
                tag: category.name,
                selection: $activeTopicCategoryName
            ) {
                EmptyView()
            }
            .hidden()
        }
    }

    private func handleTopicTap(_ category: Category) {
        HapticFeedback.tap(.light)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            selectedTopicId = category.id
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeInOut(duration: 0.25)) {
                if selectedTopicId == category.id {
                    selectedTopicId = nil
                }
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎯 Recommended for You")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.titleText)

                Spacer()

                NavigationLink(destination: RecommendedView(recommendationViewModel: recommendationViewModel)) {
                    Text("See All")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal)

            if recommendationViewModel.isLoading && visibleRecommendedArticles.isEmpty {
                ProgressView("Loading recommendations...")
                    .padding(.horizontal)
            } else if authViewModel.isLoggedIn,
                      bookmarkManager.likedArticles.isEmpty,
                      bookmarkManager.bookmarkedArticles.isEmpty,
                      bookmarkManager.bookmarks.isEmpty {
                Text("Love or bookmark articles to personalize this section.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else if visibleRecommendedArticles.isEmpty {
                Text("No recommendations available yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(visibleRecommendedArticles, id: \.id) { article in
                            recommendationCard(for: article)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🔥 Trending Now")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.titleText)

                Spacer()

                NavigationLink(destination: TrendingNowView(recommendationViewModel: recommendationViewModel)) {
                    Text("See All")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal)

            if recommendationViewModel.isLoading && visibleTrendingArticles.isEmpty {
                ProgressView("Loading trending stories...")
                    .padding(.horizontal)
            } else if visibleTrendingArticles.isEmpty {
                Text("No trending articles yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(visibleTrendingArticles, id: \.id) { article in
                            NavigationLink(destination: NewsArticleDetailView(article: article)) {
                                trendingCard(for: article)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var visibleRecommendedArticles: [Article] {
        if authViewModel.isLoggedIn {
            return Array(recommendationViewModel.recommendedArticles.prefix(10))
        }
        return Array(recommendationViewModel.sourceArticles.prefix(10))
    }

    private var visibleTrendingArticles: [Article] {
        Array(recommendationViewModel.trendingArticles.prefix(8))
    }

    private func trendingCard(for article: Article) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageString = article.urlToImage,
               let imageUrl = URL(string: imageString) {
                AsyncImage(url: imageUrl) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 230, height: 130)
                            .clipped()
                    } else if phase.error != nil {
                        Color.gray.opacity(0.2)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                            .frame(width: 230, height: 130)
                    } else {
                        ProgressView()
                            .frame(width: 230, height: 130)
                    }
                }
                .cornerRadius(12)
            }

            Text(article.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(AppTheme.titleText)

            Text(sourceName(for: article))
                .font(.caption)
                .foregroundColor(AppTheme.subtitleText)
        }
        .padding(12)
        .frame(width: 245, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }

    private func sourceName(for article: Article) -> String {
        guard
            let urlString = article.url,
            let host = URL(string: urlString)?.host
        else {
            return "SciTechHub"
        }

        let cleanedHost = host.replacingOccurrences(of: "www.", with: "")
        return cleanedHost.capitalized
    }

    private func recommendationCard(for article: Article) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageString = article.urlToImage,
               let imageUrl = URL(string: imageString) {
                AsyncImage(url: imageUrl) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 250, height: 130)
                            .clipped()
                    } else if phase.error != nil {
                        Color.gray.opacity(0.25)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                            .frame(width: 250, height: 130)
                    } else {
                        ProgressView()
                            .frame(width: 250, height: 130)
                    }
                }
                .cornerRadius(12)
            }

            Text(article.title)
                .font(.headline)
                .lineLimit(2)
                .foregroundStyle(AppTheme.titleText)

            if let description = article.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.subtitleText)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Button(action: {
                    handleLoveTap(for: article)
                }) {
                    Image(systemName: loveIconName(for: article))
                        .foregroundColor(loveIconColor(for: article))
                }

                Button(action: {
                    handleBookmarkTap(for: article)
                }) {
                    Image(systemName: bookmarkIconName(for: article))
                        .foregroundColor(bookmarkIconColor(for: article))
                }

                Spacer()

                if let urlString = article.url,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Text("Read")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
            .font(.title3)
        }
        .padding()
        .frame(width: 260, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }

    private func loveIconName(for article: Article) -> String {
        if authViewModel.isLoggedIn {
            return bookmarkManager.isArticleLoved(article: article) ? "heart.fill" : "heart"
        }
        return "heart"
    }

    private func loveIconColor(for article: Article) -> Color {
        if authViewModel.isLoggedIn {
            return bookmarkManager.isArticleLoved(article: article) ? .red : .gray
        }
        return .gray
    }

    private func bookmarkIconName(for article: Article) -> String {
        if authViewModel.isLoggedIn {
            return bookmarkManager.isArticleBookmarked(article: article) ? "bookmark.fill" : "bookmark"
        }
        return "bookmark"
    }

    private func bookmarkIconColor(for article: Article) -> Color {
        if authViewModel.isLoggedIn {
            return bookmarkManager.isArticleBookmarked(article: article) ? AppTheme.accentPrimary : .gray
        }
        return .gray
    }

    private func handleLoveTap(for article: Article) {
        guard authViewModel.isLoggedIn else {
            presentLoginPrompt(message: "Login to react or save articles.")
            return
        }

        HapticFeedback.tap(.light)
        bookmarkManager.toggleArticleLove(article: article)
    }

    private func handleBookmarkTap(for article: Article) {
        guard authViewModel.isLoggedIn else {
            presentLoginPrompt(message: "Login to react or save articles.")
            return
        }

        HapticFeedback.tap(.light)
        bookmarkManager.toggleArticleBookmark(article: article)
    }

    private func presentLoginPrompt(message: String) {
        loginPromptMessage = message
        showLoginPrompt = true
    }

    private func refreshRecommendations() {
        recommendationViewModel.refreshRecommendations(using: bookmarkManager)
    }

    private func refreshTrending() {
        recommendationViewModel.refreshTrending(using: bookmarkManager)
    }

    private func refreshPersonalizedSections() {
        refreshTrending()
        refreshRecommendations()
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(BookmarkManager())
            .environmentObject(AuthViewModel())
            .environmentObject(UserActivityViewModel())
    }
}

struct TrendingNowView: View {
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
        .navigationTitle("Trending Now")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            bookmarkManager.loadBookmarks()
            bookmarkManager.loadBookmarkedArticles()
            bookmarkManager.loadLikedArticles()
            recommendationViewModel.fetchCandidateArticlesIfNeeded()
            refreshTrending()
        }
        .onChange(of: authViewModel.isLoggedIn) { _ in
            bookmarkManager.loadBookmarks()
            bookmarkManager.loadBookmarkedArticles()
            bookmarkManager.loadLikedArticles()
            refreshTrending()
        }
        .onChange(of: recommendationViewModel.sourceArticles.map(\.id)) { _ in
            refreshTrending()
        }
        .onChange(of: recommendationViewModel.userInterests) { _ in
            refreshTrending()
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
        Array(recommendationViewModel.trendingArticles.prefix(20))
    }

    @ViewBuilder
    private var content: some View {
        if recommendationViewModel.isLoading && visibleArticles.isEmpty {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(0..<4, id: \.self) { _ in
                        ArticleCardSkeletonView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .tabBarOverlayBottomPadding()
            }
        } else if visibleArticles.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.accentPrimary)

                Text("No trending stories yet")
                    .font(.headline)
                    .foregroundColor(AppTheme.titleText)

                Text("Try again shortly while we gather engagement data.")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.subtitleText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(cornerRadius: 22)
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(visibleArticles, id: \.id) { article in
                        trendingFeedCard(for: article)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .tabBarOverlayBottomPadding()
            }
            .animation(.easeInOut(duration: 0.24), value: visibleArticles.map(\.id))
        }
    }

    private func trendingFeedCard(for article: Article) -> some View {
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

    private func refreshTrending() {
        recommendationViewModel.refreshTrending(using: bookmarkManager)
    }
}
