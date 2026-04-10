import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        TabView {
            // Tab 1: Home
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            
            // Tab 2: Trending
            TrendingView()
                .tabItem {
                    Label("Trending", systemImage: "flame")
                }
            
            // Tab 3: Bookmarks
            BookmarkWrapperView()
                .tabItem {
                    Label("Saved", systemImage: "bookmark")
                }
            
            // Tab 4: Community
            CommunityWrapperView()
                .tabItem {
                    Label("Community", systemImage: "person.3.sequence.fill")
                }

            // Tab 5: Friends
            FriendsHubWrapperView()
                .tabItem {
                    Label("Friends", systemImage: "person.2")
                }

            // Tab 6: Inbox
            InboxWrapperView()
                .tabItem {
                    Label("Inbox", systemImage: "bubble.left.and.bubble.right")
                }

            // Tab 7: Notes
            NotesWrapperView()
                .tabItem {
                    Label("My Notes", systemImage: "note.text")
                }

            // Tab 8: Live
            LiveNowWrapperView()
                .tabItem {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }

            // Tab 9: Scan
            ScanWrapperView()
                .tabItem {
                    Label("Scan", systemImage: "doc.text.viewfinder")
                }
        }
        // Change the accent color of selected tab
        .accentColor(.blue)
        .onAppear {
            bookmarkManager.loadBookmarks()
            bookmarkManager.loadBookmarkedArticles()
            bookmarkManager.loadLikedArticles()
        }
        .onChange(of: authViewModel.isLoggedIn) { _ in
            bookmarkManager.loadBookmarks()
            bookmarkManager.loadBookmarkedArticles()
            bookmarkManager.loadLikedArticles()
        }
    }
}

// Wrapper for Bookmarks to give it its own NavigationView independently of the Home tab
struct BookmarkWrapperView: View {
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        NavigationView {
            BookmarkView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// Wrapper for Notes to give it its own NavigationView independently of the Home tab
struct NotesWrapperView: View {
    var body: some View {
        NavigationView {
            NotesView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct CommunityTopic: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let symbol: String
}

enum CommunityPostSortOption: String, CaseIterable, Identifiable {
    case top
    case new

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .top:
            return "Top"
        case .new:
            return "New"
        }
    }
}

struct CommunityPost: Identifiable, Hashable {
    let id: String
    let communityId: String
    let title: String
    let description: String
    let authorId: String
    let authorName: String
    let createdAt: Date
    let likedBy: [String]
    let commentCount: Int

    var likeCount: Int {
        likedBy.count
    }
}

struct CommunityComment: Identifiable, Hashable {
    let id: String
    let communityId: String
    let postId: String
    let authorId: String
    let authorName: String
    let text: String
    let createdAt: Date
}

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published private(set) var communities: [CommunityTopic] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var communitiesListener: ListenerRegistration?

    private let defaultCommunities: [CommunityTopic] = [
        CommunityTopic(
            id: "ai",
            name: "AI",
            description: "Discuss artificial intelligence, machine learning, and new breakthroughs.",
            symbol: "brain.head.profile"
        ),
        CommunityTopic(
            id: "space",
            name: "Space",
            description: "Talk about space exploration, astronomy, and cosmic discoveries.",
            symbol: "sparkles"
        ),
        CommunityTopic(
            id: "technology",
            name: "Technology",
            description: "Share the latest discussions on software, hardware, and innovation.",
            symbol: "desktopcomputer"
        )
    ]

    deinit {
        communitiesListener?.remove()
    }

    func startListening() {
        communitiesListener?.remove()
        isLoading = true
        errorMessage = nil

        communitiesListener = db.collection("communities")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "load communities")
                        self.communities = self.defaultCommunities
                        self.isLoading = false
                        return
                    }

                    let firestoreCommunities: [CommunityTopic] = (snapshot?.documents ?? []).compactMap { document in
                        self.community(from: document)
                    }

                    var merged: [String: CommunityTopic] = [:]
                    self.defaultCommunities.forEach { merged[$0.id] = $0 }
                    firestoreCommunities.forEach { merged[$0.id] = $0 }

                    self.communities = merged.values.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    self.errorMessage = nil
                    self.isLoading = false
                }
            }
    }

    private func community(from document: QueryDocumentSnapshot) -> CommunityTopic? {
        let data = document.data()
        let name = data["name"] as? String ?? document.documentID.capitalized
        let description = data["description"] as? String ?? "Join the discussion in this community."
        let symbol = data["symbol"] as? String ?? "person.3.fill"

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return CommunityTopic(
            id: document.documentID,
            name: name,
            description: description,
            symbol: symbol
        )
    }

    private func friendlyErrorMessage(for error: Error, action: String) -> String {
        let nsError = error as NSError

        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You do not have permission to \(action)."
        }

        return "Failed to \(action)."
    }
}

@MainActor
final class PostViewModel: ObservableObject {
    @Published private(set) var posts: [CommunityPost] = []
    @Published var sortOption: CommunityPostSortOption = .top
    @Published var draftPostTitle = ""
    @Published var draftPostDescription = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isCreatingPost = false
    @Published private(set) var pendingVotePostIds: Set<String> = []
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var postsListener: ListenerRegistration?
    private var activeCommunityId: String?

    deinit {
        postsListener?.remove()
    }

    var canCreatePost: Bool {
        !draftPostTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftPostDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCreatingPost
    }

    var sortedPosts: [CommunityPost] {
        switch sortOption {
        case .top:
            return posts.sorted {
                if $0.likeCount == $1.likeCount {
                    return $0.createdAt > $1.createdAt
                }
                return $0.likeCount > $1.likeCount
            }
        case .new:
            return posts.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func startListening(for community: CommunityTopic) {
        if activeCommunityId == community.id, postsListener != nil {
            return
        }

        stopListening(clearState: false)
        activeCommunityId = community.id
        isLoading = true
        errorMessage = nil

        postsListener = postsCollection(for: community.id)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "load posts")
                        self.isLoading = false
                        return
                    }

                    let latestPosts: [CommunityPost] = (snapshot?.documents ?? []).compactMap { document in
                        self.post(from: document)
                    }

                    self.posts = latestPosts
                    self.errorMessage = nil
                    self.isLoading = false
                }
            }
    }

    func stopListening(clearState: Bool = true) {
        postsListener?.remove()
        postsListener = nil
        activeCommunityId = nil

        if clearState {
            posts = []
            pendingVotePostIds = []
            isLoading = false
            isCreatingPost = false
            errorMessage = nil
        }
    }

    func createPost(in community: CommunityTopic, completion: (() -> Void)? = nil) {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Login required to create a post."
            return
        }

        let trimmedTitle = draftPostTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = draftPostDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty, !trimmedDescription.isEmpty else {
            return
        }

        if isCreatingPost {
            return
        }

        isCreatingPost = true
        errorMessage = nil

        resolveAuthorName(for: user) { [weak self] authorName in
            guard let self = self else { return }

            let payload: [String: Any] = [
                "communityId": community.id,
                "title": trimmedTitle,
                "description": trimmedDescription,
                "authorId": user.uid,
                "authorName": authorName,
                "createdAt": FieldValue.serverTimestamp(),
                "likedBy": [],
                "commentCount": 0
            ]

            self.postsCollection(for: community.id).addDocument(data: payload) { error in
                DispatchQueue.main.async {
                    self.isCreatingPost = false

                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "create post")
                        return
                    }

                    self.draftPostTitle = ""
                    self.draftPostDescription = ""
                    self.errorMessage = nil
                    completion?()
                }
            }
        }
    }

    func toggleUpvote(for post: CommunityPost) {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Login required to vote on posts."
            return
        }

        guard let communityId = activeCommunityId else {
            return
        }

        if pendingVotePostIds.contains(post.id) {
            return
        }

        pendingVotePostIds.insert(post.id)
        let alreadyLiked = post.likedBy.contains(userId)
        let updateValue = alreadyLiked
            ? FieldValue.arrayRemove([userId])
            : FieldValue.arrayUnion([userId])

        postsCollection(for: communityId)
            .document(post.id)
            .updateData(["likedBy": updateValue]) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.pendingVotePostIds.remove(post.id)

                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "vote on post")
                    }
                }
            }
    }

    private func postsCollection(for communityId: String) -> CollectionReference {
        db.collection("communities")
            .document(communityId)
            .collection("posts")
    }

    private func post(from document: QueryDocumentSnapshot) -> CommunityPost? {
        let data = document.data()

        guard let communityId = data["communityId"] as? String,
              let title = data["title"] as? String,
              let description = data["description"] as? String,
              let authorId = data["authorId"] as? String else {
            return nil
        }

        let authorName = data["authorName"] as? String ?? "User"
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let likedBy = data["likedBy"] as? [String] ?? []
        let commentCount = data["commentCount"] as? Int ?? 0

        return CommunityPost(
            id: document.documentID,
            communityId: communityId,
            title: title,
            description: description,
            authorId: authorId,
            authorName: authorName,
            createdAt: createdAt,
            likedBy: likedBy,
            commentCount: commentCount
        )
    }

    private func resolveAuthorName(for user: User, completion: @escaping (String) -> Void) {
        db.collection("users")
            .document(user.uid)
            .getDocument { snapshot, _ in
                let data = snapshot?.data() ?? [:]
                let authorName = (data["name"] as? String)
                    ?? user.displayName
                    ?? user.email
                    ?? "User"
                completion(authorName)
            }
    }

    private func friendlyErrorMessage(for error: Error, action: String) -> String {
        let nsError = error as NSError

        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You do not have permission to \(action)."
        }

        return "Failed to \(action)."
    }
}

@MainActor
final class CommentViewModel: ObservableObject {
    @Published private(set) var comments: [CommunityComment] = []
    @Published var draftCommentText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var commentsListener: ListenerRegistration?
    private var activeCommunityId: String?
    private var activePostId: String?

    deinit {
        commentsListener?.remove()
    }

    var canPost: Bool {
        !draftCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
    }

    func startListening(communityId: String, postId: String) {
        if activeCommunityId == communityId,
           activePostId == postId,
           commentsListener != nil {
            return
        }

        stopListening(clearState: false)
        activeCommunityId = communityId
        activePostId = postId
        isLoading = true
        errorMessage = nil

        commentsListener = commentsCollection(communityId: communityId, postId: postId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "load comments")
                        self.isLoading = false
                        return
                    }

                    self.comments = (snapshot?.documents ?? []).compactMap { document in
                        self.comment(from: document)
                    }
                    self.errorMessage = nil
                    self.isLoading = false
                }
            }
    }

    func stopListening(clearState: Bool = true) {
        commentsListener?.remove()
        commentsListener = nil
        activeCommunityId = nil
        activePostId = nil

        if clearState {
            comments = []
            draftCommentText = ""
            isLoading = false
            isPosting = false
            errorMessage = nil
        }
    }

    func postComment() {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Login required to comment."
            return
        }

        guard let communityId = activeCommunityId,
              let postId = activePostId else {
            errorMessage = "Unable to resolve comment target."
            return
        }

        let trimmedText = draftCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        if isPosting {
            return
        }

        isPosting = true
        errorMessage = nil

        resolveAuthorName(for: user) { [weak self] authorName in
            guard let self = self else { return }

            let payload: [String: Any] = [
                "communityId": communityId,
                "postId": postId,
                "authorId": user.uid,
                "authorName": authorName,
                "text": trimmedText,
                "createdAt": FieldValue.serverTimestamp()
            ]

            self.commentsCollection(communityId: communityId, postId: postId)
                .addDocument(data: payload) { error in
                    DispatchQueue.main.async {
                        self.isPosting = false

                        if let error = error {
                            self.errorMessage = self.friendlyErrorMessage(for: error, action: "post comment")
                            return
                        }

                        self.postsCollection(for: communityId)
                            .document(postId)
                            .updateData(["commentCount": FieldValue.increment(Int64(1))])

                        self.draftCommentText = ""
                        self.errorMessage = nil
                    }
                }
        }
    }

    private func postsCollection(for communityId: String) -> CollectionReference {
        db.collection("communities")
            .document(communityId)
            .collection("posts")
    }

    private func commentsCollection(communityId: String, postId: String) -> CollectionReference {
        postsCollection(for: communityId)
            .document(postId)
            .collection("comments")
    }

    private func comment(from document: QueryDocumentSnapshot) -> CommunityComment? {
        let data = document.data()

        guard let communityId = data["communityId"] as? String,
              let postId = data["postId"] as? String,
              let authorId = data["authorId"] as? String,
              let text = data["text"] as? String else {
            return nil
        }

        let authorName = data["authorName"] as? String ?? "User"
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

        return CommunityComment(
            id: document.documentID,
            communityId: communityId,
            postId: postId,
            authorId: authorId,
            authorName: authorName,
            text: text,
            createdAt: createdAt
        )
    }

    private func resolveAuthorName(for user: User, completion: @escaping (String) -> Void) {
        db.collection("users")
            .document(user.uid)
            .getDocument { snapshot, _ in
                let data = snapshot?.data() ?? [:]
                let authorName = (data["name"] as? String)
                    ?? user.displayName
                    ?? user.email
                    ?? "User"
                completion(authorName)
            }
    }

    private func friendlyErrorMessage(for error: Error, action: String) -> String {
        let nsError = error as NSError

        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You do not have permission to \(action)."
        }

        return "Failed to \(action)."
    }
}

struct CommunityWrapperView: View {
    var body: some View {
        NavigationView {
            CommunityListView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct CommunityListView: View {
    @StateObject private var communityViewModel = CommunityViewModel()

    var body: some View {
        Group {
            if communityViewModel.isLoading && communityViewModel.communities.isEmpty {
                ProgressView("Loading communities...")
            } else if communityViewModel.communities.isEmpty {
                Text("No communities available right now.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(communityViewModel.communities) { community in
                            NavigationLink(destination: CommunityDetailView(community: community)) {
                                CommunityListCardView(community: community)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Community")
        .onAppear {
            communityViewModel.startListening()
        }
        .overlay(alignment: .top) {
            if let error = communityViewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct CommunityListCardView: View {
    let community: CommunityTopic

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: community.symbol)
                .font(.title2)
                .foregroundColor(.indigo)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 6) {
                Text(community.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(community.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct CommunityDetailView: View {
    let community: CommunityTopic

    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var postViewModel = PostViewModel()

    @State private var showCreatePostSheet = false
    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Sort", selection: $postViewModel.sortOption) {
                    ForEach(CommunityPostSortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if postViewModel.isLoading && postViewModel.posts.isEmpty {
                    ProgressView("Loading posts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if postViewModel.sortedPosts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 42))
                            .foregroundColor(.secondary)
                        Text("No posts yet")
                            .font(.headline)
                        Text("Tap + to create the first post in this community.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(postViewModel.sortedPosts) { post in
                                CommunityPostCardView(
                                    community: community,
                                    post: post,
                                    isLiked: post.likedBy.contains(authViewModel.user?.uid ?? ""),
                                    isVoting: postViewModel.pendingVotePostIds.contains(post.id),
                                    onVoteTap: {
                                        if authViewModel.isLoggedIn {
                                            postViewModel.toggleUpvote(for: post)
                                        } else {
                                            showLoginPrompt = true
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }

            Button {
                if authViewModel.isLoggedIn {
                    showCreatePostSheet = true
                } else {
                    showLoginPrompt = true
                }
            } label: {
                Image(systemName: authViewModel.isLoggedIn ? "plus" : "lock.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(18)
                    .background(Color.indigo)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 4)
            }
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        }
        .navigationTitle(community.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            postViewModel.startListening(for: community)
        }
        .onDisappear {
            postViewModel.stopListening(clearState: false)
        }
        .overlay(alignment: .top) {
            if let error = postViewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showCreatePostSheet) {
            CommunityCreatePostView(postViewModel: postViewModel, community: community)
        }
        .alert("Login to access this feature", isPresented: $showLoginPrompt) {
            Button("Not Now", role: .cancel) { }
            Button("Login") {
                showLoginSheet = true
            }
        } message: {
            Text("Login to create posts or vote.")
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
    }
}

private struct CommunityPostCardView: View {
    let community: CommunityTopic
    let post: CommunityPost
    let isLiked: Bool
    let isVoting: Bool
    let onVoteTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(destination: CommunityPostDetailView(community: community, post: post)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(post.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Text(post.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(PlainButtonStyle())

            HStack(spacing: 12) {
                Text("u/\(post.authorName)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(relativeTimeString(for: post.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Label("\(post.commentCount)", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button(action: onVoteTap) {
                    HStack(spacing: 4) {
                        if isVoting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: isLiked ? "arrow.up.circle.fill" : "arrow.up.circle")
                        }
                        Text("\(post.likeCount)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(isLiked ? .indigo : .secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                NavigationLink(destination: CommunityPostDetailView(community: community, post: post)) {
                    Text("View Discussion")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CommunityCreatePostView: View {
    @ObservedObject var postViewModel: PostViewModel
    let community: CommunityTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Title")) {
                    TextField("Post title", text: $postViewModel.draftPostTitle)
                }

                Section(header: Text("Description")) {
                    TextEditor(text: $postViewModel.draftPostDescription)
                        .frame(minHeight: 150)
                }

                if let error = postViewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(postViewModel.isCreatingPost ? "Posting..." : "Post") {
                        postViewModel.createPost(in: community) {
                            dismiss()
                        }
                    }
                    .disabled(!postViewModel.canCreatePost)
                }
            }
        }
    }
}

struct CommunityPostDetailView: View {
    let community: CommunityTopic
    let post: CommunityPost

    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var commentViewModel = CommentViewModel()
    @State private var showLoginSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(post.title)
                    .font(.title3)
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    Text("u/\(post.authorName)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(relativeTimeString(for: post.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(post.likeCount)", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(post.description)
                    .font(.body)

                Divider()

                Label("Comments", systemImage: "text.bubble")
                    .font(.headline)

                if commentViewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading comments...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                } else if commentViewModel.comments.isEmpty {
                    Text("No comments yet. Start the conversation.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(commentViewModel.comments) { comment in
                            CommunityCommentRowView(comment: comment)
                        }
                    }
                }

                if let error = commentViewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                }
            }
            .padding()
        }
        .navigationTitle(community.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if authViewModel.isLoggedIn {
                    HStack(spacing: 10) {
                        TextField("Add a comment...", text: $commentViewModel.draftCommentText)
                            .textFieldStyle(.roundedBorder)

                        Button(commentViewModel.isPosting ? "Posting..." : "Post") {
                            commentViewModel.postComment()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(.white)
                        .background(commentViewModel.canPost ? Color.indigo : Color.gray)
                        .cornerRadius(10)
                        .disabled(!commentViewModel.canPost)
                    }
                } else {
                    Button {
                        showLoginSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Login to comment")
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
        .onAppear {
            commentViewModel.startListening(communityId: community.id, postId: post.id)
        }
        .onDisappear {
            commentViewModel.stopListening(clearState: false)
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CommunityCommentRowView: View {
    let comment: CommunityComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(comment.authorName)
                    .font(.subheadline.weight(.semibold))

                Text(relativeTimeString(for: comment.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(comment.text)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Wrapper for Friends to provide a dedicated social discovery flow.
struct FriendsHubWrapperView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var friendsViewModel = FriendsViewModel()
    @State private var showLoginSheet = false

    var body: some View {
        NavigationView {
            if authViewModel.isLoggedIn {
                FriendsHubView(viewModel: friendsViewModel)
                    .navigationTitle("Friends")
            } else {
                LoginRequiredView(
                    title: "Connect With Readers",
                    message: "Sign in to discover people with matching interests, shared activity, and mutual connections."
                ) {
                    showLoginSheet = true
                }
                .padding(.horizontal, 20)
                .navigationTitle("Friends")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
        .onAppear {
            if authViewModel.isLoggedIn {
                friendsViewModel.startListening()
            } else {
                friendsViewModel.stopListening()
            }
        }
        .onChange(of: authViewModel.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                friendsViewModel.startListening()
            } else {
                friendsViewModel.stopListening()
            }
        }
    }
}

struct FriendsHubView: View {
    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                discoverySearchBar

                if viewModel.isLoadingDiscovery && viewModel.allDiscoveredUsers.isEmpty {
                    ProgressView("Finding people...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }

                if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                    statusBanner(
                        text: errorMessage,
                        icon: "exclamationmark.triangle.fill",
                        color: .red
                    )
                }

                if let successMessage = viewModel.successMessage, !successMessage.isEmpty {
                    statusBanner(
                        text: successMessage,
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                }

                SocialUsersSection(
                    title: "Suggested for You",
                    subtitle: "Ranked by common interests, content behavior, mutuals, and activity.",
                    icon: "sparkles",
                    users: viewModel.suggestedForYouUsers,
                    emptyMessage: "No strong matches yet. Engage with articles to sharpen recommendations.",
                    viewModel: viewModel
                )

                SocialUsersSection(
                    title: "People You May Know",
                    subtitle: "Users connected through mutual friends.",
                    icon: "person.3.fill",
                    users: viewModel.peopleYouMayKnowUsers,
                    emptyMessage: "No mutual connections found yet.",
                    viewModel: viewModel
                )

                SocialUsersSection(
                    title: "All Users",
                    subtitle: "Every discoverable user except your own account.",
                    icon: "globe",
                    users: viewModel.filteredAllUsers,
                    emptyMessage: "No users match your search.",
                    viewModel: viewModel
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            viewModel.startListening()
        }
    }

    private var discoverySearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search users by name, email, or interest", text: $viewModel.searchText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: viewModel.searchText) { value in
                    viewModel.updateDiscoverySearch(value)
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.updateDiscoverySearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusBanner(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SocialUsersSection: View {
    let title: String
    let subtitle: String
    let icon: String
    let users: [AppUser]
    let emptyMessage: String

    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)

            if users.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(users) { user in
                        SocialUserRow(user: user, viewModel: viewModel)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SocialUserRow: View {
    let user: AppUser
    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(destination: SocialFriendProfileView(userId: user.id, viewModel: viewModel)) {
                HStack(alignment: .top, spacing: 10) {
                    UserAvatarView(imageURL: user.profileImageURL, size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)

                        if !user.email.isEmpty {
                            Text(user.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if user.mutualFriendsCount > 0 {
                            Text("\(user.mutualFriendsCount) mutual friends")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.blue)
                        }

                        if !user.interests.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(user.interests.prefix(3)), id: \.self) { interest in
                                        Text(interest)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer(minLength: 8)

            FriendActionButton(
                state: viewModel.friendActionState(for: user),
                isProcessing: viewModel.processingUserIds.contains(user.id)
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.sendFriendRequest(to: user)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct FriendActionButton: View {
    let state: FriendActionState
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                } else {
                    Text(title)
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(backgroundColor)
            .clipShape(Capsule())
        }
        .disabled(!isEnabled || isProcessing)
    }

    private var title: String {
        switch state {
        case .addFriend:
            return "Add"
        case .requested:
            return "Requested"
        case .friends:
            return "Friends"
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .addFriend:
            return .white
        case .requested:
            return .secondary
        case .friends:
            return .green
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .addFriend:
            return .blue
        case .requested:
            return Color(.systemGray5)
        case .friends:
            return .green.opacity(0.15)
        }
    }

    private var isEnabled: Bool {
        if case .addFriend = state {
            return true
        }
        return false
    }
}

struct SocialFriendProfileView: View {
    let userId: String
    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        Group {
            if let user = viewModel.enrichedUser(for: userId) {
                ScrollView {
                    VStack(spacing: 16) {
                        UserAvatarView(imageURL: user.profileImageURL, size: 94)

                        Text(user.name)
                            .font(.title3.weight(.bold))

                        if !user.email.isEmpty {
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if !user.interests.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Interests")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack {
                                    ForEach(Array(user.interests.prefix(5)), id: \.self) { interest in
                                        Text(interest)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        HStack(spacing: 10) {
                            SocialStatCard(title: "Likes", value: user.likesCount)
                            SocialStatCard(title: "Bookmarks", value: user.bookmarksCount)
                            SocialStatCard(title: "Reads", value: user.readsCount)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connection Insights")
                                .font(.headline)

                            Text("Mutual friends: \(user.mutualFriendsCount)")
                                .font(.subheadline)

                            Text(viewModel.recentActivityDescription(for: user))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        FriendActionButton(
                            state: viewModel.friendActionState(for: user),
                            isProcessing: viewModel.processingUserIds.contains(user.id)
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.sendFriendRequest(to: user)
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                ProgressView("Loading profile...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Friend Profile")
        .onAppear {
            viewModel.prefetchUserDetails(for: userId)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

struct SocialStatCard: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.headline)
                .foregroundColor(.primary)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AuthViewModel())
            .environmentObject(BookmarkManager())
            .environmentObject(UserActivityViewModel())
    }
}
