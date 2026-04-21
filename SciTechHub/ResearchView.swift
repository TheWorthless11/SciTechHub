import SwiftUI
import UIKit

struct ResearchView: View {
    @StateObject private var viewModel = ResearchViewModel()
    @EnvironmentObject var bookmarkManager: BookmarkManager

    @FocusState private var isSearchFieldFocused: Bool
    @State private var showSearchField = false
    @State private var didAppearHeader = false

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    headerSection

                    if showSearchField {
                        searchField
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    categoryFiltersSection

                    ResearchAnimatedSegmentControl(selection: $viewModel.sortOption, accentGradient: accentGradient)

                    recommendationBanner

                    contentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .tabBarOverlayBottomPadding(extra: 24)
            }
            .refreshable {
                await runSearchAction()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage,
               !error.isEmpty,
               !viewModel.papers.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.top, 8)
            }
        }
        .task {
            await viewModel.loadInitialPapersIfNeeded()
        }
        .onAppear {
            if !didAppearHeader {
                withAnimation(.easeOut(duration: 0.35)) {
                    didAppearHeader = true
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Research Papers")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.titleText)

                Text("Explore recent and relevant scientific work")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtitleText)
            }

            Spacer(minLength: 8)

            Button {
                handleSearchTap()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.titleText)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 6)
            }
            .buttonStyle(SpringyButtonStyle())
            .accessibilityLabel("Search papers")
        }
        .opacity(didAppearHeader ? 1 : 0)
        .offset(y: didAppearHeader ? 0 : 10)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.subtitleText)

            TextField("Search papers (AI, robotics, climate...)", text: $viewModel.searchText)
                .focused($isSearchFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(AppTheme.titleText)
                .onSubmit {
                    Task {
                        await runSearchAction()
                    }
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.subtitleText.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            Button {
                Task {
                    await runSearchAction()
                }
            } label: {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var categoryFiltersSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ResearchCategoryChip.allCases) { category in
                    FilterChipView(
                        title: category.rawValue,
                        isSelected: viewModel.selectedCategory == category,
                        accentGradient: accentGradient
                    ) {
                        HapticFeedback.tap(.light)
                        Task {
                            await viewModel.selectCategory(category)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var recommendationBanner: some View {
        if let recommendation = viewModel.recommendationBannerText,
           !recommendation.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(accentColor)

                Text(recommendation)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.titleText)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardColor.opacity(0.48))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accentColor.opacity(0.22), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if viewModel.isLoading && viewModel.papers.isEmpty {
            LazyVStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    ResearchPaperSkeletonCard()
                }
            }
        } else if viewModel.papers.isEmpty {
            ResearchEmptyStateView(
                accentColor: accentColor,
                errorText: viewModel.errorMessage,
                onRetry: {
                    Task {
                        await runSearchAction()
                    }
                }
            )
            .padding(.top, 8)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(Array(viewModel.papers.enumerated()), id: \.element.id) { index, paper in
                    ResearchPaperRow(
                        paper: paper,
                        isBookmarked: bookmarkManager.isArticleBookmarked(article: paper.toArticle()),
                        cardColor: cardColor,
                        accentColor: accentColor,
                        appearDelay: Double(index) * 0.05,
                        onBookmarkTap: {
                            toggleBookmark(for: paper)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            await viewModel.loadMoreIfNeeded(currentPaper: paper)
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 8)
                        Spacer()
                    }
                } else if !viewModel.hasMoreResults && !viewModel.papers.isEmpty {
                    Text("You reached the end of results")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.subtitleText)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.84), value: viewModel.papers.map(\.id))
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
                .frame(width: 230, height: 230)
                .blur(radius: 42)
                .offset(x: 130, y: -250)

            Circle()
                .fill(accentColor.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 38)
                .offset(x: -140, y: 260)
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

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, AppTheme.accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func handleSearchTap() {
        HapticFeedback.tap(.light)

        if showSearchField {
            Task {
                await runSearchAction()
            }
            return
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            showSearchField = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isSearchFieldFocused = true
        }
    }

    private func runSearchAction() async {
        if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await viewModel.loadLatestPapers()
        } else {
            await viewModel.searchPapers()
        }
    }

    private func toggleBookmark(for paper: ResearchPaper) {
        let article = paper.toArticle()
        let wasBookmarked = bookmarkManager.isArticleBookmarked(article: article)

        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            bookmarkManager.toggleArticleBookmark(article: article)
        }

        if !wasBookmarked {
            viewModel.recordBookmarkInterest(for: paper)
        }
    }
}

private struct ResearchPaperRow: View {
    let paper: ResearchPaper
    let isBookmarked: Bool
    let cardColor: Color
    let accentColor: Color
    let appearDelay: Double
    let onBookmarkTap: () -> Void

    @State private var didAppear = false
    @State private var bookmarkTapPulse = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(destination: ResearchDetailView(paper: paper)) {
                PaperCardView(
                    paper: paper,
                    cardColor: cardColor,
                    accentColor: accentColor
                )
            }
            .buttonStyle(PaperCardButtonStyle(accentColor: accentColor))
            .simultaneousGesture(
                TapGesture().onEnded {
                    HapticFeedback.tap(.light)
                }
            )

            Button {
                HapticFeedback.tap(.medium)
                onBookmarkTap()

                bookmarkTapPulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    bookmarkTapPulse = false
                }
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isBookmarked ? accentColor : AppTheme.subtitleText)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.15), radius: 7, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .scaleEffect(bookmarkTapPulse ? 0.88 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.66), value: bookmarkTapPulse)
            .padding(12)
        }
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 12)
        .animation(.easeOut(duration: 0.34).delay(appearDelay), value: didAppear)
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }
}

struct PaperCardView: View {
    let paper: ResearchPaper
    let cardColor: Color
    let accentColor: Color

    private let cornerRadius: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(paper.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.titleText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.trailing, 42)

            Text(paper.authorsText)
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)
                .lineLimit(2)

            Text(paper.shortAbstract)
                .font(.footnote)
                .foregroundStyle(AppTheme.subtitleText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)

            HStack(spacing: 8) {
                ResearchMetaBadge(label: paper.yearText, symbol: "calendar")
                ResearchMetaBadge(label: paper.authorCountText, symbol: "person.2")

                if let category = paper.categoryLabel {
                    ResearchMetaBadge(label: category, symbol: "tag")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        .shadow(color: accentColor.opacity(0.12), radius: 10, x: 0, y: 0)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(cardColor.opacity(0.55))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.18), Color.clear],
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
}

struct FilterChipView: View {
    let title: String
    let isSelected: Bool
    let accentGradient: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : AppTheme.subtitleText)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(chipBackground)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isSelected)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Capsule()
                .fill(accentGradient)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        } else {
            Capsule()
                .fill(Color.black.opacity(0.24))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

struct ResearchAnimatedSegmentControl: View {
    @Binding var selection: ResearchSortOption
    let accentGradient: LinearGradient

    @Namespace private var segmentNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ResearchSortOption.allCases) { option in
                let isSelected = selection == option

                Button {
                    HapticFeedback.tap(.light)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : AppTheme.subtitleText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(accentGradient)
                                    .matchedGeometryEffect(id: "segment-indicator", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.22))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct ResearchMetaBadge: View {
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppTheme.subtitleText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

private struct PaperCardButtonStyle: ButtonStyle {
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accentColor.opacity(configuration.isPressed ? 0.34 : 0), lineWidth: 1.2)
                    .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ResearchPaperSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.55))
                .frame(height: 20)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.46))
                .frame(height: 16)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.42))
                .frame(height: 46)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.42))
                    .frame(width: 64, height: 22)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.36))
                    .frame(width: 82, height: 22)

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
        .shimmering()
    }
}

private struct ResearchEmptyStateView: View {
    let accentColor: Color
    let errorText: String?
    let onRetry: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.04 : 0.96)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(accentColor)
                    .scaleEffect(pulse ? 1.03 : 0.97)
            }

            Text("No papers found")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.titleText)

            Text("Try another keyword or category to explore research papers.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)

            if let errorText,
               !errorText.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
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
