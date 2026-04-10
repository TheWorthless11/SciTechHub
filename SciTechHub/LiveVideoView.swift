import Foundation
import SwiftUI
import WebKit
import UIKit

// MARK: - Model
struct LiveVideoEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let isLive: Bool
    let embedURL: String
    let externalURL: String
    let thumbnailURL: String?
    let sortOrder: Int
}

// MARK: - ViewModel
@MainActor
final class LiveVideoViewModel: ObservableObject {
    @Published private(set) var events: [LiveVideoEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var embedRestrictedEventIDs: Set<String> = []
    @Published private(set) var restrictionToastMessage: String?

    private var loadTask: Task<Void, Never>?

    private struct LiveChannelTarget {
        let id: String
        let name: String
        let channelID: String
        let liveURLString: String
    }

    // Ordered priority for channels we consider trustworthy for real-time live news.
    private static let liveChannelTargets: [LiveChannelTarget] = [
        LiveChannelTarget(
            id: "reuters",
            name: "Reuters",
            channelID: "UChqUTb7kYRX8-EiaN3XFrSQ",
            liveURLString: "https://www.youtube.com/@Reuters/live"
        ),
        LiveChannelTarget(
            id: "ap",
            name: "Associated Press",
            channelID: "UC52X5wxOL_s5yw0dQk7NtgA",
            liveURLString: "https://www.youtube.com/@AP/live"
        ),
        LiveChannelTarget(
            id: "dwnews",
            name: "DW News",
            channelID: "UCknLrEdhRCp1aegoMqRaCZg",
            liveURLString: "https://www.youtube.com/@DWNews/live"
        ),
        LiveChannelTarget(
            id: "france24",
            name: "FRANCE 24 English",
            channelID: "UCQfwfsi5VrQ8yKZ-UWmAEFg",
            liveURLString: "https://www.youtube.com/@FRANCE24/live"
        ),
        LiveChannelTarget(
            id: "skynews",
            name: "Sky News",
            channelID: "UCoMdktPbSTixAyNGwb-UYkQ",
            liveURLString: "https://www.youtube.com/@SkyNews/live"
        ),
        LiveChannelTarget(
            id: "nasa",
            name: "NASA",
            channelID: "UCLA_DiR1FfKNvjuUpBHmylQ",
            liveURLString: "https://www.youtube.com/@NASA/live"
        )
    ]

    private static var youTubeDataAPIKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "YOUTUBE_DATA_API_KEY") as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "REPLACE_WITH_YOUR_KEY" {
            return nil
        }

        return trimmed
    }

    private struct YouTubeSearchResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let id: Identifier
            let snippet: Snippet

            struct Identifier: Decodable {
                let videoId: String?
            }

            struct Snippet: Decodable {
                let title: String
                let channelTitle: String
                let liveBroadcastContent: String?
                let thumbnails: Thumbnails?

                struct Thumbnails: Decodable {
                    let `default`: Thumbnail?
                    let medium: Thumbnail?
                    let high: Thumbnail?

                    var bestURL: String? {
                        high?.url ?? medium?.url ?? `default`?.url
                    }

                    struct Thumbnail: Decodable {
                        let url: String
                    }
                }
            }
        }
    }

    init() {
        loadEvents()
    }

    // Pull currently live streams from selected channels each time we refresh.
    func loadEvents() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            await self.refreshLiveEvents()
        }
    }

    func stopListening() {
        loadTask?.cancel()
        loadTask = nil
    }

    func markEmbeddingRestriction(for event: LiveVideoEvent) {
        let isNewRestriction = embedRestrictedEventIDs.insert(event.id).inserted
        if isNewRestriction {
            restrictionToastMessage = "\(event.title) may only open in YouTube."
        } else {
            restrictionToastMessage = "This video may only open in YouTube."
        }
    }

    func clearRestrictionToastMessage() {
        restrictionToastMessage = nil
    }

    var liveNowEvents: [LiveVideoEvent] {
        events.sorted { lhs, rhs in
            if lhs.isLive != rhs.isLive {
                return lhs.isLive && !rhs.isLive
            }

            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func refreshLiveEvents() async {
        if Task.isCancelled {
            return
        }

        isLoading = true
        errorMessage = nil

        let fetchedEvents: [LiveVideoEvent]
        if let apiKey = Self.youTubeDataAPIKey {
            fetchedEvents = await Self.fetchLiveEventsFromYouTubeAPI(apiKey: apiKey)
            if fetchedEvents.isEmpty {
                print("YouTube API returned no live streams. Falling back to public page parsing.")
                let fallbackEvents = await Self.fetchLiveEventsFromPublicPages()
                if fallbackEvents.isEmpty {
                    events = []
                    isLoading = false
                    errorMessage = "No real-time live news streams found right now."
                    return
                }

                events = fallbackEvents
                isLoading = false
                errorMessage = nil
                return
            }
        } else {
            fetchedEvents = await Self.fetchLiveEventsFromPublicPages()
            if fetchedEvents.isEmpty {
                isLoading = false
                events = []
                errorMessage = "Add YOUTUBE_DATA_API_KEY to load reliable real-time live videos."
                return
            }
        }

        if Task.isCancelled {
            return
        }

        isLoading = false
        events = fetchedEvents

        if fetchedEvents.isEmpty {
            errorMessage = "No real-time live news streams found right now."
            print("Live feed refresh completed with zero active streams.")
        } else {
            errorMessage = nil
            print("Live feed refresh loaded \(fetchedEvents.count) active streams.")
        }
    }

    private static func fetchLiveEventsFromYouTubeAPI(apiKey: String) async -> [LiveVideoEvent] {
        await withTaskGroup(of: LiveVideoEvent?.self) { group in
            for (index, target) in liveChannelTargets.enumerated() {
                group.addTask {
                    await fetchLiveEventFromYouTubeAPI(
                        for: target,
                        sortOrder: index + 1,
                        apiKey: apiKey
                    )
                }
            }

            var results: [LiveVideoEvent] = []
            for await event in group {
                if let event = event {
                    results.append(event)
                }
            }

            return results.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    private static func fetchLiveEventFromYouTubeAPI(
        for target: LiveChannelTarget,
        sortOrder: Int,
        apiKey: String
    ) async -> LiveVideoEvent? {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "channelId", value: target.channelID),
            URLQueryItem(name: "eventType", value: "live"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "1"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                let bodySnippet = String(data: data, encoding: .utf8) ?? ""
                print("YouTube API request failed for \(target.name) [\(httpResponse.statusCode)]: \(bodySnippet.prefix(180))")
                return nil
            }

            let decoded = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            guard let item = decoded.items.first,
                  let videoID = item.id.videoId else {
                return nil
            }

            let liveState = item.snippet.liveBroadcastContent?.lowercased() ?? ""
            guard liveState == "live" || liveState.isEmpty else {
                return nil
            }

            let title = decodeEscapedText(item.snippet.title)
            let channelTitle = decodeEscapedText(item.snippet.channelTitle)
            let resolvedTitle = title.isEmpty ? "\(channelTitle) Live" : title

            return LiveVideoEvent(
                id: "\(target.id)-\(videoID)",
                title: resolvedTitle,
                isLive: true,
                embedURL: "https://www.youtube.com/embed/\(videoID)",
                externalURL: "https://www.youtube.com/watch?v=\(videoID)",
                thumbnailURL: item.snippet.thumbnails?.bestURL,
                sortOrder: sortOrder
            )
        } catch {
            print("YouTube API decode/request failed for \(target.name): \(error.localizedDescription)")
            return nil
        }
    }

    private static func fetchLiveEventsFromPublicPages() async -> [LiveVideoEvent] {
        await withTaskGroup(of: LiveVideoEvent?.self) { group in
            for (index, target) in liveChannelTargets.enumerated() {
                group.addTask {
                    await fetchLiveEvent(for: target, sortOrder: index + 1)
                }
            }

            var results: [LiveVideoEvent] = []
            for await event in group {
                if let event = event {
                    results.append(event)
                }
            }

            return results.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    private static func fetchLiveEvent(for target: LiveChannelTarget, sortOrder: Int) async -> LiveVideoEvent? {
        guard let url = URL(string: target.liveURLString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8),
                  let parsedLiveVideo = parseLiveVideo(from: html) else {
                return nil
            }

            let videoID = parsedLiveVideo.videoID
            let resolvedTitle = parsedLiveVideo.title.isEmpty ? "\(target.name) Live" : parsedLiveVideo.title

            return LiveVideoEvent(
                id: "\(target.id)-\(videoID)",
                title: resolvedTitle,
                isLive: true,
                embedURL: "https://www.youtube.com/embed/\(videoID)",
                externalURL: "https://www.youtube.com/watch?v=\(videoID)",
                thumbnailURL: "https://i.ytimg.com/vi/\(videoID)/hqdefault_live.jpg",
                sortOrder: sortOrder
            )
        } catch {
            print("Failed loading channel \(target.name): \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseLiveVideo(from html: String) -> (videoID: String, title: String)? {
        guard let liveMarkerRange = html.range(of: "\"style\":\"LIVE\"") else {
            return nil
        }

        let markerIndex = html.distance(from: html.startIndex, to: liveMarkerRange.lowerBound)
        let startOffset = max(0, markerIndex - 12000)
        let endOffset = min(html.count, markerIndex + 3000)

        let startIndex = html.index(html.startIndex, offsetBy: startOffset)
        let endIndex = html.index(html.startIndex, offsetBy: endOffset)
        let window = String(html[startIndex..<endIndex])

        guard let videoID = firstRegexCapture(
            in: window,
            pattern: #""videoId":"([A-Za-z0-9_-]{11})""#
        ) else {
            return nil
        }

        let rawTitle = firstRegexCapture(
            in: window,
            pattern: #""title":\{"runs":\[\{"text":"([^"]+)""#
        ) ?? firstRegexCapture(
            in: window,
            pattern: #""title":\{"simpleText":"([^"]+)""#
        ) ?? "Live stream"

        let title = decodeEscapedText(rawTitle)
        return (videoID: videoID, title: title)
    }

    private static func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange])
    }

    private static func decodeEscapedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\n", with: " ")
    }
}

// MARK: - Wrapper
struct LiveNowWrapperView: View {
    var body: some View {
        Group {
            // NavigationStack is used when available. NavigationView fallback keeps iOS 15 support.
            if #available(iOS 16.0, *) {
                NavigationStack {
                    LiveNowView()
                }
            } else {
                NavigationView {
                    LiveNowView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
    }
}

// MARK: - Live List
struct LiveNowView: View {
    @StateObject private var viewModel = LiveVideoViewModel()
    @State private var showRestrictionToast = false
    @State private var restrictionToastText = ""
    private let autoRefreshTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.events.isEmpty {
                ProgressView("Loading live events...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.liveNowEvents.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.liveNowEvents) { event in
                            NavigationLink(destination: LiveVideoDetailView(event: event) {
                                viewModel.markEmbeddingRestriction(for: event)
                            }) {
                                LiveEventCardView(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Live Now")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadEvents()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .onReceive(autoRefreshTimer) { _ in
            viewModel.loadEvents()
        }
        .onChange(of: viewModel.restrictionToastMessage) { message in
            guard let message = message else {
                return
            }

            restrictionToastText = message
            withAnimation(.easeInOut(duration: 0.2)) {
                showRestrictionToast = true
            }

            let currentMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                guard restrictionToastText == currentMessage else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.2)) {
                    showRestrictionToast = false
                }
                viewModel.clearRestrictionToastMessage()
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }

                if showRestrictionToast {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                        Text(restrictionToastText)
                            .lineLimit(2)
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.14))
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.loadEvents()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh live videos")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)

            Text("No live streams right now")
                .font(.headline)

            Text("We only show active real-time streams. Tap refresh to check again.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Refresh now") {
                viewModel.loadEvents()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveEventCardView: View {
    let event: LiveVideoEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnailView
                .frame(width: 120, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    statusBadge
                    Text(event.isLive ? "Streaming now" : "Starts soon")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = event.thumbnailURL,
           let url = URL(string: thumbnailURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else if phase.error != nil {
                    thumbnailPlaceholder
                } else {
                    ZStack {
                        Color.gray.opacity(0.15)
                        ProgressView()
                    }
                }
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "video.fill")
                .font(.title3)
                .foregroundColor(.secondary)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(event.isLive ? Color.red : Color.orange)
                .frame(width: 8, height: 8)

            Text(event.isLive ? "LIVE" : "UPCOMING")
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(event.isLive ? .red : .orange)
        .background((event.isLive ? Color.red : Color.orange).opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Detail + Player
struct LiveVideoDetailView: View {
    let event: LiveVideoEvent
    var onEmbeddingRestrictionDetected: (() -> Void)?

    @State private var autoplayEnabled = true
    @State private var showFullscreenPlayer = false
    @State private var playerLoadFailed = false
    @State private var hasEmbeddingRestriction = false
    @State private var hasReportedEmbeddingRestriction = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    YouTubeWebView(
                        embedURLString: event.embedURL,
                        autoplay: autoplayEnabled,
                        hasLoadingError: $playerLoadFailed,
                        hasEmbeddingRestriction: $hasEmbeddingRestriction
                    )

                    if playerLoadFailed {
                        PlayerErrorPlaceholderView(
                            title: "Video unavailable",
                            subtitle: "Try opening this stream in your browser."
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    liveBadge
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        openInBrowser()
                    } label: {
                        Label("Open in YouTube", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showFullscreenPlayer = true
                    } label: {
                        Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                if hasEmbeddingRestriction {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)

                        Text("This video has in-app embed restrictions (Error 153). Please tap Open in YouTube.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Toggle("Auto-play on open", isOn: $autoplayEnabled)
                    .font(.subheadline)

                Text(event.title)
                    .font(.title3.weight(.bold))

                Text(event.isLive ? "This event is live now." : "This event is upcoming. The stream will start soon.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("Live Video")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showFullscreenPlayer) {
            LiveFullscreenPlayerView(event: event)
        }
        .onChange(of: hasEmbeddingRestriction) { isRestricted in
            guard isRestricted, !hasReportedEmbeddingRestriction else {
                return
            }

            hasReportedEmbeddingRestriction = true
            onEmbeddingRestrictionDetected?()
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: event.externalURL) else {
            print("Invalid external URL: \(event.externalURL)")
            return
        }

        UIApplication.shared.open(url, options: [:]) { success in
            print("Open in browser \(success ? "succeeded" : "failed"): \(url.absoluteString)")
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(event.isLive ? Color.red : Color.orange)
                .frame(width: 9, height: 9)

            Text(event.isLive ? "LIVE" : "UPCOMING")
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundColor(event.isLive ? .red : .orange)
        .background((event.isLive ? Color.red : Color.orange).opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct LiveFullscreenPlayerView: View {
    let event: LiveVideoEvent
    @Environment(\.dismiss) private var dismiss
    @State private var playerLoadFailed = false
    @State private var hasEmbeddingRestriction = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            YouTubeWebView(
                embedURLString: event.embedURL,
                autoplay: true,
                hasLoadingError: $playerLoadFailed,
                hasEmbeddingRestriction: $hasEmbeddingRestriction
            )
                .ignoresSafeArea()

            if playerLoadFailed {
                PlayerErrorPlaceholderView(
                    title: "Unable to play video",
                    subtitle: "Use Open in YouTube from the previous screen."
                )
                .padding(.horizontal, 20)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
    }
}

private struct PlayerErrorPlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.yellow)

            Text(title)
                .font(.headline)
                .foregroundColor(.white)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(Color.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Reusable WebView
struct YouTubeWebView: UIViewRepresentable {
    let embedURLString: String
    var autoplay: Bool
    @Binding var hasLoadingError: Bool
    @Binding var hasEmbeddingRestriction: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Keep YouTube embeds working like native social apps.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let targetURL = configuredEmbedURL else {
            DispatchQueue.main.async {
                hasLoadingError = true
                hasEmbeddingRestriction = false
            }
            print("Invalid embed URL: \(embedURLString)")
            return
        }

        // Prevent unnecessary reloads while SwiftUI updates the view hierarchy.
        if context.coordinator.lastLoadedURL != targetURL {
            context.coordinator.lastLoadedURL = targetURL
            print("Loading embed URL: \(targetURL.absoluteString)")
            webView.load(URLRequest(url: targetURL))
        }
    }

    private var configuredEmbedURL: URL? {
        guard var components = URLComponents(string: embedURLString) else {
            return nil
        }

        var items = components.queryItems ?? []

        func setItem(_ name: String, _ value: String) {
            if let index = items.firstIndex(where: { $0.name == name }) {
                items[index].value = value
            } else {
                items.append(URLQueryItem(name: name, value: value))
            }
        }

        setItem("playsinline", "1")
        setItem("rel", "0")
        setItem("modestbranding", "1")
        setItem("fs", "1")
        setItem("autoplay", autoplay ? "1" : "0")
        setItem("mute", autoplay ? "1" : "0")

        components.queryItems = items
        return components.url
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: YouTubeWebView
        var lastLoadedURL: URL?

        init(parent: YouTubeWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.hasLoadingError = false
                self.parent.hasEmbeddingRestriction = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
                let bodyText = (result as? String)?.lowercased() ?? ""
                let hasRestriction = bodyText.contains("error 153")
                    || bodyText.contains("video player configuration error")
                    || bodyText.contains("refused to connect")

                DispatchQueue.main.async {
                    self.parent.hasLoadingError = false
                    self.parent.hasEmbeddingRestriction = hasRestriction
                }

                if hasRestriction {
                    print("YouTube embed restriction detected (Error 153/configuration block).")
                }
            }

            print("YouTube player finished loading.")
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            DispatchQueue.main.async {
                self.parent.hasLoadingError = true
                self.parent.hasEmbeddingRestriction = false
            }
            print("YouTube player failed: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            DispatchQueue.main.async {
                self.parent.hasLoadingError = true
                self.parent.hasEmbeddingRestriction = false
            }
            print("YouTube provisional load failed: \(error.localizedDescription)")
        }
    }
}
