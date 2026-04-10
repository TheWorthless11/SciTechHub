# SciTechHub

SciTechHub is an iOS SwiftUI app for reading science and technology news, saving content, tracking activity, connecting with other users through social discovery, and sending lightweight direct messages.

## Current Status

Implemented so far:

- Firebase authentication (sign up, sign in, sign out)
- News feed for Science and Technology categories
- Home, Trending, Saved, Friends, and My Notes tabs
- Inbox tab for lightweight direct messages
- Article interactions: love and bookmark
- Reading history tracking
- Notes per user
- Profile editing (name, interests, profile image)
- Social discovery with recommendations and mutual connections
- Friend requests (top-level and mirrored per-user collections)
- Privacy/message permission model in Firestore rules
- On-demand AI article summary in article detail view
- Reddit-style async direct messaging (chat list + conversation view)
- Share article to friend from article detail as a direct message

## Tech Stack

- SwiftUI
- MVVM architecture
- Firebase iOS SDK (Auth, Firestore, Storage)
- NewsAPI for article data
- OpenAI Chat Completions API for article summarization

## Project Structure

- `SciTechHub/SciTechHubApp.swift`: App entry, Firebase initialization, global environment objects
- `SciTechHub/MainTabView.swift`: Main tab navigation and Friends hub UI
- `SciTechHub/HomeView.swift`: Home feed and recommendation logic
- `SciTechHub/TrendingView.swift`: Trending content view
- `SciTechHub/NewsView.swift`: News list and article detail UI
- `SciTechHub/NewsViewModel.swift`: News fetch logic
- `SciTechHub/ArticleSummaryViewModel.swift`: AI summary service + state management
- `SciTechHub/DirectMessagingView.swift`: Inbox UI, conversation UI, friend picker, `ChatViewModel`, `MessageViewModel`
- `SciTechHub/BookmarkManager.swift`: Bookmark/love persistence + listeners
- `SciTechHub/ProfileView.swift`: Profile, settings, and friend requests UI
- `SciTechHub/ProfileViewModel.swift`: Profile, privacy, social graph, and activity logic
- `SciTechHub/NotesView.swift`: User notes flow
- `firestore.rules`: Firestore security rules

## Requirements

- macOS with Xcode installed
- iOS Simulator or iOS device
- Firebase project configured

Recommended:

- Xcode 15+
- iOS 15+ target runtime

## Setup

1. Open the project:
   - Open `SciTechHub.xcodeproj` in Xcode.

2. Configure Firebase:
   - Add `GoogleService-Info.plist` to the app target.
   - Ensure Firebase is enabled for Authentication, Firestore, and Storage.

3. Configure API keys:
   - NewsAPI key is currently hardcoded in:
     - `SciTechHub/HomeView.swift`
     - `SciTechHub/NewsViewModel.swift`
   - OpenAI key is read in this order:
     - `OPENAI_API_KEY` in app Info.plist
     - `OPENAI_API_KEY` inside `GoogleService-Info.plist`
     - `OPENAI_API_KEY` from process environment

4. Deploy Firestore rules:
   - Use the `firestore.rules` file in the repo.
   - Deploy from Firebase Console or Firebase CLI using an account with permission to test/deploy Firestore rules.
   - Deploy after every messaging rule change (`/chats` + `/chats/{chatId}/messages` now required).

## Run the App

1. Select the `SciTechHub` scheme.
2. Choose an iOS Simulator (or connected device).
3. Build and run from Xcode.

## Firestore Notes

Important collections used by current implementation:

- `users/{userId}`
- `users/{userId}/notes/{noteId}`
- `users/{userId}/bookmarks/{bookmarkId}`
- `users/{userId}/likedArticles/{articleId}`
- `users/{userId}/readArticles/{articleId}`
- `users/{userId}/friends/{friendId}`
- `users/{userId}/friendRequests/{peerId}`
- `friendRequests/{requestId}`
- `friends/{userId}` (legacy compatibility)
- `chats/{chatId}`
- `chats/{chatId}/messages/{messageId}`

Chat document shape:

- `participants: [userId1, userId2]`
- `participantNames: { userId: displayName }`
- `participantPhotoURLs: { userId: photoURL }`
- `lastMessage: String`
- `lastTimestamp: Timestamp`

Message document shape:

- `senderId: String`
- `receiverId: String`
- `text: String`
- `timestamp: Timestamp`

## Troubleshooting

### "Missing or insufficient permissions" in Friends flow

If this appears while adding friends:

- Confirm latest `firestore.rules` is actually deployed to your Firebase project.
- Ensure top-level `friendRequests` read rule supports missing-document precheck reads (the rule containing `resource == null`).
- Ensure the Firebase account used for deployment has permission to test/deploy Firestore rules.

### AI summary not generating

- Verify `OPENAI_API_KEY` is set in one of the supported locations.
- Confirm network access and valid OpenAI billing/quota.

### Inbox shows permission errors

- Confirm latest `firestore.rules` is deployed.
- Ensure `/chats/{chatId}` and `/chats/{chatId}/messages/{messageId}` rules exist in the deployed version.
- Ensure users are actually friends if target user privacy is set to `messagePermission = friends`.

## Tests

Current test targets exist but are mostly starter templates:

- `SciTechHubTests`
- `SciTechHubUITests`

## Production Hardening Suggestions

Before production release:

- Move API keys out of source files and tracked plist files.
- Add focused unit tests for view models and friend request flows.
- Add Firestore emulator rule tests.
- Add centralized logging for network and Firestore permission errors.
