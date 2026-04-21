import SwiftUI
import UIKit
@preconcurrency import Vision
import VisionKit
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

struct ScannedNote: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    let keywords: [String]
    let createdAt: Date
    let updatedAt: Date
}

enum ScanProcessingState: Equatable {
    case idle
    case ocr
    case summarizing
    case saving
    case searching
    case simplifying

    var statusMessage: String {
        switch self {
        case .idle:
            return ""
        case .ocr:
            return "Extracting text..."
        case .summarizing:
            return "Generating summary..."
        case .saving:
            return "Saving note..."
        case .searching:
            return "Searching related news..."
        case .simplifying:
            return "Simplifying content..."
        }
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var extractedText = ""
    @Published var summaryText: String?
    @Published var simplifiedText: String?
    @Published var extractedKeywords: [String] = []
    @Published var relatedArticles: [Article] = []
    @Published private(set) var savedScanNotes: [ScannedNote] = []
    @Published private(set) var processingState: ScanProcessingState = .idle
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let db = Firestore.firestore()
    private let session = URLSession.shared
    private let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private var notesListener: ListenerRegistration?
    private var listeningUserId: String?
    private var successWorkItem: DispatchWorkItem?

    private static var notesMemoryCache: [String: [ScannedNote]] = [:]

    private let guestNotesStorageKey = "guest_scanned_notes_v1"
    private let stopWords: Set<String> = [
        "about", "after", "again", "also", "among", "been", "being", "between",
        "could", "from", "have", "into", "just", "more", "most", "other", "over",
        "some", "than", "that", "their", "there", "these", "they", "this", "through",
        "very", "what", "when", "where", "which", "with", "will", "would", "your"
    ]

    var isProcessing: Bool {
        processingState != .idle
    }

    deinit {
        notesListener?.remove()
        successWorkItem?.cancel()
    }

    @discardableResult
    func processScannedPages(_ images: [UIImage]) async -> Bool {
        guard !images.isEmpty else {
            errorMessage = "No scanned pages found."
            return false
        }

        processingState = .ocr
        errorMessage = nil
        successMessage = nil

        do {
            var chunks: [String] = []
            for image in images {
                let text = try await recognizeText(in: image)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chunks.append(text)
                }
            }

            let combined = chunks.joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !combined.isEmpty else {
                processingState = .idle
                errorMessage = "No readable text found. Try a clearer capture."
                return false
            }

            extractedText = combined
            extractedKeywords = keywords(from: combined)
            summaryText = nil
            simplifiedText = nil
            relatedArticles = []
            errorMessage = nil
            processingState = .idle
            return true
        } catch {
            processingState = .idle
            errorMessage = "OCR failed. Please try again."
            return false
        }
    }

    @discardableResult
    func summarizeExtractedText() async -> Bool {
        guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Nothing to summarize. Scan text first."
            return false
        }

        processingState = .summarizing
        errorMessage = nil

        do {
            let clipped = clippedForAI(extractedText)
            let prompt = "Summarize this science/technology text in plain language for students. Keep it short and easy (3-5 bullet points)."
            let response = try await requestAI(prompt: prompt, text: clipped, maxTokens: 220)
            summaryText = response
            processingState = .idle
            return true
        } catch {
            processingState = .idle
            errorMessage = "Summary generation failed."
            return false
        }
    }

    @discardableResult
    func simplifyExtractedText() async -> Bool {
        guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Nothing to simplify. Scan text first."
            return false
        }

        processingState = .simplifying
        errorMessage = nil

        do {
            let clipped = clippedForAI(extractedText)
            let prompt = "Simplify this text for a beginner. First extract key ideas, then explain them in simple terms. Keep it concise and clear."
            let response = try await requestAI(prompt: prompt, text: clipped, maxTokens: 320)
            simplifiedText = response
            processingState = .idle
            return true
        } catch {
            processingState = .idle
            errorMessage = "Simplification failed."
            return false
        }
    }

    @discardableResult
    func searchRelatedNews() async -> Bool {
        guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Nothing to search. Scan text first."
            return false
        }

        processingState = .searching
        errorMessage = nil

        let keywords = self.keywords(from: extractedText)
        extractedKeywords = keywords

        guard !keywords.isEmpty else {
            processingState = .idle
            errorMessage = "Could not extract useful keywords from the text."
            return false
        }

        let query = keywords.prefix(4).joined(separator: " OR ")
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            processingState = .idle
            errorMessage = "Failed to prepare search query."
            return false
        }

        let urlString = "https://newsapi.org/v2/everything?q=\(encodedQuery)&sortBy=publishedAt&language=en&pageSize=20&apiKey=\(newsAPIKey)"
        guard let url = URL(string: urlString) else {
            processingState = .idle
            errorMessage = "Failed to build news request URL."
            return false
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                processingState = .idle
                errorMessage = "News search failed."
                return false
            }

            let decoded = try JSONDecoder().decode(NewsResponse.self, from: data)
            relatedArticles = decoded.articles
            processingState = .idle
            return true
        } catch {
            processingState = .idle
            errorMessage = "News search failed."
            return false
        }
    }

    @discardableResult
    func saveExtractedTextAsNote(currentUser: User?) async -> Bool {
        let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Nothing to save. Scan text first."
            return false
        }

        processingState = .saving
        errorMessage = nil

        let noteId = sha256Hex(trimmed)
        let keywords = extractedKeywords.isEmpty ? self.keywords(from: trimmed) : extractedKeywords

        if let user = currentUser {
            let now = Date()
            let existing = savedScanNotes.first(where: { $0.id == noteId })
            let createdAt = existing?.createdAt ?? now

            let payload: [String: Any] = [
                "ownerId": user.uid,
                "text": trimmed,
                "keywords": keywords,
                "createdAt": Timestamp(date: createdAt),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            do {
                try await writeFirestoreNote(userId: user.uid, noteId: noteId, payload: payload)

                let updatedNote = ScannedNote(
                    id: noteId,
                    text: trimmed,
                    keywords: keywords,
                    createdAt: createdAt,
                    updatedAt: now
                )
                upsertLocalNote(updatedNote, userId: user.uid)
                processingState = .idle
                showSuccess("Scan saved as note")
                return true
            } catch {
                processingState = .idle
                errorMessage = "Failed to save note."
                return false
            }
        }

        let now = Date()
        let existing = savedScanNotes.first(where: { $0.id == noteId })
        let localNote = ScannedNote(
            id: noteId,
            text: trimmed,
            keywords: keywords,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        upsertGuestNote(localNote)
        processingState = .idle
        showSuccess("Saved locally")
        return true
    }

    func loadSavedNotes(currentUser: User?) {
        if let user = currentUser {
            if listeningUserId == user.uid, notesListener != nil {
                return
            }

            notesListener?.remove()
            notesListener = nil
            listeningUserId = user.uid

            if let cached = Self.notesMemoryCache[user.uid] {
                savedScanNotes = cached
            }

            notesListener = db.collection("users")
                .document(user.uid)
                .collection("scanNotes")
                .order(by: "updatedAt", descending: true)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self = self else { return }

                    DispatchQueue.main.async {
                        if let error = error {
                            self.errorMessage = self.friendlyErrorMessage(for: error, action: "load saved scan notes")
                            return
                        }

                        let notes: [ScannedNote] = (snapshot?.documents ?? []).compactMap { document in
                            self.note(from: document)
                        }

                        Self.notesMemoryCache[user.uid] = notes
                        self.savedScanNotes = notes
                        self.errorMessage = nil
                    }
                }
            return
        }

        notesListener?.remove()
        notesListener = nil
        listeningUserId = nil
        savedScanNotes = loadGuestNotes()
    }

    func removeSavedNote(_ note: ScannedNote, currentUser: User?) {
        if let user = currentUser {
            db.collection("users")
                .document(user.uid)
                .collection("scanNotes")
                .document(note.id)
                .delete { [weak self] error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.errorMessage = self?.friendlyErrorMessage(for: error, action: "delete note")
                            return
                        }
                        self?.showSuccess("Note deleted")
                    }
                }
            return
        }

        var notes = loadGuestNotes()
        notes.removeAll { $0.id == note.id }
        saveGuestNotes(notes)
        savedScanNotes = notes
        showSuccess("Note deleted")
    }

    private func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "ScanViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid scanned image"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.015

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func requestAI(prompt: String, text: String, maxTokens: Int) async throws -> String {
        guard let key = openAIAPIKey, !key.isEmpty else {
            throw NSError(domain: "ScanViewModel", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API key"])
        }

        struct ChatRequest: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }

            let model: String
            let messages: [Message]
            let temperature: Double
            let maxTokens: Int

            enum CodingKeys: String, CodingKey {
                case model
                case messages
                case temperature
                case maxTokens = "max_tokens"
            }
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }

            let choices: [Choice]
        }

        let body = ChatRequest(
            model: "gpt-4o-mini",
            messages: [
                .init(role: "system", content: "You are a helpful science learning assistant. Keep explanations concise and student-friendly."),
                .init(role: "user", content: "\(prompt)\n\nText:\n\(text)")
            ],
            temperature: 0.3,
            maxTokens: maxTokens
        )

        var request = URLRequest(url: openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ScanViewModel", code: -3, userInfo: [NSLocalizedDescriptionKey: "AI request failed"])
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if content.isEmpty {
            throw NSError(domain: "ScanViewModel", code: -4, userInfo: [NSLocalizedDescriptionKey: "Empty AI response"])
        }

        return content
    }

    private func writeFirestoreNote(userId: String, noteId: String, payload: [String: Any]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("users")
                .document(userId)
                .collection("scanNotes")
                .document(noteId)
                .setData(payload, merge: true) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
        }
    }

    private func note(from document: QueryDocumentSnapshot) -> ScannedNote? {
        let data = document.data()
        let text = data["text"] as? String ?? ""
        let keywords = data["keywords"] as? [String] ?? []
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return ScannedNote(
            id: document.documentID,
            text: text,
            keywords: keywords,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func upsertLocalNote(_ note: ScannedNote, userId: String) {
        var notes = Self.notesMemoryCache[userId] ?? savedScanNotes
        notes.removeAll { $0.id == note.id }
        notes.insert(note, at: 0)
        notes.sort { $0.updatedAt > $1.updatedAt }
        Self.notesMemoryCache[userId] = notes
        savedScanNotes = notes
    }

    private func upsertGuestNote(_ note: ScannedNote) {
        var notes = loadGuestNotes()
        notes.removeAll { $0.id == note.id }
        notes.insert(note, at: 0)
        notes.sort { $0.updatedAt > $1.updatedAt }
        saveGuestNotes(notes)
        savedScanNotes = notes
    }

    private func loadGuestNotes() -> [ScannedNote] {
        guard let data = UserDefaults.standard.data(forKey: guestNotesStorageKey),
              let notes = try? JSONDecoder().decode([ScannedNote].self, from: data) else {
            return []
        }
        return notes
    }

    private func saveGuestNotes(_ notes: [ScannedNote]) {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: guestNotesStorageKey)
        }
    }

    private func clippedForAI(_ input: String, maxCharacters: Int = 5000) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxCharacters {
            return trimmed
        }
        return String(trimmed.prefix(maxCharacters))
    }

    private func keywords(from text: String) -> [String] {
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count > 2 && !stopWords.contains(token)
            }

        var counts: [String: Int] = [:]
        tokens.forEach { counts[$0, default: 0] += 1 }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map { $0.key }
            .prefix(8)
            .map { $0 }
    }

    private var newsAPIKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "NEWS_API_KEY") as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let key = plist["NEWS_API_KEY"] as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }

        return "635dcde799d14101b7b967df87c7106e"
    }

    private var openAIAPIKey: String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let key = plist["OPENAI_API_KEY"] as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }

        let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        if let envKey, !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envKey
        }

        return nil
    }

    private func sha256Hex(_ value: String) -> String {
        let data = Data(value.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func showSuccess(_ message: String) {
        successWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            successMessage = message
        }

        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self?.successMessage = nil
                }
            }
        }

        successWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
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

struct ScanWrapperView: View {
    var useNavigationContainer: Bool = true

    var body: some View {
        Group {
            if useNavigationContainer {
                NavigationView {
                    ScanHomeView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else {
                ScanHomeView()
            }
        }
    }
}

struct ScanHomeView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = ScanViewModel()

    @State private var showScanner = false
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 48))
                .foregroundColor(.indigo)

            Text("Scan & Smart AI Processing")
                .font(.title3)
                .fontWeight(.bold)

            Text("Capture printed or handwritten text, then choose what to do: summarize, save notes, search related news, or simplify content.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                showScanner = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera")
                    Text("Scan Text")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .foregroundColor(.white)
                .background(Color.indigo)
                .cornerRadius(12)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Spacer()

            NavigationLink(destination: ScanPreviewView(viewModel: viewModel).environmentObject(authViewModel), isActive: $showPreview) {
                EmptyView()
            }
            .hidden()
        }
        .padding(.top, 24)
        .navigationTitle("Scan")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SavedScansNotesView(viewModel: viewModel).environmentObject(authViewModel)) {
                    Image(systemName: "book")
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            DocumentTextScannerView { images in
                Task {
                    let success = await viewModel.processScannedPages(images)
                    if success {
                        showPreview = true
                    }
                }
            } onFailure: { errorText in
                viewModel.errorMessage = errorText
            }
        }
        .overlay {
            if viewModel.isProcessing {
                ScanProcessingOverlay(text: viewModel.processingState.statusMessage)
            }
        }
        .onAppear {
            viewModel.loadSavedNotes(currentUser: authViewModel.user)
        }
        .onChange(of: authViewModel.user?.uid) { _ in
            viewModel.loadSavedNotes(currentUser: authViewModel.user)
        }
    }
}

struct ScanPreviewView: View {
    @ObservedObject var viewModel: ScanViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var showSummaryResult = false
    @State private var showSimplifiedResult = false
    @State private var showRelatedNewsResult = false
    @State private var showSavedNotes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Scanned Text Preview")
                    .font(.headline)

                Text(viewModel.extractedText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)

                Text("Choose an action")
                    .font(.headline)

                VStack(spacing: 10) {
                    scanActionButton(title: "Summarize", icon: "text.alignleft") {
                        Task {
                            let success = await viewModel.summarizeExtractedText()
                            if success {
                                showSummaryResult = true
                            }
                        }
                    }

                    scanActionButton(title: "Save as Notes", icon: "square.and.arrow.down") {
                        Task {
                            let success = await viewModel.saveExtractedTextAsNote(currentUser: authViewModel.user)
                            if success {
                                showSavedNotes = true
                            }
                        }
                    }

                    scanActionButton(title: "Search Related News", icon: "magnifyingglass") {
                        Task {
                            let success = await viewModel.searchRelatedNews()
                            if success {
                                showRelatedNewsResult = true
                            }
                        }
                    }

                    scanActionButton(title: "Simplify Content", icon: "wand.and.stars") {
                        Task {
                            let success = await viewModel.simplifyExtractedText()
                            if success {
                                showSimplifiedResult = true
                            }
                        }
                    }
                }

                if let success = viewModel.successMessage {
                    Text(success)
                        .font(.footnote)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
            .padding(16)
            .tabBarOverlayBottomPadding()
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isProcessing {
                ScanProcessingOverlay(text: viewModel.processingState.statusMessage)
            }
        }
        .background(
            Group {
                NavigationLink(
                    destination: ScanSummaryResultView(summaryText: viewModel.summaryText ?? "", originalText: viewModel.extractedText),
                    isActive: $showSummaryResult
                ) {
                    EmptyView()
                }
                NavigationLink(
                    destination: ScanSimplifiedResultView(originalText: viewModel.extractedText, simplifiedText: viewModel.simplifiedText ?? ""),
                    isActive: $showSimplifiedResult
                ) {
                    EmptyView()
                }
                NavigationLink(
                    destination: ScanRelatedNewsResultView(articles: viewModel.relatedArticles, keywords: viewModel.extractedKeywords),
                    isActive: $showRelatedNewsResult
                ) {
                    EmptyView()
                }
                NavigationLink(
                    destination: SavedScansNotesView(viewModel: viewModel).environmentObject(authViewModel),
                    isActive: $showSavedNotes
                ) {
                    EmptyView()
                }
            }
            .hidden()
        )
    }

    private func scanActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .foregroundColor(.primary)
            .cornerRadius(12)
        }
    }
}

struct ScanSummaryResultView: View {
    let summaryText: String
    let originalText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Summary", systemImage: "text.alignleft")
                    .font(.headline)

                Text(summaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                Label("Original", systemImage: "doc.text")
                    .font(.headline)

                Text(originalText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
            .padding(16)
            .tabBarOverlayBottomPadding()
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ScanSimplifiedResultView: View {
    let originalText: String
    let simplifiedText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Simplified Version", systemImage: "wand.and.stars")
                    .font(.headline)

                Text(simplifiedText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                Label("Original Text", systemImage: "doc.text")
                    .font(.headline)

                Text(originalText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
            .padding(16)
            .tabBarOverlayBottomPadding()
        }
        .navigationTitle("Simplified")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ScanRelatedNewsResultView: View {
    let articles: [Article]
    let keywords: [String]

    var body: some View {
        Group {
            if articles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary)
                    Text("No related articles found")
                        .font(.headline)
                    Text("Try scanning a clearer or more specific topic.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    if !keywords.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Detected keywords")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(Array(keywords.prefix(8)), id: \.self) { keyword in
                                        Text(keyword)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.12))
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    ForEach(articles, id: \.id) { article in
                        NavigationLink(destination: NewsArticleDetailView(article: article)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(article.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                if let description = article.description {
                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Related News")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SavedScansNotesView: View {
    @ObservedObject var viewModel: ScanViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if viewModel.savedScanNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No saved scans yet")
                        .font(.headline)
                    Text("Use Scan Text and tap Save as Notes to build your study notes.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding()
            } else {
                List {
                    ForEach(viewModel.savedScanNotes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.text)
                                .font(.body)
                                .lineLimit(5)

                            if !note.keywords.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(Array(note.keywords.prefix(6)), id: \.self) { keyword in
                                            Text(keyword)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.indigo.opacity(0.12))
                                                .cornerRadius(10)
                                        }
                                    }
                                }
                            }

                            Text("Updated \(relativeTimeString(for: note.updatedAt))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let note = viewModel.savedScanNotes[index]
                            viewModel.removeSavedNote(note, currentUser: authViewModel.user)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Saved Scans")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadSavedNotes(currentUser: authViewModel.user)
        }
        .onChange(of: authViewModel.user?.uid) { _ in
            viewModel.loadSavedNotes(currentUser: authViewModel.user)
        }
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct ScanProcessingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ProgressView()
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 8)
        }
    }
}

struct DocumentTextScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard VNDocumentCameraViewController.isSupported else {
            let controller = UIViewController()
            DispatchQueue.main.async {
                onFailure("Document scanner is not supported on this device.")
            }
            return controller
        }

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentTextScannerView

        init(_ parent: DocumentTextScannerView) {
            self.parent = parent
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            parent.onFailure("Scanning failed. Please try again.")
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            if scan.pageCount > 0 {
                for index in 0..<scan.pageCount {
                    images.append(scan.imageOfPage(at: index))
                }
            }

            controller.dismiss(animated: true) {
                self.parent.onScan(images)
            }
        }
    }
}
