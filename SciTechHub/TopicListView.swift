import Foundation
import SwiftUI
import UIKit

// MARK: - 1. Model
struct Topic: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let category: String
}

// MARK: - 2. ViewModel
class TopicViewModel: ObservableObject {
    // This will hold our topics and tell the View to update when it changes
    @Published var topics: [Topic] = []
    
    // Automatically load the topics when the ViewModel is created
    init() {
        loadTopics()
    }
    
    func loadTopics() {
        // 1. Find the file in our app bundle
        guard let url = Bundle.main.url(forResource: "topics", withExtension: "json") else {
            print("Failed to find topics.json in bundle.")
            return
        }
        
        do {
            // 2. Load the data from the file
            let data = try Data(contentsOf: url)
            
            // 3. Decode the JSON data into an array of strictly-typed `Topic` objects
            let decodedTopics = try JSONDecoder().decode([Topic].self, from: data)
            
            // 4. Update the published UI variable
            self.topics = decodedTopics
        } catch {
            // Very simple error handling
            print("Failed to decode topics.json: \(error.localizedDescription)")
        }
    }
}

// MARK: - 3. TopicListView (Replaces old placeholder)
struct TopicListView: View {
    let categoryName: String // Received from HomeView

    // Connect to the ViewModel
    @StateObject private var viewModel = TopicViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var didShowHeader = false

    var body: some View {
        ZStack {
            backgroundLayer.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    headerSection

                    if filteredTopics.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(Array(filteredTopics.enumerated()), id: \.element.id) { index, topic in
                            NavigationLink(destination: TopicDetailView(topic: topic)) {
                                CategoryDetailCardView(
                                    topic: topic,
                                    icon: iconName(for: topic),
                                    accentColor: accentColor,
                                    cardColor: cardColor,
                                    appearDelay: Double(index) * 0.06
                                )
                            }
                            .buttonStyle(CategoryDetailCardButtonStyle())
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    HapticFeedback.tap(.light)
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .tabBarOverlayBottomPadding(extra: 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didShowHeader {
                withAnimation(.easeOut(duration: 0.36)) {
                    didShowHeader = true
                }
            }
        }
    }

    private var filteredTopics: [Topic] {
        viewModel.topics.filter { $0.category == categoryName }
    }

    private var backgroundLayer: some View {
        ZStack {
            backgroundColor

            LinearGradient(
                colors: [
                    backgroundColor,
                    Color.black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accentColor.opacity(0.16))
                .frame(width: 240, height: 240)
                .blur(radius: 36)
                .offset(x: 140, y: -210)
                .allowsHitTesting(false)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    HapticFeedback.tap(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.titleText)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 5)
                        .shadow(color: accentColor.opacity(0.34), radius: 10, x: 0, y: 0)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Text(categoryName)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.titleText)
                .opacity(didShowHeader ? 1 : 0)
                .offset(y: didShowHeader ? 0 : 8)
                .animation(.easeOut(duration: 0.34), value: didShowHeader)

            Text("\(filteredTopics.count) curated topics")
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)
                .opacity(didShowHeader ? 1 : 0)
                .offset(y: didShowHeader ? 0 : 6)
                .animation(.easeOut(duration: 0.42), value: didShowHeader)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(accentColor)

            Text("No articles available")
                .font(.headline)
                .foregroundStyle(AppTheme.titleText)

            Text("Check back soon for fresh updates in this category.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 24)
        .padding(.top, 12)
    }

    private func iconName(for topic: Topic) -> String {
        let haystack = (topic.title + " " + topic.description + " " + topic.category).lowercased()

        if haystack.contains("dna") || haystack.contains("gene") || haystack.contains("biology") {
            return "leaf.fill"
        }
        if haystack.contains("space") || haystack.contains("planet") || haystack.contains("orbit") {
            return "sparkles"
        }
        if haystack.contains("chem") || haystack.contains("lab") || haystack.contains("molecule") {
            return "flask.fill"
        }
        if haystack.contains("ai") || haystack.contains("machine") || haystack.contains("robot") {
            return "brain.head.profile"
        }

        return "atom"
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
}

private struct CategoryDetailCardView: View {
    let topic: Topic
    let icon: String
    let accentColor: Color
    let cardColor: Color
    var appearDelay: Double = 0

    @State private var didAppear = false

    private let cornerRadius: CGFloat = 22

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(topic.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.titleText)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    Text(topic.category.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(topic.description)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtitleText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        .shadow(color: accentColor.opacity(0.2), radius: 10, x: 0, y: 0)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
        .animation(.easeOut(duration: 0.34).delay(appearDelay), value: didAppear)
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.36), accentColor.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.9)

            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.titleText)
        }
        .frame(width: 44, height: 44)
        .shadow(color: accentColor.opacity(0.24), radius: 8, x: 0, y: 0)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardColor.opacity(0.36))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.24), Color.black.opacity(0.1)],
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
                .blur(radius: 14)
                .padding(8)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accentColor.opacity(0.22), lineWidth: 1.1)
                .blur(radius: 2)
                .opacity(0.75)
        }
    }
}

private struct CategoryDetailCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(configuration.isPressed ? 0.16 : 0), .clear],
                            center: .center,
                            startRadius: 1,
                            endRadius: 220
                        )
                    )
                    .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - 4. TopicDetailView
struct TopicDetailView: View {
    let topic: Topic // Received from TopicListView

    // Connect to our global BookmarkManager
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false
    @State private var didAppear = false
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 1
    @State private var bookmarkTapPulse = false

    private let heroHeight: CGFloat = 308

    var body: some View {
        ZStack {
            backgroundLayer.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: TopicDetailScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("topic_detail_scroll")).minY
                            )
                    }
                    .frame(height: 0)

                    DetailHeaderView(
                        topic: topic,
                        iconName: topicIcon,
                        accentColor: accentColor,
                        cardColor: cardColor,
                        estimatedReadMinutes: estimatedReadMinutes,
                        didAppear: didAppear,
                        heroHeight: heroHeight,
                        scrollOffset: scrollOffset
                    )
                    .frame(height: heroHeight)
                    .padding(.top, 8)

                    SectionCardView(
                        title: "Overview",
                        icon: "text.alignleft",
                        text: topic.description,
                        accentColor: accentColor,
                        cardColor: cardColor,
                        appearDelay: 0.02,
                        didAppear: didAppear,
                        supportsReadMore: true
                    )

                    sectionDivider

                    SectionCardView(
                        title: "Key Concepts",
                        icon: "lightbulb.max.fill",
                        text: keyConceptsText,
                        accentColor: accentColor,
                        cardColor: cardColor,
                        appearDelay: 0.08,
                        didAppear: didAppear
                    )

                    SectionCardView(
                        title: "Examples",
                        icon: "sparkles",
                        text: examplesText,
                        accentColor: accentColor,
                        cardColor: cardColor,
                        appearDelay: 0.14,
                        didAppear: didAppear
                    )

                    SectionCardView(
                        title: "Applications",
                        icon: "bolt.fill",
                        text: applicationsText,
                        accentColor: accentColor,
                        cardColor: cardColor,
                        appearDelay: 0.2,
                        didAppear: didAppear
                    )

                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 14)
                }
                .padding(.horizontal, 16)
                .tabBarOverlayBottomPadding(extra: 26)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: TopicDetailContentHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
            }
            .coordinateSpace(name: "topic_detail_scroll")
            .onPreferenceChange(TopicDetailScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .onPreferenceChange(TopicDetailContentHeightPreferenceKey.self) { value in
                contentHeight = max(1, value)
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        HapticFeedback.tap(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.titleText)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 5)
                    }

                    Spacer()

                    ShareLink(item: sharePayload) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.titleText)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 5)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            HapticFeedback.tap(.light)
                        }
                    )

                    Button {
                        handleBookmarkTap()
                    } label: {
                        Image(systemName: bookmarkIconName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(bookmarkIconColor)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 5)
                            .shadow(color: accentColor.opacity(0.3), radius: 10, x: 0, y: 0)
                    }
                    .scaleEffect(bookmarkTapPulse ? 0.88 : 1)
                    .animation(.spring(response: 0.24, dampingFraction: 0.64), value: bookmarkTapPulse)
                }

                GeometryReader { proxy in
                    let width = max(8, proxy.size.width * readingProgress)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))

                        Capsule()
                            .fill(accentColor)
                            .frame(width: width)
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .navigationBarHidden(true)
        .onAppear {
            if !didAppear {
                withAnimation(.easeOut(duration: 0.36)) {
                    didAppear = true
                }
            }
        }
        .alert("Login to access this feature", isPresented: $showLoginPrompt) {
            Button("Not Now", role: .cancel) { }
            Button("Login") {
                showLoginSheet = true
            }
        } message: {
            Text("Saving topic bookmarks is available for logged-in users.")
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(AppTheme.cardBorder.opacity(0.35))
            .frame(height: 1)
            .padding(.horizontal, 2)
    }

    private var backgroundLayer: some View {
        ZStack {
            backgroundColor

            LinearGradient(
                colors: [
                    backgroundColor,
                    Color.black.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accentColor.opacity(0.18))
                .frame(width: 250, height: 250)
                .blur(radius: 44)
                .offset(x: 130, y: -260)

            Circle()
                .fill(accentColor.opacity(0.1))
                .frame(width: 200, height: 200)
                .blur(radius: 38)
                .offset(x: -170, y: 260)
        }
    }

    private var keyConceptsText: String {
        [
            "\(topic.title) sits in the \(topic.category.lowercased()) domain, where core ideas are tested with repeatable evidence.",
            "Understanding first principles helps explain why systems behave the way they do under different constraints.",
            "New findings often emerge when theory and real-world observations are compared side by side."
        ]
        .map { "- \($0)" }
        .joined(separator: "\n")
    }

    private var examplesText: String {
        [
            "A classroom demonstration can simplify \(topic.title) into a few measurable steps.",
            "Short experiments help isolate variables and reveal cause-and-effect clearly.",
            "Comparing historical and modern case studies shows how models improve over time."
        ]
        .map { "- \($0)" }
        .joined(separator: "\n")
    }

    private var applicationsText: String {
        [
            "Industry teams apply \(topic.title) ideas to improve reliability, safety, and performance.",
            "Research labs use these concepts to prototype future technologies with measurable impact.",
            "Education and policy settings benefit from simplified interpretations that support better decisions."
        ]
        .map { "- \($0)" }
        .joined(separator: "\n")
    }

    private var estimatedReadMinutes: Int {
        let combined = [topic.title, topic.description, keyConceptsText, examplesText, applicationsText].joined(separator: " ")
        let words = combined.split(separator: " ").count
        return max(1, Int(ceil(Double(words) / 220.0)))
    }

    private var readingProgress: CGFloat {
        let totalScrollable = max(1, contentHeight - 500)
        let progress = min(max((-scrollOffset) / totalScrollable, 0), 1)
        return progress
    }

    private var bookmarkIconName: String {
        if !authViewModel.isLoggedIn {
            return "lock.fill"
        }
        return bookmarkManager.isBookmarked(topic: topic) ? "bookmark.fill" : "bookmark"
    }

    private var bookmarkIconColor: Color {
        authViewModel.isLoggedIn ? accentColor : .orange
    }

    private var sharePayload: String {
        "\(topic.title)\n\n\(topic.description)\n\nShared from SciTechHub"
    }

    private var topicIcon: String {
        let haystack = (topic.title + " " + topic.description + " " + topic.category).lowercased()

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

    private var backgroundColor: Color {
        UIColor(named: "Background") == nil ? AppTheme.background : Color("Background")
    }

    private var cardColor: Color {
        UIColor(named: "Card") == nil ? AppTheme.cardBackground : Color("Card")
    }

    private var accentColor: Color {
        UIColor(named: "Accent") == nil ? AppTheme.accentPrimary : Color("Accent")
    }

    private func handleBookmarkTap() {
        guard authViewModel.isLoggedIn else {
            HapticFeedback.tap(.light)
            showLoginPrompt = true
            return
        }

        HapticFeedback.tap(.medium)
        bookmarkManager.toggleBookmark(topic: topic)

        bookmarkTapPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            bookmarkTapPulse = false
        }
    }

    private struct DetailHeaderView: View {
        let topic: Topic
        let iconName: String
        let accentColor: Color
        let cardColor: Color
        let estimatedReadMinutes: Int
        let didAppear: Bool
        let heroHeight: CGFloat
        let scrollOffset: CGFloat

        var body: some View {
            let stretch = max(0, scrollOffset)
            let parallax = scrollOffset > 0 ? -scrollOffset : scrollOffset * 0.33

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                cardColor.opacity(0.6),
                                accentColor.opacity(0.42),
                                Color.black.opacity(0.46)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: iconName)
                    .font(.system(size: 130, weight: .thin))
                    .foregroundStyle(Color.white.opacity(0.12))
                    .offset(x: 72, y: -72)

                LinearGradient(
                    colors: [Color.black.opacity(0.08), Color.black.opacity(0.34), Color.black.opacity(0.74)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(topic.category.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(accentColor.opacity(0.14))
                            .clipShape(Capsule())
                            .shadow(color: accentColor.opacity(0.32), radius: 10, x: 0, y: 0)

                        Label("\(estimatedReadMinutes) min read", systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.88))
                    }

                    Text(topic.title)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .opacity(didAppear ? 1 : 0)
                        .scaleEffect(didAppear ? 1 : 0.96, anchor: .leading)
                        .animation(.easeOut(duration: 0.36), value: didAppear)
                }
                .padding(20)
            }
            .frame(height: heroHeight + stretch)
            .offset(y: parallax)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 10)
        }
    }

    private struct SectionCardView: View {
        let title: String
        let icon: String
        let text: String
        let accentColor: Color
        let cardColor: Color
        let appearDelay: Double
        let didAppear: Bool
        var supportsReadMore: Bool = false

        @State private var isExpanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accentColor)

                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.titleText)
                }

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtitleText)
                    .lineSpacing(4)
                    .lineLimit(isExpanded || !supportsReadMore ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if supportsReadMore {
                    Button {
                        HapticFeedback.tap(.light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Text(isExpanded ? "Show Less" : "Read More")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 11, x: 0, y: 8)
            .shadow(color: accentColor.opacity(0.12), radius: 10, x: 0, y: 0)
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 12)
            .animation(.easeOut(duration: 0.34).delay(appearDelay), value: didAppear)
        }

        private var cardBackground: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(cardColor.opacity(0.36))

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.24), Color.black.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.16), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 12)
                    .padding(8)
            }
        }
    }
}


private struct TopicDetailScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TopicDetailContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}