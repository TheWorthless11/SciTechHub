import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DirectMessageFriend: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String
    let profileImageURL: String
}

struct DirectChatPreview: Identifiable, Hashable {
    let id: String
    let participants: [String]
    let otherUserId: String
    let otherUserName: String
    let otherUserPhotoURL: String
    let lastMessage: String
    let lastTimestamp: Date?
}

struct DirectMessageItem: Identifiable, Hashable {
    let id: String
    let senderId: String
    let receiverId: String
    let text: String
    let timestamp: Date?
}

enum DirectMessageRepositoryError: LocalizedError {
    case notLoggedIn
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Login required to send messages."
        case .emptyMessage:
            return "Message cannot be empty."
        }
    }
}

enum DirectMessageRepository {
    static func makeChatId(userA: String, userB: String) -> String {
        [userA, userB].sorted().joined(separator: "__")
    }

    static func articleShareText(for article: Article) -> String {
        let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let articleURL = article.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !title.isEmpty && !articleURL.isEmpty {
            return "Shared article: \(title)\n\(articleURL)"
        }

        if !title.isEmpty {
            return "Shared article: \(title)"
        }

        if !articleURL.isEmpty {
            return "Shared article link: \(articleURL)"
        }

        return "Shared an article from SciTechHub."
    }

    static func loadChats(
        for currentUserId: String,
        using db: Firestore,
        completion: @escaping (Result<[DirectChatPreview], Error>) -> Void
    ) {
        db.collection("chats")
            .whereField("participants", arrayContains: currentUserId)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let chats: [DirectChatPreview] = (snapshot?.documents ?? []).compactMap { document in
                    let data = document.data()
                    guard let participants = data["participants"] as? [String],
                          participants.contains(currentUserId) else {
                        return nil
                    }

                    let otherUserId = participants.first(where: { $0 != currentUserId }) ?? currentUserId
                    let participantNames = data["participantNames"] as? [String: String] ?? [:]
                    let participantPhotoURLs = data["participantPhotoURLs"] as? [String: String] ?? [:]

                    let rawOtherName = participantNames[otherUserId] ?? "User"
                    let otherName = rawOtherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "User"
                        : rawOtherName

                    let lastMessageRaw = (data["lastMessage"] as? String) ?? ""
                    let lastMessage = lastMessageRaw.trimmingCharacters(in: .whitespacesAndNewlines)

                    return DirectChatPreview(
                        id: document.documentID,
                        participants: participants,
                        otherUserId: otherUserId,
                        otherUserName: otherName,
                        otherUserPhotoURL: participantPhotoURLs[otherUserId] ?? "",
                        lastMessage: lastMessage.isEmpty ? "Start chatting" : lastMessage,
                        lastTimestamp: (data["lastTimestamp"] as? Timestamp)?.dateValue()
                    )
                }

                let sorted = chats.sorted {
                    ($0.lastTimestamp ?? .distantPast) > ($1.lastTimestamp ?? .distantPast)
                }

                completion(.success(sorted))
            }
    }

    static func loadMessages(
        chatId: String,
        using db: Firestore,
        completion: @escaping (Result<[DirectMessageItem], Error>) -> Void
    ) {
        db.collection("chats")
            .document(chatId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                let messages: [DirectMessageItem] = (snapshot?.documents ?? []).compactMap { document in
                    let data = document.data()
                    guard let senderId = data["senderId"] as? String,
                          let text = data["text"] as? String else {
                        return nil
                    }

                    let receiverId = data["receiverId"] as? String ?? ""
                    let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalizedText.isEmpty else {
                        return nil
                    }

                    return DirectMessageItem(
                        id: document.documentID,
                        senderId: senderId,
                        receiverId: receiverId,
                        text: normalizedText,
                        timestamp: (data["timestamp"] as? Timestamp)?.dateValue()
                    )
                }

                completion(.success(messages))
            }
    }

    static func loadFriends(
        for currentUserId: String,
        using db: Firestore,
        completion: @escaping (Result<[DirectMessageFriend], Error>) -> Void
    ) {
        db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                var friends: [DirectMessageFriend] = (snapshot?.documents ?? []).compactMap { document in
                    let data = document.data()
                    let friendId = (data["friendId"] as? String) ?? document.documentID
                    let friendName = (data["friendName"] as? String) ?? "User"
                    let friendEmail = (data["friendEmail"] as? String) ?? ""
                    let friendPhoto = (data["friendPhotoURL"] as? String) ?? ""

                    guard !friendId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }

                    return DirectMessageFriend(
                        id: friendId,
                        name: friendName,
                        email: friendEmail,
                        profileImageURL: friendPhoto
                    )
                }

                friends.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

                completion(.success(friends))
            }
    }

    static func sendMessageFromCurrentUser(
        text: String,
        to receiver: DirectMessageFriend,
        using db: Firestore,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            completion(.failure(DirectMessageRepositoryError.emptyMessage))
            return
        }

        guard let currentUser = Auth.auth().currentUser else {
            completion(.failure(DirectMessageRepositoryError.notLoggedIn))
            return
        }

        let senderId = currentUser.uid
        let chatId = makeChatId(userA: senderId, userB: receiver.id)

        resolveCurrentUserProfile(userId: senderId, using: db) { profile in
            let senderName = profile.name
            let senderPhotoURL = profile.photoURL

            let chatRef = db.collection("chats").document(chatId)
            let messageRef = chatRef.collection("messages").document()

            let participants = [senderId, receiver.id].sorted()
            let participantNames: [String: String] = [
                senderId: senderName,
                receiver.id: receiver.name
            ]

            let participantPhotos: [String: String] = [
                senderId: senderPhotoURL,
                receiver.id: receiver.profileImageURL
            ]

            let batch = db.batch()

            batch.setData([
                "participants": participants,
                "participantNames": participantNames,
                "participantPhotoURLs": participantPhotos,
                "lastMessage": trimmedText,
                "lastTimestamp": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: chatRef, merge: true)

            batch.setData([
                "senderId": senderId,
                "receiverId": receiver.id,
                "text": trimmedText,
                "timestamp": FieldValue.serverTimestamp()
            ], forDocument: messageRef)

            batch.commit { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    private static func resolveCurrentUserProfile(
        userId: String,
        using db: Firestore,
        completion: @escaping ((name: String, photoURL: String)) -> Void
    ) {
        db.collection("users")
            .document(userId)
            .getDocument { snapshot, _ in
                let data = snapshot?.data() ?? [:]
                let fallbackName = Auth.auth().currentUser?.displayName ?? Auth.auth().currentUser?.email ?? "You"
                let name = (data["name"] as? String) ?? fallbackName
                let photoURL = (data["profileImageUrl"] as? String) ?? ""
                completion((name, photoURL))
            }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var chats: [DirectChatPreview] = []
    @Published private(set) var friends: [DirectMessageFriend] = []
    @Published private(set) var isLoadingChats = false
    @Published private(set) var isLoadingFriends = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let db = Firestore.firestore()

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    func loadChats() {
        guard let uid = currentUserId else {
            chats = []
            errorMessage = "Login required to view inbox."
            return
        }

        isLoadingChats = true
        errorMessage = nil

        DirectMessageRepository.loadChats(for: uid, using: db) { result in
            DispatchQueue.main.async {
                self.isLoadingChats = false
                switch result {
                case let .success(chats):
                    self.chats = chats
                case let .failure(error):
                    self.errorMessage = self.friendlyErrorMessage(for: error, action: "load inbox")
                }
            }
        }
    }

    func loadFriends() {
        guard let uid = currentUserId else {
            friends = []
            errorMessage = "Login required to load friends."
            return
        }

        isLoadingFriends = true
        errorMessage = nil

        DirectMessageRepository.loadFriends(for: uid, using: db) { result in
            DispatchQueue.main.async {
                self.isLoadingFriends = false
                switch result {
                case let .success(friends):
                    self.friends = friends
                case let .failure(error):
                    self.errorMessage = self.friendlyErrorMessage(for: error, action: "load friends")
                }
            }
        }
    }

    func sendArticle(_ article: Article, to friend: DirectMessageFriend, completion: @escaping (Bool) -> Void) {
        let articleText = DirectMessageRepository.articleShareText(for: article)
        sendMessage(articleText, to: friend) { success in
            completion(success)
        }
    }

    func sendMessage(_ text: String, to friend: DirectMessageFriend, completion: @escaping (Bool) -> Void) {
        isSending = true
        errorMessage = nil
        successMessage = nil

        DirectMessageRepository.sendMessageFromCurrentUser(text: text, to: friend, using: db) { result in
            DispatchQueue.main.async {
                self.isSending = false
                switch result {
                case .success:
                    self.successMessage = "Message sent."
                    self.loadChats()
                    completion(true)
                case let .failure(error):
                    self.errorMessage = self.friendlyErrorMessage(for: error, action: "send message")
                    completion(false)
                }
            }
        }
    }

    private func friendlyErrorMessage(for error: Error, action: String) -> String {
        if let message = (error as? LocalizedError)?.errorDescription {
            return message
        }

        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You do not have permission to \(action)."
        }

        return "Failed to \(action)."
    }
}

@MainActor
final class MessageViewModel: ObservableObject {
    @Published private(set) var messages: [DirectMessageItem] = []
    @Published var draftMessage = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private let chat: DirectChatPreview
    private let db = Firestore.firestore()

    init(chat: DirectChatPreview) {
        self.chat = chat
    }

    var canSend: Bool {
        !isSending && !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadMessages() {
        isLoading = true
        errorMessage = nil

        DirectMessageRepository.loadMessages(chatId: chat.id, using: db) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case let .success(messages):
                    self.messages = messages
                case let .failure(error):
                    self.errorMessage = self.friendlyErrorMessage(for: error, action: "load messages")
                }
            }
        }
    }

    func sendMessage() {
        guard canSend else {
            return
        }

        isSending = true
        errorMessage = nil

        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let friend = DirectMessageFriend(
            id: chat.otherUserId,
            name: chat.otherUserName,
            email: "",
            profileImageURL: chat.otherUserPhotoURL
        )

        DirectMessageRepository.sendMessageFromCurrentUser(text: text, to: friend, using: db) { result in
            DispatchQueue.main.async {
                self.isSending = false
                switch result {
                case .success:
                    self.draftMessage = ""
                    self.loadMessages()
                case let .failure(error):
                    self.errorMessage = self.friendlyErrorMessage(for: error, action: "send message")
                }
            }
        }
    }

    private func friendlyErrorMessage(for error: Error, action: String) -> String {
        if let message = (error as? LocalizedError)?.errorDescription {
            return message
        }

        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You do not have permission to \(action)."
        }

        return "Failed to \(action)."
    }
}

struct InboxWrapperView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showLoginSheet = false

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    content
                }
            } else {
                NavigationView {
                    content
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
    }

    @ViewBuilder
    private var content: some View {
        if authViewModel.isLoggedIn {
            InboxView()
                .navigationTitle("Inbox")
        } else {
            LoginRequiredView(
                title: "Messages Need Login",
                message: "Sign in to read conversations and share articles with friends."
            ) {
                showLoginSheet = true
            }
            .navigationTitle("Inbox")
        }
    }
}

struct InboxView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        Group {
            if viewModel.isLoadingChats && viewModel.chats.isEmpty {
                ProgressView("Loading inbox...")
            } else if viewModel.chats.isEmpty {
                emptyState
            } else {
                List(viewModel.chats) { chat in
                    NavigationLink(destination: MessageConversationView(chat: chat)) {
                        ChatInboxRow(chat: chat)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.loadChats()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh inbox")
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.top, 8)
            }
        }
        .onAppear {
            viewModel.loadChats()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(.secondary)

            Text("No conversations yet")
                .font(.headline)

            Text("Share an article with a friend to start chatting.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Refresh") {
                viewModel.loadChats()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct ChatInboxRow: View {
    let chat: DirectChatPreview

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.otherUserName)
                    .font(.headline)
                    .lineLimit(1)

                Text(chat.lastMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let timestamp = chat.lastTimestamp {
                Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = URL(string: chat.otherUserPhotoURL), !chat.otherUserPhotoURL.isEmpty {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackAvatar
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(.blue.opacity(0.85))
            .frame(width: 42, height: 42)
    }
}

struct MessageConversationView: View {
    let chat: DirectChatPreview
    @StateObject private var viewModel: MessageViewModel

    init(chat: DirectChatPreview) {
        self.chat = chat
        _viewModel = StateObject(wrappedValue: MessageViewModel(chat: chat))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                ProgressView("Loading messages...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.messages.isEmpty {
                emptyConversationState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleRow(
                                    message: message,
                                    isCurrentUser: message.senderId == Auth.auth().currentUser?.uid
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            composerBar
        }
        .navigationTitle(chat.otherUserName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.loadMessages()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh messages")
            }
        }
        .onAppear {
            viewModel.loadMessages()
        }
    }

    private var emptyConversationState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left")
                .font(.system(size: 34))
                .foregroundColor(.secondary)

            Text("No messages yet")
                .font(.headline)

            Text("Send a message to start this conversation.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var composerBar: some View {
        HStack(spacing: 10) {
            TextField("Write a message...", text: $viewModel.draftMessage)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                viewModel.sendMessage()
            } label: {
                if viewModel.isSending {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(width: 40, height: 40)
            .background(viewModel.canSend ? Color.blue : Color.gray)
            .clipShape(Circle())
            .disabled(!viewModel.canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let lastId = viewModel.messages.last?.id else {
            return
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

private struct MessageBubbleRow: View {
    let message: DirectMessageItem
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer(minLength: 36)
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(isCurrentUser ? Color.blue : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let timestamp = message.timestamp {
                    Text(timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if !isCurrentUser {
                Spacer(minLength: 36)
            }
        }
    }
}

struct ArticleShareSheet: View {
    let article: Article

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    content
                }
            } else {
                NavigationView {
                    content
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if viewModel.isLoadingFriends && viewModel.friends.isEmpty {
                ProgressView("Loading friends...")
            } else if viewModel.friends.isEmpty {
                emptyState
            } else {
                List(viewModel.friends) { friend in
                    ShareFriendRow(friend: friend, isSending: viewModel.isSending) {
                        viewModel.sendArticle(article, to: friend) { success in
                            if success {
                                dismiss()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Share Article")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.loadFriends()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh friends")
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }

                if let success = viewModel.successMessage {
                    Text(success)
                        .font(.footnote)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 8)
        }
        .onAppear {
            viewModel.loadFriends()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)

            Text("No friends found")
                .font(.headline)

            Text("Add friends first, then you can share articles directly as messages.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Refresh") {
                viewModel.loadFriends()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct ShareFriendRow: View {
    let friend: DirectMessageFriend
    let isSending: Bool
    let onShareTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.name)
                    .font(.headline)
                    .lineLimit(1)

                if !friend.email.isEmpty {
                    Text(friend.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: onShareTap) {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Label("Share", systemImage: "paperplane")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = URL(string: friend.profileImageURL), !friend.profileImageURL.isEmpty {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackAvatar
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)
            .foregroundColor(.blue.opacity(0.85))
    }
}
