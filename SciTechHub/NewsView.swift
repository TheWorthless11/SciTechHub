import SwiftUI

struct NewsView: View {
    @StateObject private var viewModel = NewsViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                // Show a simple loading indicator
                ProgressView("Loading...")
            } else {
                List {
                    // Science News Section
                    Section(header: Text("Science News")) {
                        ForEach(viewModel.scienceArticles, id: \.id) { article in
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
                    
                    // Technology News Section
                    Section(header: Text("Technology News")) {
                        ForEach(viewModel.techArticles, id: \.id) { article in
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
}

// Extracted into a small subview to keep code clean and simple
struct ArticleRow: View {
    let article: Article
    let isLoggedIn: Bool
    let onRestrictedAction: () -> Void
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

            VStack(spacing: 8) {
                Button(action: {
                    if isLoggedIn {
                        bookmarkManager.toggleArticleLove(article: article)
                    } else {
                        onRestrictedAction()
                    }
                }) {
                    Image(systemName: loveIconName)
                        .foregroundColor(loveIconColor)
                        .padding(8)
                }
                .buttonStyle(BorderlessButtonStyle())

                Button(action: {
                    if isLoggedIn {
                        bookmarkManager.toggleArticleBookmark(article: article)
                    } else {
                        onRestrictedAction()
                    }
                }) {
                    Image(systemName: bookmarkIconName)
                        .foregroundColor(bookmarkIconColor)
                        .padding(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private var loveIconName: String {
        if isLoggedIn {
            return bookmarkManager.isArticleLoved(article: article) ? "heart.fill" : "heart"
        }
        return "heart"
    }

    private var loveIconColor: Color {
        if isLoggedIn {
            return bookmarkManager.isArticleLoved(article: article) ? .red : .gray
        }
        return .gray
    }
    
    private var bookmarkIconName: String {
        if isLoggedIn {
            return bookmarkManager.isArticleBookmarked(article: article) ? "bookmark.fill" : "bookmark"
        }
        return "bookmark"
    }
    
    private var bookmarkIconColor: Color {
        if isLoggedIn {
            return bookmarkManager.isArticleBookmarked(article: article) ? .blue : .gray
        }
        return .gray
    }
}

struct NewsArticleDetailView: View {
    let article: Article

    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var userActivityViewModel: UserActivityViewModel
    @StateObject private var summaryViewModel = ArticleSummaryViewModel()
    @StateObject private var notesViewModel = ArticleNotesViewModel()
    @StateObject private var commentViewModel = ArticleCommentViewModel()

    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false
    @State private var showShareSheet = false
    @State private var showInteractionToast = false
    @State private var interactionToastMessage = "Saved"
    @FocusState private var isCommentInputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageString = article.urlToImage,
                   let imageURL = URL(string: imageString) {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .clipped()
                                .cornerRadius(12)
                        } else if phase.error != nil {
                            Image(systemName: "photo")
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                        }
                    }
                }

                Text(article.title)
                    .font(.title2)
                    .fontWeight(.bold)

                if let description = article.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    Text("No description available for this article.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                if let urlString = article.url,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Text("Read Full Article")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.top, 8)
                }

                summaryFeatureSection
                notesFeatureSection
                commentsFeatureSection
            }
            .padding()
        }
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: handleShareTap) {
                    Image(systemName: "paperplane")
                        .foregroundColor(.blue)
                }

                Button(action: handleLoveTap) {
                    Image(systemName: loveIconName)
                        .foregroundColor(loveIconColor)
                }

                Button(action: handleBookmarkTap) {
                    Image(systemName: bookmarkIconName)
                        .foregroundColor(bookmarkIconColor)
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
            return bookmarkManager.isArticleBookmarked(article: article) ? .blue : .gray
        }
        return .gray
    }

    private func handleLoveTap() {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

        let wasLoved = bookmarkManager.isArticleLoved(article: article)
        bookmarkManager.toggleArticleLove(article: article)
        showToast(message: wasLoved ? "Love removed" : "Loved!")
    }

    private func handleBookmarkTap() {
        guard authViewModel.isLoggedIn else {
            showLoginPrompt = true
            return
        }

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
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                summaryViewModel.onSummaryButtonTap(for: article)
            }) {
                HStack(spacing: 8) {
                    if summaryViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }

                    Text(summaryViewModel.buttonTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: summaryViewModel.isSummaryVisible ? "sparkles.rectangle.stack.fill" : "sparkles")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(summaryViewModel.isLoading ? Color.gray : Color.indigo)
                .cornerRadius(12)
            }
            .disabled(summaryViewModel.isLoading)

            if summaryViewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Generating summary...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if let errorMessage = summaryViewModel.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)

                    Button("Retry") {
                        summaryViewModel.retry(for: article)
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }

            if summaryViewModel.isSummaryVisible,
               let summaryText = summaryViewModel.summaryText {
                VStack(alignment: .leading, spacing: 10) {
                    Label("AI Summary", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.indigo)

                    Text(summaryText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.indigo.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: summaryViewModel.isSummaryVisible)
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
                            .background(Color(.secondarySystemBackground))
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
                        .background(notesViewModel.isSaving ? Color.gray : Color.indigo)
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
                .background(Color(.secondarySystemBackground))
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
                            .background(Color.indigo)
                            .cornerRadius(10)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
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
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            } else if commentViewModel.threadedComments.isEmpty {
                Text("No comments yet. Start the discussion.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
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
                        .foregroundColor(.indigo)
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
                    .background(commentViewModel.canPost ? Color.indigo : Color.gray)
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
                    .background(Color.indigo)
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
