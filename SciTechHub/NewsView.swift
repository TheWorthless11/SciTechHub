import SwiftUI

struct NewsView: View {
    @StateObject private var viewModel = NewsViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.scienceArticles.isEmpty && viewModel.techArticles.isEmpty {
                loadingState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        articleSection(
                            title: "Science Frontier",
                            subtitle: "Breakthroughs, discoveries, and space updates.",
                            articles: viewModel.scienceArticles
                        )

                        articleSection(
                            title: "Tech Pulse",
                            subtitle: "AI, products, and future-defining engineering.",
                            articles: viewModel.techArticles
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .navigationTitle("Top News")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.scienceArticles.isEmpty {
                viewModel.fetchScienceNews()
            }
            if viewModel.techArticles.isEmpty {
                viewModel.fetchTechNews()
            }
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

    private var loadingState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(0..<4, id: \.self) { _ in
                    ArticleCardSkeletonView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 26)
        }
    }

    private func articleSection(title: String, subtitle: String, articles: [Article]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.titleText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtitleText)
            }

            ForEach(articles, id: \.id) { article in
                ZStack(alignment: .topTrailing) {
                    NavigationLink(destination: NewsArticleDetailView(article: article)) {
                        ArticleCardView(article: article)
                    }
                    .buttonStyle(.plain)

                    quickActionBar(for: article)
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
}

struct NewsArticleDetailView: View {
    let article: Article

    private enum ArticleTextOutputMode: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case simplified = "Simplified"

        var id: String {
            rawValue
        }
    }

    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var userActivityViewModel: UserActivityViewModel
    @StateObject private var articleViewModel = ArticleViewModel()
    @StateObject private var notesViewModel = ArticleNotesViewModel()
    @StateObject private var commentViewModel = ArticleCommentViewModel()

    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false
    @State private var showShareSheet = false
    @State private var showInteractionToast = false
    @State private var interactionToastMessage = "Saved"
    @State private var selectedTextOutputMode: ArticleTextOutputMode = .summary
    @State private var didAppear = false
    @FocusState private var isCommentInputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeaderView(article: article)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 14) {
                    if let description = article.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(AppTheme.subtitleText)
                    } else {
                        Text("No description available for this article.")
                            .font(.body)
                            .foregroundStyle(AppTheme.subtitleText)
                    }

                    detailActionRow

                    if let urlString = article.url,
                       let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.circle.fill")
                                Text("Read Full Article")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(AppTheme.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    summaryFeatureSection
                    notesFeatureSection
                    commentsFeatureSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
            }
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 14)
            .animation(.easeOut(duration: 0.34), value: didAppear)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: handleShareTap) {
                    Image(systemName: "paperplane")
                        .foregroundStyle(AppTheme.accentPrimary)
                }
            }
        }
        .overlay(alignment: .top) {
            if showInteractionToast {
                Text(interactionToastMessage)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .alert("Login to access this feature", isPresented: $showLoginPrompt) {
            Button("Not Now", role: .cancel) { }
            Button("Login") {
                showLoginSheet = true
            }
        } message: {
            Text("Login to react or save articles.")
        }
        .alert("Delete note?", isPresented: $notesViewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                notesViewModel.deleteNote()
            }
        } message: {
            Text("This note will be permanently removed for this article.")
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            ArticleShareSheet(article: article)
        }
        .safeAreaInset(edge: .bottom) {
            commentInputBar
        }
        .onAppear {
            didAppear = true
            userActivityViewModel.trackArticleRead(article: article)
            notesViewModel.configure(for: article, currentUser: authViewModel.user)
            commentViewModel.startListening(for: article)
        }
        .onChange(of: authViewModel.user?.uid) { _ in
            notesViewModel.configure(for: article, currentUser: authViewModel.user)
        }
        .onDisappear {
            commentViewModel.stopListening(clearState: false)
        }
    }

    private var loveIconName: String {
        if authViewModel.isLoggedIn {
            return bookmarkManager.isArticleLoved(article: article) ? "heart.fill" : "heart"
        }
        return "heart"
    }

    private var loveIconColor: Color {
        if authViewModel.isLoggedIn {
            return bookmarkManager.isArticleLoved(article: article) ? .red : .gray
        }
        return .gray
    }

    private var bookmarkIconName: String {
        if authViewModel.isLoggedIn {
            return bookmarkManager.isArticleBookmarked(article: article) ? "bookmark.fill" : "bookmark"
        }
        return "bookmark"
    }

    private var bookmarkIconColor: Color {
        if authViewModel.isLoggedIn {
            return bookmarkManager.isArticleBookmarked(article: article) ? AppTheme.accentPrimary : .gray
        }
        return .gray
    }

    private var detailActionRow: some View {
        HStack(spacing: 10) {
            detailActionButton(
                title: "Like",
                icon: loveIconName,
                foreground: loveIconColor
            ) {
                handleLoveTap()
            }

            detailActionButton(
                title: "Save",
                icon: bookmarkIconName,
                foreground: bookmarkIconColor
            ) {
                handleBookmarkTap()
            }

            detailActionButton(
                title: "Summarize",
                icon: "wand.and.stars",
                foreground: AppTheme.accentPrimary
            ) {
                selectedTextOutputMode = .summary
                articleViewModel.generateSummary(for: article)
            }
        }
    }

    private func detailActionButton(
        title: String,
        icon: String,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(foreground.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(SpringyButtonStyle())
    }

    private func handleLoveTap() {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

        HapticFeedback.tap(.light)
        let wasLoved = bookmarkManager.isArticleLoved(article: article)
        bookmarkManager.toggleArticleLove(article: article)
        showToast(message: wasLoved ? "Love removed" : "Loved!")
    }

    private func handleBookmarkTap() {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

        HapticFeedback.tap(.light)
        let wasBookmarked = bookmarkManager.isArticleBookmarked(article: article)
        bookmarkManager.toggleArticleBookmark(article: article)
        showToast(message: wasBookmarked ? "Bookmark removed" : "Bookmarked!")
    }

    private func handleShareTap() {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

        showShareSheet = true
    }

    private func showToast(message: String) {
        interactionToastMessage = message
        withAnimation {
            showInteractionToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                showInteractionToast = false
            }
        }
    }

    private func handleCommentLike(_ comment: ArticleComment) {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

        commentViewModel.toggleLike(for: comment)
    }

    private func handleReply(to comment: ArticleComment) {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

        commentViewModel.beginReply(to: comment)
        isCommentInputFocused = true
    }

    private func isCommentLiked(_ comment: ArticleComment) -> Bool {
        guard let currentUserId = authViewModel.user?.uid else {
            return false
        }

        return comment.likedBy.contains(currentUserId)
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var summaryFeatureSection: some View {
        let hasSummary = !articleViewModel.summaryText.isEmpty
        let hasSimplified = !articleViewModel.simplifiedText.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: {
                    selectedTextOutputMode = .summary
                    articleViewModel.generateSummary(for: article)
                }) {
                    HStack(spacing: 8) {
                        if articleViewModel.isSummarizing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }

                        Text("Summarize")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer(minLength: 0)
                        Image(systemName: "sparkles")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(articleViewModel.isProcessing ? Color.gray : AppTheme.accentSecondary)
                    .cornerRadius(12)
                }
                .disabled(articleViewModel.isProcessing)

                Button(action: {
                    selectedTextOutputMode = .simplified
                    articleViewModel.generateSimplifiedText(for: article)
                }) {
                    HStack(spacing: 8) {
                        if articleViewModel.isSimplifying {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }

                        Text("Simplify Content")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer(minLength: 0)
                        Image(systemName: "wand.and.stars")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(articleViewModel.isProcessing ? Color.gray : AppTheme.accentPrimary)
                    .cornerRadius(12)
                }
                .disabled(articleViewModel.isProcessing)
            }

            if articleViewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Processing article text...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if let errorMessage = articleViewModel.processingError {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }

            if hasSummary && hasSimplified {
                Picker("Result", selection: $selectedTextOutputMode) {
                    ForEach(ArticleTextOutputMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if hasSummary,
               selectedTextOutputMode == .summary || !hasSimplified {
                VStack(alignment: .leading, spacing: 10) {
                    Label("AI Summary", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.accentSecondary)

                    Text(articleViewModel.summaryText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.accentSecondary.opacity(0.13))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.accentSecondary.opacity(0.28), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if hasSimplified,
               selectedTextOutputMode == .simplified || !hasSummary {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Simplified Content", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.accentPrimary)

                    Text(articleViewModel.simplifiedText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.accentPrimary.opacity(0.13))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.accentPrimary.opacity(0.28), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: articleViewModel.summaryText)
        .animation(.easeInOut(duration: 0.25), value: articleViewModel.simplifiedText)
        .animation(.easeInOut(duration: 0.2), value: selectedTextOutputMode)
    }

    private var notesFeatureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("My Notes", systemImage: "square.and.pencil")
                    .font(.headline)

                Spacer()

                if notesViewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if authViewModel.isLoggedIn {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notesViewModel.noteText)
                            .frame(minHeight: 130)
                            .padding(6)
                            .background(AppTheme.cardBackground.opacity(0.72))
                            .cornerRadius(12)

                        if notesViewModel.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Write your thoughts here...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }

                    HStack(spacing: 10) {
                        Button(notesViewModel.isSaving ? "Saving..." : (notesViewModel.hasSavedNote ? "Update Note" : "Save Note")) {
                            notesViewModel.saveNote()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundColor(.white)
                        .background(notesViewModel.isSaving ? Color.gray : AppTheme.accentSecondary)
                        .cornerRadius(10)
                        .disabled(notesViewModel.isSaving)

                        Button("Delete") {
                            notesViewModel.requestDelete()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundColor(.red)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(10)
                        .disabled(notesViewModel.isSaving || (!notesViewModel.hasSavedNote && notesViewModel.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                        Spacer()
                    }

                    if let success = notesViewModel.successMessage {
                        Text(success)
                            .font(.footnote)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }

                    if let error = notesViewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardBackground.opacity(0.82))
                .cornerRadius(14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Login to write personal notes for this article.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button {
                        showLoginSheet = true
                    } label: {
                        Text("Login to save notes")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundColor(.white)
                            .background(AppTheme.accentPrimary)
                            .cornerRadius(10)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardBackground.opacity(0.82))
                .cornerRadius(14)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notesViewModel.successMessage)
    }

    private var commentsFeatureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Discussion", systemImage: "text.bubble")
                    .font(.headline)

                Spacer()

                Picker("Sort", selection: $commentViewModel.sortOption) {
                    ForEach(CommentSortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
            }

            if commentViewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading comments...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardBackground.opacity(0.82))
                .cornerRadius(12)
            } else if commentViewModel.threadedComments.isEmpty {
                Text("No comments yet. Start the discussion.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground.opacity(0.82))
                    .cornerRadius(12)
            } else {
                VStack(spacing: 10) {
                    ForEach(commentViewModel.threadedComments) { thread in
                        VStack(spacing: 8) {
                            CommentCardView(
                                comment: thread.root,
                                isReply: false,
                                isLiked: isCommentLiked(thread.root),
                                isLikePending: commentViewModel.pendingLikeCommentIds.contains(thread.root.id),
                                timestampText: relativeTimeString(for: thread.root.createdAt),
                                likeAction: {
                                    handleCommentLike(thread.root)
                                },
                                replyAction: {
                                    handleReply(to: thread.root)
                                }
                            )

                            ForEach(thread.replies) { reply in
                                CommentCardView(
                                    comment: reply,
                                    isReply: true,
                                    isLiked: isCommentLiked(reply),
                                    isLikePending: commentViewModel.pendingLikeCommentIds.contains(reply.id),
                                    timestampText: relativeTimeString(for: reply.createdAt),
                                    likeAction: {
                                        handleCommentLike(reply)
                                    },
                                    replyAction: {
                                        handleReply(to: reply)
                                    }
                                )
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: commentViewModel.renderKey)
            }

            if let error = commentViewModel.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
            }
        }
    }

    private var commentInputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTarget = commentViewModel.replyingTo {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.right.fill")
                        .foregroundColor(AppTheme.accentPrimary)
                    Text("Replying to \(replyTarget.authorName)")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Cancel") {
                        commentViewModel.cancelReply()
                    }
                    .font(.footnote.weight(.semibold))
                }
            }

            if authViewModel.isLoggedIn {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Share your thoughts...", text: $commentViewModel.draftCommentText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isCommentInputFocused)

                    Button(commentViewModel.isPosting ? "Posting..." : "Post") {
                        commentViewModel.postComment(for: article)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .foregroundColor(.white)
                    .background(commentViewModel.canPost ? AppTheme.accentPrimary : Color.gray)
                    .cornerRadius(10)
                    .disabled(!commentViewModel.canPost)
                }
            } else {
                Button {
                    showLoginSheet = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Login to join discussion")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(AppTheme.accentPrimary)
                    .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}

private struct CommentCardView: View {
    let comment: ArticleComment
    let isReply: Bool
    let isLiked: Bool
    let isLikePending: Bool
    let timestampText: String
    let likeAction: () -> Void
    let replyAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            UserAvatarView(imageURL: comment.authorPhotoURL, size: isReply ? 30 : 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.subheadline.weight(.semibold))

                    Text(timestampText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(comment.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Button(action: likeAction) {
                        HStack(spacing: 4) {
                            if isLikePending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: isLiked ? "arrow.up.circle.fill" : "arrow.up.circle")
                            }

                            Text("\(comment.likesCount)")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLikePending)

                    Button("Reply", action: replyAction)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                }
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.leading, isReply ? 24 : 0)
    }
}

struct NewsView_Previews: PreviewProvider {
    static var previews: some View {
        NewsView()
            .environmentObject(AuthViewModel())
            .environmentObject(BookmarkManager())
            .environmentObject(UserActivityViewModel())
    }
}
