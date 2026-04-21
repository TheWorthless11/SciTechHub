import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

private struct PersistentTabBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 96

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @Namespace private var tabNamespace
    @State private var selectedTab: AppRootTab = .home
    // Reserve enough bottom space so content never falls under the persistent tab bar.
    @State private var persistentTabBarReservedHeight: CGFloat = 96
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            activeTabView
                .environment(\.tabBarOverlayHeight, persistentTabBarReservedHeight)
                .id(selectedTab)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: selectedTab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: persistentTabBarReservedHeight)
        }
        .overlay(alignment: .bottom) {
            AnimatedTabBar(selectedTab: $selectedTab, namespace: tabNamespace)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .background(AppTheme.background.opacity(0.78))
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: PersistentTabBarHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
        }
        .onPreferenceChange(PersistentTabBarHeightPreferenceKey.self) { measuredHeight in
            let resolvedHeight = max(88, measuredHeight)
            if abs(resolvedHeight - persistentTabBarReservedHeight) > 0.5 {
                persistentTabBarReservedHeight = resolvedHeight
            }
        }
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

    @ViewBuilder
    private var activeTabView: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .trending:
            TrendingView()
        case .saved:
            BookmarkWrapperView()
        case .community:
            CommunityWrapperView()
        case .more:
            MoreHubWrapperView()
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

// Wrapper for Research papers to keep tab navigation isolated
struct ResearchWrapperView: View {
    var useNavigationContainer: Bool = true

    var body: some View {
        Group {
            if useNavigationContainer {
                NavigationView {
                    ResearchView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else {
                ResearchView()
            }
        }
    }
}

struct MoreHubWrapperView: View {
    var body: some View {
        NavigationView {
            MoreHubView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct MoreHubView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                moreCard(
                    title: "Friends",
                    subtitle: "Discover and message people with shared interests.",
                    icon: "person.2.fill"
                ) {
                    FriendsHubWrapperView(useNavigationContainer: false)
                }

                moreCard(
                    title: "Inbox",
                    subtitle: "Open your direct messages and unread chats.",
                    icon: "bubble.left.and.bubble.right.fill"
                ) {
                    InboxWrapperView(useNavigationContainer: false)
                }

                moreCard(
                    title: "My Notes",
                    subtitle: "Read and manage your private article notes.",
                    icon: "note.text"
                ) {
                    NotesView()
                }

                moreCard(
                    title: "Live",
                    subtitle: "Join the current live video and discussions.",
                    icon: "dot.radiowaves.left.and.right"
                ) {
                    LiveNowWrapperView(useNavigationContainer: false)
                }

                moreCard(
                    title: "Scan",
                    subtitle: "Scan documents or posters for quick extraction.",
                    icon: "doc.text.viewfinder"
                ) {
                    ScanWrapperView(useNavigationContainer: false)
                }

                moreCard(
                    title: "Research",
                    subtitle: "Explore recent papers with smart recommendations.",
                    icon: "doc.text.magnifyingglass"
                ) {
                    ResearchWrapperView(useNavigationContainer: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .tabBarOverlayBottomPadding()
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("More")
    }

    private func moreCard<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.accentGradient)
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(AppTheme.titleText)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(AppTheme.subtitleText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppTheme.subtitleText)
            }
            .padding(14)
            .glassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
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

    private static let fallbackCommunities: [CommunityTopic] = [
        CommunityTopic(
            id: "community_ai",
            name: "AI",
            description: "Discuss machine learning, generative models, and practical AI experiments.",
            symbol: "brain.head.profile"
        ),
        CommunityTopic(
            id: "community_robotics",
            name: "Robotics",
            description: "Talk about autonomous systems, control, sensors, and real-world robotics builds.",
            symbol: "gearshape.2.fill"
        ),
        CommunityTopic(
            id: "community_climate",
            name: "Climate",
            description: "Share climate research, sustainability projects, and environmental technology ideas.",
            symbol: "leaf.fill"
        ),
        CommunityTopic(
            id: "community_space",
            name: "Space",
            description: "Explore astronomy, missions, propulsion, and the future of space engineering.",
            symbol: "sparkles"
        ),
        CommunityTopic(
            id: "community_health",
            name: "Health",
            description: "Discuss biomedical innovation, diagnostics, digital health, and public health research.",
            symbol: "cross.case.fill"
        )
    ]

    deinit {
        communitiesListener?.remove()
    }

    func startListening() {
        if communitiesListener != nil {
            return
        }

        isLoading = true
        errorMessage = nil

        communitiesListener = db.collection("communities")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "load communities")
                        if self.communities.isEmpty {
                            self.communities = Self.fallbackCommunities
                        }
                        self.isLoading = false
                        return
                    }

                    let docs = snapshot?.documents ?? []
                    let remoteCommunities = docs.compactMap { document in
                        self.community(from: document)
                    }

                    // Keep Community discoverable even when backend seed data is missing.
                    self.communities = remoteCommunities.isEmpty ? Self.fallbackCommunities : remoteCommunities
                    self.errorMessage = nil
                    self.isLoading = false
                }
            }
    }

    func stopListening(clearState: Bool = false) {
        communitiesListener?.remove()
        communitiesListener = nil

        if clearState {
            communities = []
            isLoading = false
            errorMessage = nil
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
    @Published private(set) var pendingDeleteCommentIds: Set<String> = []
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

                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        self.comments = (snapshot?.documents ?? []).compactMap { document in
                            self.comment(from: document)
                        }
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
            pendingDeleteCommentIds = []
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

    func deleteComment(_ comment: CommunityComment) {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Login required to manage comments."
            return
        }

        guard comment.authorId == user.uid else {
            errorMessage = "You can only delete your own comments."
            return
        }

        guard let communityId = activeCommunityId,
              let postId = activePostId else {
            errorMessage = "Unable to resolve comment target."
            return
        }

        if pendingDeleteCommentIds.contains(comment.id) {
            return
        }

        pendingDeleteCommentIds.insert(comment.id)
        errorMessage = nil

        commentsCollection(communityId: communityId, postId: postId)
            .document(comment.id)
            .delete { error in
                DispatchQueue.main.async {
                    self.pendingDeleteCommentIds.remove(comment.id)

                    if let error = error {
                        self.errorMessage = self.friendlyErrorMessage(for: error, action: "delete comment")
                        return
                    }

                    self.postsCollection(for: communityId)
                        .document(postId)
                        .updateData(["commentCount": FieldValue.increment(Int64(-1))])

                    self.errorMessage = nil
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
    @State private var selectedCommunityId: String?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            Group {
                if communityViewModel.isLoading && communityViewModel.communities.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(0..<3, id: \.self) { _ in
                                CommunityCardSkeletonView()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .tabBarOverlayBottomPadding()
                    }
                } else if communityViewModel.communities.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(AppTheme.accentPrimary)

                        Text("No communities available")
                            .font(.headline)
                            .foregroundColor(AppTheme.titleText)

                        Text("Please check again shortly.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.subtitleText)
                    }
                    .padding(20)
                    .glassCard(cornerRadius: 22)
                    .padding(.horizontal, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(Array(communityViewModel.communities.enumerated()), id: \.element.id) { index, community in
                                NavigationLink(destination: CommunityDetailView(community: community)) {
                                    CommunityCardView(
                                        community: community,
                                        isSelected: selectedCommunityId == community.id,
                                        appearDelay: Double(index) * 0.055
                                    )
                                }
                                .buttonStyle(TopicCardButtonStyle())
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        HapticFeedback.tap(.light)
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                            selectedCommunityId = community.id
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .tabBarOverlayBottomPadding()
                    }
                    .coordinateSpace(name: "communityScroll")
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
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
                    .cornerRadius(10)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
        }
    }
}

struct CommunityCardView: View {
    let community: CommunityTopic
    var isSelected: Bool = false
    var appearDelay: Double = 0

    @State private var didAppear = false

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named("communityScroll")).minY
            let parallax = max(-8, min(8, -minY * 0.03))

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.35), Color.blue.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: community.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.titleText)
                }
                .frame(width: 54, height: 54)
                .shadow(color: AppTheme.accentPrimary.opacity(0.24), radius: 12, x: 0, y: 0)

                VStack(alignment: .leading, spacing: 7) {
                    Text(community.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.titleText)

                    Text(community.description)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtitleText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.subtitleText)
                    .padding(.top, 3)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.accentPrimary.opacity(0.38), lineWidth: 1.2)
                        .shadow(color: AppTheme.accentPrimary.opacity(0.35), radius: 14, x: 0, y: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.11), radius: 14, x: 0, y: 10)
            .offset(y: parallax)
            .opacity(didAppear ? 1 : 0)
            .offset(y: didAppear ? 0 : 12)
            .animation(.easeOut(duration: 0.35).delay(appearDelay), value: didAppear)
            .animation(.easeInOut(duration: 0.22), value: isSelected)
            .onAppear {
                if !didAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + appearDelay) {
                        didAppear = true
                    }
                }
            }
        }
        .frame(height: 124)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color("Card").opacity(0.38))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.26), Color.black.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accentPrimary.opacity(0.18), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 12)
                .padding(8)
        }
    }
}

private struct CommunityCardSkeletonView: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(AppTheme.cardBackground.opacity(0.55))
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.55))
                    .frame(height: 18)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.45))
                    .frame(height: 15)
            }

            Spacer()
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
        .shimmering()
    }
}

struct CommunityDetailView: View {
    let community: CommunityTopic

    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var postViewModel = PostViewModel()
    @Namespace private var sortNamespace

    @State private var showCreatePostSheet = false
    @State private var showLoginPrompt = false
    @State private var showLoginSheet = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                AnimatedSegmentControl(selection: $postViewModel.sortOption, namespace: sortNamespace)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Rectangle()
                    .fill(AppTheme.cardBorder.opacity(0.35))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                discussionContent
            }
        }
        .navigationTitle(community.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticFeedback.tap(.medium)
                    if authViewModel.isLoggedIn {
                        showCreatePostSheet = true
                    } else {
                        showLoginPrompt = true
                    }
                } label: {
                    Image(systemName: authViewModel.isLoggedIn ? "plus.circle.fill" : "lock.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppTheme.accentPrimary)
                }
                .accessibilityLabel(authViewModel.isLoggedIn ? "Create post" : "Login to create post")
            }
        }
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
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.red.opacity(0.24), lineWidth: 1)
                    )
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

    @ViewBuilder
    private var discussionContent: some View {
        if postViewModel.isLoading && postViewModel.posts.isEmpty {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        PostCardSkeletonView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .tabBarOverlayBottomPadding()
            }
        } else if postViewModel.sortedPosts.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 42))
                    .foregroundColor(AppTheme.accentPrimary)
                Text("No posts yet")
                    .font(.headline)
                    .foregroundColor(AppTheme.titleText)
                Text("Tap + to create the first post in this community.")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.subtitleText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(postViewModel.sortedPosts) { post in
                        PostCardView(
                            community: community,
                            post: post,
                            isLiked: post.likedBy.contains(authViewModel.user?.uid ?? ""),
                            isVoting: postViewModel.pendingVotePostIds.contains(post.id),
                            onVoteTap: {
                                if authViewModel.isLoggedIn {
                                    HapticFeedback.tap(.light)
                                    postViewModel.toggleUpvote(for: post)
                                } else {
                                    showLoginPrompt = true
                                }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .tabBarOverlayBottomPadding()
            }
        }
    }
}

private struct PostCardView: View {
    let community: CommunityTopic
    let post: CommunityPost
    let isLiked: Bool
    let isVoting: Bool
    let onVoteTap: () -> Void

    @State private var didAppear = false
    @State private var cardTapPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: CommunityPostDetailView(community: community, post: post)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(post.title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(AppTheme.titleText)
                        .multilineTextAlignment(.leading)

                    Text(post.description)
                        .font(.subheadline)
                        .foregroundColor(AppTheme.subtitleText)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(PlainButtonStyle())

            HStack(spacing: 8) {
                metadataPill(icon: "person.fill", text: "u/\(post.authorName)")
                metadataPill(icon: "clock", text: relativeTimeString(for: post.createdAt))
                metadataPill(icon: "arrow.up", text: "\(post.likeCount)")
                metadataPill(icon: "bubble.left", text: "\(post.commentCount)")
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
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
                    .foregroundColor(isLiked ? AppTheme.accentPrimary : AppTheme.subtitleText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background((isLiked ? AppTheme.accentPrimary : AppTheme.cardBackground).opacity(0.13))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                NavigationLink(destination: CommunityPostDetailView(community: community, post: post)) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                        Text("View Discussion")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(AppTheme.accentGradient)
                    .clipShape(Capsule())
                }
                .buttonStyle(SpringyButtonStyle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        HapticFeedback.tap(.light)
                    }
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(postBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(cardTapPulse ? 0.16 : 0.1), radius: cardTapPulse ? 16 : 12, x: 0, y: cardTapPulse ? 10 : 8)
        .scaleEffect(cardTapPulse ? 0.985 : 1)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
        .animation(.easeOut(duration: 0.3), value: didAppear)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: cardTapPulse)
        .onTapGesture {
            HapticFeedback.tap(.light)
            cardTapPulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                cardTapPulse = false
            }
        }
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }

    private var postBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color("Card").opacity(0.36))

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
                        colors: [AppTheme.accentPrimary.opacity(0.16), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 12)
                .padding(8)
        }
    }

    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppTheme.subtitleText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.cardBackground.opacity(0.4))
        .clipShape(Capsule())
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct AnimatedSegmentControl: View {
    @Binding var selection: CommunityPostSortOption
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CommunityPostSortOption.allCases) { option in
                let isActive = selection == option

                Button {
                    HapticFeedback.tap(.light)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selection = option
                    }
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isActive ? .white : AppTheme.subtitleText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isActive {
                                Capsule()
                                    .fill(AppTheme.accentGradient)
                                    .matchedGeometryEffect(id: "community_sort_indicator", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Color("Card").opacity(0.4))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.09), radius: 10, x: 0, y: 5)
    }
}

private struct PostCardSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.58))
                .frame(height: 18)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.48))
                .frame(height: 14)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.45))
                    .frame(width: 90, height: 24)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.45))
                    .frame(width: 110, height: 24)

                Spacer()
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
        .shimmering()
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
    @State private var replyTargetName: String?
    @FocusState private var isCommentInputFocused: Bool

    var body: some View {
        ZStack {
            detailBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    PostHeaderView(post: post, accentColor: accentColor, cardColor: cardColor)
                        .padding(.top, 8)

                    commentsSectionHeader

                    if commentViewModel.isLoading {
                        VStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                CommentCardSkeletonView()
                            }
                        }
                    } else if commentViewModel.comments.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(accentColor)

                            Text("No comments yet")
                                .font(.headline)
                                .foregroundStyle(AppTheme.titleText)

                            Text("Be the first to start this discussion.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.subtitleText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .glassCard(cornerRadius: 20)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(commentViewModel.comments.enumerated()), id: \.element.id) { index, comment in
                                CommentCardView(
                                    comment: comment,
                                    accentColor: accentColor,
                                    cardColor: cardColor,
                                    canDelete: comment.authorId == authViewModel.user?.uid,
                                    isDeleting: commentViewModel.pendingDeleteCommentIds.contains(comment.id),
                                    appearDelay: Double(index) * 0.045,
                                    onReply: {
                                        reply(to: comment)
                                    },
                                    onDelete: {
                                        delete(comment)
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))

                                if index < commentViewModel.comments.count - 1 {
                                    Rectangle()
                                        .fill(AppTheme.cardBorder.opacity(0.28))
                                        .frame(height: 1)
                                        .padding(.horizontal, 8)
                                }
                            }
                        }
                        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: commentViewModel.comments.map(\.id))
                    }

                    if let error = commentViewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.red.opacity(0.24), lineWidth: 1)
                            )
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 16)
                .tabBarOverlayBottomPadding(extra: 84)
            }
        }
        .navigationTitle(community.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            CommentInputBar(
                isLoggedIn: authViewModel.isLoggedIn,
                draftText: $commentViewModel.draftCommentText,
                isPosting: commentViewModel.isPosting,
                canSend: commentViewModel.canPost,
                accentColor: accentColor,
                replyTargetName: replyTargetName,
                focused: $isCommentInputFocused,
                onClearReply: {
                    replyTargetName = nil
                    commentViewModel.draftCommentText = ""
                },
                onSend: {
                    HapticFeedback.tap(.medium)
                    commentViewModel.postComment()
                    replyTargetName = nil
                },
                onLoginTap: {
                    HapticFeedback.tap(.light)
                    showLoginSheet = true
                }
            )
            .tabBarOverlayBottomPadding(extra: 6)
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

    private var commentsSectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accentColor)

            Text("Comments")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.titleText)

            Spacer()

            Text("\(commentViewModel.comments.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var detailBackground: some View {
        ZStack {
            backgroundColor

            LinearGradient(
                colors: [backgroundColor, Color.black.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accentColor.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 38)
                .offset(x: 145, y: -180)

            Circle()
                .fill(accentColor.opacity(0.1))
                .frame(width: 180, height: 180)
                .blur(radius: 32)
                .offset(x: -140, y: 260)
        }
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

    private func reply(to comment: CommunityComment) {
        guard authViewModel.isLoggedIn else {
            showLoginSheet = true
            return
        }

        let firstName = comment.authorName
            .split(separator: " ")
            .first
            .map(String.init) ?? comment.authorName

        HapticFeedback.tap(.light)
        replyTargetName = firstName
        commentViewModel.draftCommentText = "@\(firstName) "
        isCommentInputFocused = true
    }

    private func delete(_ comment: CommunityComment) {
        guard authViewModel.isLoggedIn else {
            showLoginSheet = true
            return
        }

        HapticFeedback.tap(.medium)
        commentViewModel.deleteComment(comment)
    }
}

private struct PostHeaderView: View {
    let post: CommunityPost
    let accentColor: Color
    let cardColor: Color

    @State private var didAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(post.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.titleText)

            HStack(spacing: 8) {
                metadataPill(icon: "person.fill", text: "u/\(post.authorName)")
                metadataPill(icon: "clock", text: relativeTimeString(for: post.createdAt))
                metadataPill(icon: "arrow.up", text: "\(post.likeCount)")
            }

            Text(post.description)
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtitleText)
                .lineLimit(4)
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 8)
        .shadow(color: accentColor.opacity(0.16), radius: 12, x: 0, y: 0)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
        .animation(.easeOut(duration: 0.34), value: didAppear)
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }

    private var headerBackground: some View {
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

    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppTheme.subtitleText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.cardBackground.opacity(0.42))
        .clipShape(Capsule())
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CommentCardView: View {
    let comment: CommunityComment
    let accentColor: Color
    let cardColor: Color
    let canDelete: Bool
    let isDeleting: Bool
    let appearDelay: Double
    let onReply: () -> Void
    let onDelete: () -> Void

    @State private var didAppear = false
    @State private var isHighlighted = false
    @State private var showActions = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(comment.authorName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.titleText)

                    Text(relativeTimeString(for: comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(AppTheme.subtitleText)

                    Spacer()
                }

                Text(comment.text)
                    .font(.body)
                    .foregroundStyle(AppTheme.subtitleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accentColor.opacity(isHighlighted ? 0.12 : 0))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 7)
        .shadow(color: accentColor.opacity(0.12), radius: 9, x: 0, y: 0)
        .opacity(isDeleting ? 0.5 : (didAppear ? 1 : 0))
        .offset(y: didAppear ? 0 : 10)
        .scaleEffect(isHighlighted ? 0.985 : 1)
        .animation(.easeOut(duration: 0.3).delay(appearDelay), value: didAppear)
        .animation(.spring(response: 0.26, dampingFraction: 0.74), value: isHighlighted)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            HapticFeedback.tap(.light)
            isHighlighted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isHighlighted = false
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            HapticFeedback.tap(.medium)
            showActions = true
        }
        .confirmationDialog("Comment actions", isPresented: $showActions, titleVisibility: .visible) {
            Button("Reply") {
                onReply()
            }

            if canDelete {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            }

            Button("Cancel", role: .cancel) { }
        }
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.34), accentColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 0.9)

            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.titleText)
        }
        .frame(width: 36, height: 36)
        .shadow(color: accentColor.opacity(0.2), radius: 8, x: 0, y: 0)
    }

    private var initials: String {
        let parts = comment.authorName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }

        if parts.isEmpty {
            return "U"
        }
        return parts.joined()
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardColor.opacity(0.33))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CommentInputBar: View {
    let isLoggedIn: Bool
    @Binding var draftText: String
    let isPosting: Bool
    let canSend: Bool
    let accentColor: Color
    let replyTargetName: String?
    var focused: FocusState<Bool>.Binding
    let onClearReply: () -> Void
    let onSend: () -> Void
    let onLoginTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isLoggedIn, let replyTargetName {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption)
                        .foregroundStyle(accentColor)

                    Text("Replying to u/\(replyTargetName)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.subtitleText)

                    Spacer()

                    Button {
                        onClearReply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.subtitleText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }

            if isLoggedIn {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(AppTheme.subtitleText)

                        TextField("Write a comment...", text: $draftText)
                            .focused(focused)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button(action: onSend) {
                        Group {
                            if isPosting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(canSend ? AppTheme.accentGradient : LinearGradient(colors: [Color.gray, Color.gray.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                        .clipShape(Circle())
                        .shadow(color: canSend ? accentColor.opacity(0.32) : .clear, radius: 10, x: 0, y: 0)
                    }
                    .buttonStyle(SpringyButtonStyle())
                    .disabled(!canSend)
                }
            } else {
                Button(action: onLoginTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Login to comment")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundColor(.white)
                    .background(AppTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SpringyButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
        }
    }
}

private struct CommentCardSkeletonView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(AppTheme.cardBackground.opacity(0.55))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.56))
                    .frame(width: 130, height: 14)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.44))
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.4))
                    .frame(height: 14)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .shimmering()
    }
}

// Wrapper for Friends to provide a dedicated social discovery flow.
struct FriendsHubWrapperView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var friendsViewModel = FriendsViewModel()
    @State private var showLoginSheet = false
    var useNavigationContainer: Bool = true

    var body: some View {
        Group {
            if useNavigationContainer {
                NavigationView {
                    content
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else {
                content
            }
        }
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

    @ViewBuilder
    private var content: some View {
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
            .tabBarOverlayBottomPadding()
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

                        if viewModel.canMessage(user: user),
                           let chatPreview = chatPreview(for: user) {
                            NavigationLink(destination: MessageConversationView(chat: chatPreview)) {
                                Label("Message", systemImage: "paperplane.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .tabBarOverlayBottomPadding()
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

    private func chatPreview(for user: AppUser) -> DirectChatPreview? {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != user.id else {
            return nil
        }

        return DirectChatPreview(
            id: DirectMessageRepository.makeChatId(userA: currentUserId, userB: user.id),
            participants: [currentUserId, user.id].sorted(),
            otherUserId: user.id,
            otherUserName: user.name,
            otherUserPhotoURL: user.profileImageURL,
            lastMessage: "Start chatting",
            lastTimestamp: nil,
            unreadCount: 0
        )
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
