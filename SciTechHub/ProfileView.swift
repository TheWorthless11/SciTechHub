import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @StateObject private var friendsViewModel = FriendsViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var userActivityViewModel: UserActivityViewModel
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showLoginSheet = false
    @State private var showPhotoPicker = false
    @State private var selectedProfileImage: UIImage?
    
    var body: some View {
        Group {
            if !authViewModel.isLoggedIn {
                LoginRequiredView(
                    message: "Profile, account, and support actions require login."
                ) {
                    showLoginSheet = true
                }
            } else {
                List {
                    // Profile Header
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Button(action: {
                                    showPhotoPicker = true
                                }) {
                                    profileAvatarView
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if viewModel.isUploadingPhoto {
                                    ProgressView("Uploading photo...")
                                        .font(.caption)
                                } else {
                                    Text("Tap image to change photo")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(viewModel.userName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text(viewModel.userEmail)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }

                    if let error = viewModel.errorMessage {
                        Section {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }

                    if let success = viewModel.successMessage {
                        Section {
                            Text(success)
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                    }
                    
                    // Account Section
                    Section(header: Text("Account")) {
                        NavigationLink(destination: EditProfileView(viewModel: viewModel)) {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                        
                        NavigationLink(destination: ChangePasswordView()) {
                            Label("Change Password", systemImage: "lock.rotation")
                        }

                        NavigationLink(destination: MyActivityView()) {
                            Label("My Activity", systemImage: "chart.bar.fill")
                        }

                        NavigationLink(destination: SelectInterestsView(viewModel: viewModel)) {
                            Label("Interests", systemImage: "tag.fill")
                        }

                        NavigationLink(destination: FriendsSectionView(viewModel: friendsViewModel)) {
                            Label("Friends", systemImage: "person.2.fill")
                        }
                    }
                    
                    // Preferences Section
                    Section(header: Text("Preferences")) {
                        NavigationLink(destination: PrivacySettingsView()) {
                            Label("Privacy Settings", systemImage: "lock.shield")
                        }

                        Toggle(isOn: $isDarkMode) {
                            Label("Dark Mode", systemImage: isDarkMode ? "moon.fill" : "moon")
                        }
                    }
                    
                    // Support Section
                    Section(header: Text("Support")) {
                        NavigationLink(destination: FAQView()) {
                            Label("FAQ", systemImage: "questionmark.circle")
                        }
                        
                        NavigationLink(destination: ReportIssueView(viewModel: viewModel)) {
                            Label("Report Issue", systemImage: "exclamationmark.bubble")
                        }
                    }
                    
                    // Legal Section
                    Section(header: Text("Legal")) {
                        NavigationLink(destination: Text("Privacy Policy Details...")) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                    }
                    
                    // Logout Section
                    Section {
                        Button(action: {
                            authViewModel.signOut()
                        }) {
                            HStack {
                                Spacer()
                                Text("Logout")
                                    .foregroundColor(.red)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.fetchUserInfo()
            bookmarkManager.loadBookmarks()
            bookmarkManager.loadBookmarkedArticles()
            bookmarkManager.loadLikedArticles()
            userActivityViewModel.startListening()
            friendsViewModel.startListening()
        }
        .onChange(of: authViewModel.isLoggedIn) { isLoggedIn in
            if isLoggedIn {
                viewModel.fetchUserInfo()
                userActivityViewModel.startListening()
                friendsViewModel.startListening()
            } else {
                userActivityViewModel.stopListening()
                friendsViewModel.stopListening()
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView(showGuestDismiss: true)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showPhotoPicker) {
            ProfileImagePicker { image in
                selectedProfileImage = image
                viewModel.updateProfilePhoto(image: image)
            }
        }
    }

    @ViewBuilder
    private var profileAvatarView: some View {
        if let selectedProfileImage {
            Image(uiImage: selectedProfileImage)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 2))
        } else if let imageURL = URL(string: viewModel.profileImageURL), !viewModel.profileImageURL.isEmpty {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else if phase.error != nil {
                    defaultAvatar
                } else {
                    ProgressView()
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 2))
        } else {
            defaultAvatar
        }
    }

    private var defaultAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .foregroundColor(.blue.opacity(0.9))
    }
}

struct MyActivityView: View {
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @EnvironmentObject var userActivityViewModel: UserActivityViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NavigationLink(destination: LikedArticlesHistoryView()) {
                    ActivityMetricCard(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "Likes Count",
                        count: userActivityViewModel.likesCount,
                        isInteractive: true
                    )
                }
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: ReadingHistoryView()) {
                    ActivityMetricCard(
                        icon: "book.fill",
                        iconColor: .blue,
                        title: "Articles Read Count",
                        count: userActivityViewModel.readCount,
                        isInteractive: true
                    )
                }
                .buttonStyle(PlainButtonStyle())

                ActivityMetricCard(
                    icon: "bookmark.fill",
                    iconColor: .orange,
                    title: "Bookmarks Count",
                    count: bookmarkCount,
                    isInteractive: false
                )
            }
            .padding()
        }
        .navigationTitle("My Activity")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            bookmarkManager.loadBookmarks()
            bookmarkManager.loadBookmarkedArticles()
            userActivityViewModel.startListening()
        }
    }

    private var bookmarkCount: Int {
        bookmarkManager.bookmarks.count + bookmarkManager.bookmarkedArticles.count
    }
}

struct ActivityMetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int
    let isInteractive: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.bold)
            }

            Spacer()

            if isInteractive {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

struct LikedArticlesHistoryView: View {
    @EnvironmentObject var userActivityViewModel: UserActivityViewModel

    var body: some View {
        Group {
            if userActivityViewModel.isLoadingActivity && userActivityViewModel.likedHistory.isEmpty {
                ProgressView("Loading liked articles...")
            } else if userActivityViewModel.likedHistory.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(userActivityViewModel.likedHistory) { item in
                        NavigationLink(destination: NewsArticleDetailView(article: item.article)) {
                            ActivityArticleRow(article: item.article, source: item.source, timestamp: item.timestamp)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Liked Articles")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            userActivityViewModel.startListening()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No liked articles yet")
                .font(.headline)
            Text("Tap the heart icon on articles to see them here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct ReadingHistoryView: View {
    @EnvironmentObject var userActivityViewModel: UserActivityViewModel

    var body: some View {
        Group {
            if userActivityViewModel.isLoadingActivity && userActivityViewModel.readingHistory.isEmpty {
                ProgressView("Loading reading history...")
            } else if userActivityViewModel.readingHistory.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(userActivityViewModel.readingHistory) { item in
                        NavigationLink(destination: NewsArticleDetailView(article: item.article)) {
                            ActivityArticleRow(article: item.article, source: item.source, timestamp: item.timestamp)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Reading History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            userActivityViewModel.startListening()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No reading history yet")
                .font(.headline)
            Text("Open an article to automatically add it here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct ActivityArticleRow: View {
    let article: Article
    let source: String
    let timestamp: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageString = article.urlToImage,
               let imageURL = URL(string: imageString) {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 76, height: 76)
                            .clipped()
                    } else if phase.error != nil {
                        Color.gray.opacity(0.2)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                            .frame(width: 76, height: 76)
                    } else {
                        ProgressView()
                            .frame(width: 76, height: 76)
                    }
                }
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(source)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let timestamp {
                    Text(timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SelectInterestsView: View {
    @ObservedObject var viewModel: ProfileViewModel

    private let availableInterests = ["AI", "Space", "Technology", "Health", "Science"]
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select the topics you want to personalize your feed.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(availableInterests, id: \.self) { interest in
                        Button(action: {
                            viewModel.toggleInterest(interest)
                        }) {
                            Text(interest)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(viewModel.selectedInterests.contains(interest) ? .white : .blue)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(viewModel.selectedInterests.contains(interest) ? Color.blue : Color.blue.opacity(0.12))
                                .cornerRadius(18)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                if let success = viewModel.successMessage {
                    Text(success)
                        .font(.footnote)
                        .foregroundColor(.green)
                }

                Button(action: {
                    viewModel.saveInterests()
                }) {
                    HStack {
                        Spacer()
                        if viewModel.isSavingInterests {
                            ProgressView()
                        } else {
                            Text("Save Interests")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Select Interests")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.fetchUserInfo()
            viewModel.clearMessages()
        }
    }
}

struct PrivacySettingsView: View {
    @StateObject private var viewModel = PrivacyViewModel()

    var body: some View {
        Form {
            Section(
                header: Label("Profile Visibility", systemImage: "person.crop.circle.badge.checkmark"),
                footer: Text("Private profile means only your friends can see your activity")
            ) {
                // A single source-of-truth toggle for visibility keeps this beginner-friendly.
                Toggle(isOn: profileVisibilityBinding) {
                    Label("Public Profile", systemImage: "person.fill")
                }

                HStack {
                    Label("Private Profile", systemImage: "lock.fill")
                    Spacer()
                    Image(systemName: viewModel.isProfilePublic ? "circle" : "checkmark.circle.fill")
                        .foregroundColor(viewModel.isProfilePublic ? .secondary : .blue)
                }
            }

            Section(
                header: Label("Messaging", systemImage: "message.fill"),
                footer: Text(viewModel.messagePermission.helperText)
            ) {
                Text("Who can message me?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Who can message me?", selection: messagePermissionBinding) {
                    ForEach(MessagePermission.allCases) { permission in
                        Text(permission.displayTitle).tag(permission)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if viewModel.isLoadingSettings {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading privacy settings...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.isSavingSettings {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Saving changes...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                if let success = viewModel.successMessage {
                    Text(success)
                        .font(.footnote)
                        .foregroundColor(.green)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Privacy Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadSettings()
        }
    }

    private var profileVisibilityBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isProfilePublic },
            set: { viewModel.updateProfileVisibility(isPublic: $0) }
        )
    }

    private var messagePermissionBinding: Binding<MessagePermission> {
        Binding(
            get: { viewModel.messagePermission },
            set: { viewModel.updateMessagePermission($0) }
        )
    }
}

struct FriendsSectionView: View {
    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        List {
            NavigationLink(destination: FindFriendsView(viewModel: viewModel)) {
                Label("Find Friends", systemImage: "person.badge.plus")
            }

            NavigationLink(destination: FriendRequestsView(viewModel: viewModel)) {
                HStack {
                    Label("Friend Requests", systemImage: "tray.full")
                    Spacer()
                    let pendingCount = viewModel.incomingRequests.filter { $0.status == "pending" }.count
                    if pendingCount > 0 {
                        Text("\(pendingCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
            }

            NavigationLink(destination: MyFriendsView(viewModel: viewModel)) {
                Label("My Friends", systemImage: "person.2.fill")
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startListening()
        }
    }
}

struct FindFriendsView: View {
    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextField("Search by name or email", text: $viewModel.searchQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)

                Button(action: {
                    viewModel.searchUsers()
                }) {
                    Image(systemName: "magnifyingglass")
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            if let success = viewModel.successMessage {
                Text(success)
                    .font(.footnote)
                    .foregroundColor(.green)
                    .padding(.horizontal)
            }

            if viewModel.isLoadingSearch {
                Spacer()
                ProgressView("Searching users...")
                Spacer()
            } else if viewModel.searchResults.isEmpty {
                Spacer()
                Text("Search users to send friend requests.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(viewModel.searchResults) { user in
                        HStack(spacing: 12) {
                            UserAvatarView(imageURL: user.profileImageURL, size: 42)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.name)
                                    .font(.headline)

                                if viewModel.canViewProfile(of: user) {
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text(user.isProfilePublic ? "Public Profile" : "Private Profile")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text(viewModel.messagingPermissionText(for: user))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Label("Private Profile", systemImage: "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if viewModel.isFriend(userId: user.id) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Friends")
                                }
                                .font(.caption)
                                .foregroundColor(.green)
                            } else if viewModel.hasPendingRequest(with: user.id) {
                                Text("Pending")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(10)
                            } else {
                                Button(action: {
                                    viewModel.sendFriendRequest(to: user)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                        Text("Add")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Find Friends")
        .navigationBarTitleDisplayMode(.inline)
        .onSubmit {
            viewModel.searchUsers()
        }
        .onAppear {
            viewModel.clearMessages()
            viewModel.startListening()
        }
    }
}

struct FriendRequestsView: View {
    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        Group {
            let pendingRequests = viewModel.incomingRequests.filter { $0.status == "pending" }

            if viewModel.isLoadingRequests && pendingRequests.isEmpty {
                ProgressView("Loading requests...")
            } else if pendingRequests.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No pending requests")
                        .font(.headline)
                    Text("New friend requests will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(pendingRequests) { request in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                UserAvatarView(imageURL: request.senderPhotoURL, size: 46)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.senderName)
                                        .font(.headline)
                                    Text(request.senderEmail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("Pending")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(8)
                            }

                            HStack(spacing: 10) {
                                Button(action: {
                                    viewModel.accept(request: request)
                                }) {
                                    Label("Accept", systemImage: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }

                                Button(action: {
                                    viewModel.reject(request: request)
                                }) {
                                    Label("Reject", systemImage: "xmark")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Friend Requests")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.clearMessages()
            viewModel.startListening()
        }
    }
}

struct MyFriendsView: View {
    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingFriends && viewModel.friends.isEmpty {
                ProgressView("Loading friends...")
            } else if viewModel.friends.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No friends yet")
                        .font(.headline)
                    Text("Find and add friends to build your network.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(viewModel.friends) { friend in
                        NavigationLink(destination: FutureChatPlaceholderView(friend: friend, canMessage: viewModel.canMessage(user: friend))) {
                            HStack(spacing: 12) {
                                UserAvatarView(imageURL: friend.profileImageURL, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.name)
                                        .font(.headline)
                                    Text(friend.email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("My Friends")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startListening()
        }
    }
}

struct FutureChatPlaceholderView: View {
    let friend: AppUser
    let canMessage: Bool

    var body: some View {
        VStack(spacing: 16) {
            UserAvatarView(imageURL: friend.profileImageURL, size: 88)
            Text(friend.name)
                .font(.title3)
                .fontWeight(.bold)

            if canMessage {
                Text("Chat feature will be added in a future update.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("You cannot message this user based on their privacy settings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UserAvatarView: View {
    let imageURL: String
    let size: CGFloat

    var body: some View {
        if let url = URL(string: imageURL), !imageURL.isEmpty {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    fallbackAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackAvatar
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(.blue.opacity(0.75))
    }
}

struct ProfileImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ProfileImagePicker

        init(parent: ProfileImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self)
            else {
                return
            }

            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    if let selectedImage = image as? UIImage {
                        self.parent.onImagePicked(selectedImage)
                    }
                }
            }
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProfileView()
                .environmentObject(AuthViewModel())
                .environmentObject(BookmarkManager())
                .environmentObject(UserActivityViewModel())
        }
    }
}
