import SwiftUI
import UIKit

struct BookmarkView: View {
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var showLoginSheet = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var selectedFilter: BookmarkFilter = .all
    @State private var searchText = ""
    @State private var didAppearHeader = false

    private enum BookmarkFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        case favorites = "Favorites"

        var id: String {
            rawValue
        }
    }

    var body: some View {
        ZStack {
            backgroundLayer

            Group {
                if !authViewModel.isLoggedIn {
                    LoginRequiredView(
                        message: "Saved topics and bookmarked articles are available for logged-in users."
                    ) {
                        showLoginSheet = true
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            headerSection

                            if bookmarkManager.bookmarks.isEmpty && bookmarkManager.bookmarkedArticles.isEmpty {
                                BookmarkEmptyStateView(accentColor: accentColor)
                                    .padding(.top, 24)
                            } else {
                                if !bookmarkManager.bookmarkedArticles.isEmpty {
                                    filtersSection
                                }

                                articleSection

                                if !bookmarkManager.bookmarks.isEmpty {
                                    topicsSection
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .tabBarOverlayBottomPadding(extra: 24)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(activityItems: shareItems)
        }
        .onAppear {
            if !didAppearHeader {
                withAnimation(.easeOut(duration: 0.36)) {
                    didAppearHeader = true
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bookmarks")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.titleText)

            Text("Your Collection")
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)

            if !bookmarkManager.bookmarkedArticles.isEmpty {
                Text("\(bookmarkManager.bookmarkedArticles.count) saved \(bookmarkManager.bookmarkedArticles.count == 1 ? "article" : "articles")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.subtitleText.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }
        }
        .opacity(didAppearHeader ? 1 : 0)
        .offset(y: didAppearHeader ? 0 : 12)
    }

    private var filtersSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.subtitleText)

                TextField("Search saved articles", text: $searchText)
                    .foregroundStyle(AppTheme.titleText)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.subtitleText.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )

            Picker("Filter", selection: $selectedFilter) {
                ForEach(BookmarkFilter.allCases) { option in
                    Text(option.rawValue)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var articleSection: some View {
        let items = visibleArticles

        return VStack(alignment: .leading, spacing: 12) {
            if bookmarkManager.bookmarkedArticles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No saved articles yet")
                        .font(.headline)
                        .foregroundStyle(AppTheme.titleText)

                    Text("Bookmark an article from Trending, News, or Recommended to build your library.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtitleText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 20)
            } else if items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No matches found")
                        .font(.headline)
                        .foregroundStyle(AppTheme.titleText)

                    Text("Try a different keyword or switch the filter.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtitleText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 20)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, article in
                    SwipeableBookmarkCard(
                        accentColor: accentColor,
                        onLeadingAction: {
                            share(article: article)
                        },
                        onTrailingAction: {
                            remove(article: article)
                        }
                    ) {
                        NavigationLink(destination: NewsArticleDetailView(article: article)) {
                            BookmarkCardView(
                                article: article,
                                cardColor: cardColor,
                                accentColor: accentColor,
                                isFavorite: bookmarkManager.isArticleLoved(article: article),
                                appearDelay: Double(index) * 0.05
                            )
                        }
                        .buttonStyle(BookmarkCardButtonStyle(accentColor: accentColor))
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                HapticFeedback.tap(.light)
                            }
                        )
                    }

                    if index < items.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                            .padding(.top, -2)
                            .padding(.bottom, 2)
                    }
                }
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: items.map(\.id))
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Topics")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.titleText)
                .padding(.top, 4)

            ForEach(Array(bookmarkManager.bookmarks.enumerated()), id: \.element.id) { index, topic in
                SwipeableBookmarkCard(
                    accentColor: accentColor,
                    onLeadingAction: {
                        share(topic: topic)
                    },
                    onTrailingAction: {
                        remove(topic: topic)
                    }
                ) {
                    NavigationLink(destination: TopicDetailView(topic: topic)) {
                        BookmarkTopicCardView(
                            topic: topic,
                            cardColor: cardColor,
                            accentColor: accentColor,
                            appearDelay: Double(index) * 0.05
                        )
                    }
                    .buttonStyle(BookmarkCardButtonStyle(accentColor: accentColor))
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            HapticFeedback.tap(.light)
                        }
                    )
                }

                if index < bookmarkManager.bookmarks.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                        .padding(.top, -2)
                        .padding(.bottom, 2)
                }
            }
        }
    }

    private var visibleArticles: [Article] {
        var filtered = bookmarkManager.bookmarkedArticles

        switch selectedFilter {
        case .all:
            break
        case .recent:
            filtered = Array(filtered.reversed())
        case .favorites:
            filtered = filtered.filter { bookmarkManager.isArticleLoved(article: $0) }
        }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return filtered
        }

        return filtered.filter { article in
            let title = article.title.lowercased()
            let description = article.description?.lowercased() ?? ""
            let source = sourceName(for: article).lowercased()
            return title.contains(query) || description.contains(query) || source.contains(query)
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            backgroundColor

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.clear,
                    Color.black.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 46)
                .offset(x: 120, y: -260)

            Circle()
                .fill(accentColor.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: -130, y: 260)
        }
        .ignoresSafeArea()
    }

    private var backgroundColor: Color {
        UIColor(named: "Background") == nil ? AppTheme.background : Color("Background")
    }

    private var cardColor: Color {
        UIColor(named: "Card") == nil ? AppTheme.cardBackground : Color("Card")
    }

    private var accentColor: Color {
        UIColor(named: "Accent") == nil ? AppTheme.accentPrimary : Color("Accent")
    }

    private func sourceName(for article: Article) -> String {
        guard
            let urlString = article.url,
            let host = URL(string: urlString)?.host,
            !host.isEmpty
        else {
            return "Latest Update"
        }

        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func share(article: Article) {
        HapticFeedback.tap(.light)

        var payload: [Any] = [article.title]
        if let url = article.url, !url.isEmpty {
            payload.append(url)
        }

        shareItems = payload
        showShareSheet = true
    }

    private func share(topic: Topic) {
        HapticFeedback.tap(.light)
        shareItems = ["\(topic.title)\n\n\(topic.description)\n\nShared from SciTechHub"]
        showShareSheet = true
    }

    private func remove(article: Article) {
        HapticFeedback.tap(.medium)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            bookmarkManager.removeArticleBookmark(article: article)
        }
    }

    private func remove(topic: Topic) {
        HapticFeedback.tap(.medium)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            bookmarkManager.removeBookmark(topic: topic)
        }
    }
}

private struct BookmarkCardView: View {
    let article: Article
    let cardColor: Color
    let accentColor: Color
    let isFavorite: Bool
    let appearDelay: Double

    @State private var didAppear = false

    private let cornerRadius: CGFloat = 20

    var body: some View {
        HStack(spacing: 14) {
            BookmarkThumbnailView(urlString: article.urlToImage, accentColor: accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.titleText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(sourceName)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtitleText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(isFavorite ? "Favorite" : "Saved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFavorite ? accentColor : AppTheme.subtitleText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isFavorite ? accentColor.opacity(0.16) : Color.white.opacity(0.08)))
                        .clipShape(Capsule())

                    Text("\(estimatedReadMinutes) min read")
                        .font(.caption)
                        .foregroundStyle(AppTheme.subtitleText.opacity(0.9))
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.subtitleText.opacity(0.8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        .shadow(color: accentColor.opacity(isFavorite ? 0.18 : 0), radius: 10, x: 0, y: 0)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 12)
        .animation(.easeOut(duration: 0.34).delay(appearDelay), value: didAppear)
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardColor.opacity(0.58))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.2), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accentColor.opacity(isFavorite ? 0.44 : 0.12), lineWidth: isFavorite ? 1.4 : 1)
        )
    }

    private var sourceName: String {
        guard
            let urlString = article.url,
            let host = URL(string: urlString)?.host,
            !host.isEmpty
        else {
            return "Latest Update"
        }

        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var estimatedReadMinutes: Int {
        let wordCount = [article.title, article.description ?? ""]
            .joined(separator: " ")
            .split(separator: " ")
            .count
        return max(1, Int(ceil(Double(wordCount) / 220.0)))
    }
}

private struct BookmarkThumbnailView: View {
    let urlString: String?
    let accentColor: Color

    var body: some View {
        GeometryReader { proxy in
            let parallaxOffset = min(max((proxy.frame(in: .global).minY - 210) / 22, -6), 6)

            Group {
                if let urlString,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else if phase.error != nil {
                            fallback
                        } else {
                            Rectangle()
                                .fill(AppTheme.cardBackground.opacity(0.45))
                                .shimmering()
                        }
                    }
                } else {
                    fallback
                }
            }
            .offset(y: parallaxOffset)
        }
        .frame(width: 60, height: 60)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor.opacity(0.9), AppTheme.accentSecondary.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "newspaper.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }
}

private struct BookmarkTopicCardView: View {
    let topic: Topic
    let cardColor: Color
    let accentColor: Color
    let appearDelay: Double

    @State private var didAppear = false

    private let cornerRadius: CGFloat = 20

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: topicIcon)
                    .font(.headline)
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.titleText)
                    .lineLimit(2)

                Text(topic.category)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtitleText)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.subtitleText.opacity(0.8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(topicCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 6)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 12)
        .animation(.easeOut(duration: 0.34).delay(appearDelay), value: didAppear)
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }

    private var topicCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardColor.opacity(0.54))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.16), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var topicIcon: String {
        let haystack = (topic.title + " " + topic.category).lowercased()

        if haystack.contains("quantum") || haystack.contains("physics") {
            return "atom"
        }
        if haystack.contains("space") || haystack.contains("orbit") {
            return "sparkles"
        }
        if haystack.contains("bio") || haystack.contains("dna") {
            return "leaf.fill"
        }
        if haystack.contains("ai") || haystack.contains("machine") {
            return "brain.head.profile"
        }
        return "book.pages.fill"
    }
}

private struct SwipeableBookmarkCard<Content: View>: View {
    let accentColor: Color
    let onLeadingAction: () -> Void
    let onTrailingAction: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var horizontalOffset: CGFloat = 0

    var body: some View {
        ZStack {
            swipeBackground

            content()
                .offset(x: horizontalOffset)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    horizontalOffset = max(-98, min(98, value.translation.width))
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        horizontalOffset = 0
                        return
                    }

                    if value.translation.width <= -86 {
                        triggerSwipeAction(targetOffset: -72, action: onTrailingAction)
                    } else if value.translation.width >= 86 {
                        triggerSwipeAction(targetOffset: 72, action: onLeadingAction)
                    } else {
                        horizontalOffset = 0
                    }
                }
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: horizontalOffset)
    }

    private var swipeBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.clear)
            .overlay {
                HStack {
                    SwipeHintPill(
                        title: "Share",
                        icon: "square.and.arrow.up",
                        tint: accentColor,
                        progress: max(0, min(1, horizontalOffset / 86))
                    )

                    Spacer()

                    SwipeHintPill(
                        title: "Delete",
                        icon: "trash.fill",
                        tint: .red,
                        progress: max(0, min(1, -horizontalOffset / 86))
                    )
                }
                .padding(.horizontal, 14)
            }
    }

    private func triggerSwipeAction(targetOffset: CGFloat, action: @escaping () -> Void) {
        horizontalOffset = targetOffset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            action()
            horizontalOffset = 0
        }
    }
}

private struct SwipeHintPill: View {
    let title: String
    let icon: String
    let tint: Color
    let progress: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.16))
        .clipShape(Capsule())
        .opacity(Double(progress))
        .scaleEffect(0.9 + (0.1 * progress))
    }
}

private struct BookmarkCardButtonStyle: ButtonStyle {
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accentColor.opacity(configuration.isPressed ? 0.42 : 0), lineWidth: 1.2)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(configuration.isPressed ? 0.16 : 0), .clear],
                            center: .center,
                            startRadius: 1,
                            endRadius: 220
                        )
                    )
                    .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

private struct BookmarkEmptyStateView: View {
    let accentColor: Color

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.16))
                    .frame(width: 98, height: 98)
                    .scaleEffect(pulse ? 1.04 : 0.96)

                Image(systemName: "bookmark.slash.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(accentColor)
                    .scaleEffect(pulse ? 1.03 : 0.97)
            }

            Text("No saved articles yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.titleText)

            Text("Save stories from Trending, News, or Recommended and they will appear here.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 24)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
