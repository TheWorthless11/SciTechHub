import Foundation
import SwiftUI

protocol ArticleSummaryProviding {
    func generateSummary(for article: Article) async throws -> String
}

enum ArticleSummaryError: Error {
    case missingAPIKey
    case invalidURL
    case noContentToSummarize
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case noData
    case decodingFailed(String)
    case invalidResponse
    case emptySummary

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            return "Summary AI is not configured. Add OPENAI_API_KEY in app settings."
        case .invalidURL:
            return "Summary service URL is invalid."
        case .noContentToSummarize:
            return "No content available to summarize"
        case let .networkError(details):
            return "Network error while generating summary: \(details)"
        case let .serverError(statusCode, message):
            if statusCode == 401 || statusCode == 403 {
                return "API key rejected. Check OPENAI_API_KEY permissions."
            }
            return "Summary API error (\(statusCode)): \(message)"
        case .noData:
            return "Summary service returned no data."
        case let .decodingFailed(details):
            return "Failed to read summary response: \(details)"
        case .invalidResponse:
            return "Summary service returned an invalid response."
        case .emptySummary:
            return "Summary came back empty. Please try again."
        }
    }
}

final class OpenAIArticleSummaryService: ArticleSummaryProviding {
    private struct ChatCompletionRequest: Encodable {
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

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String

                private struct ContentPart: Decodable {
                    let type: String?
                    let text: String?
                }

                enum CodingKeys: String, CodingKey {
                    case content
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)

                    if let directContent = try? container.decode(String.self, forKey: .content) {
                        content = directContent
                        return
                    }

                    if let parts = try? container.decode([ContentPart].self, forKey: .content) {
                        let merged = parts
                            .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n")
                        content = merged
                        return
                    }

                    content = ""
                }
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct APIErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
            let type: String?
            let code: String?
        }

        let error: APIError
    }

    private let session: URLSession
    private let defaultEndpoint = "https://api.openai.com/v1/chat/completions"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateSummary(for article: Article) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ArticleSummaryError.missingAPIKey
        }

        let endpointValue = endpointString
        guard let endpoint = URL(string: endpointValue) else {
            print("[ArticleSummary] Invalid endpoint URL: \(endpointValue)")
            throw ArticleSummaryError.invalidURL
        }

        let articleText = try buildArticleText(for: article)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatCompletionRequest(
            model: "gpt-4o-mini",
            messages: [
                .init(
                    role: "system",
                    content: "You summarize news into 2 to 4 short, simple lines. Focus only on the key points."
                ),
                .init(
                    role: "user",
                    content: articleText)
            ],
            temperature: 0.3,
            maxTokens: 120
        )

        request.httpBody = try JSONEncoder().encode(payload)

        logRequest(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[ArticleSummary] Network error: \(error.localizedDescription)")
            throw ArticleSummaryError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[ArticleSummary] Invalid non-HTTP response.")
            throw ArticleSummaryError.invalidResponse
        }

        logResponse(httpResponse: httpResponse, data: data)

        guard !data.isEmpty else {
            print("[ArticleSummary] Response returned empty data.")
            throw ArticleSummaryError.noData
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiMessage = extractAPIErrorMessage(from: data)
            print("[ArticleSummary] API error status \(httpResponse.statusCode): \(apiMessage)")
            throw ArticleSummaryError.serverError(statusCode: httpResponse.statusCode, message: apiMessage)
        }

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            print("[ArticleSummary] Decoding error: \(error.localizedDescription)")
            throw ArticleSummaryError.decodingFailed(error.localizedDescription)
        }

        guard let first = decoded.choices.first?.message.content else {
            throw ArticleSummaryError.emptySummary
        }

        let summary = normalizeSummary(first)
        guard !summary.isEmpty else {
            throw ArticleSummaryError.emptySummary
        }

        return summary
    }

    private var endpointString: String {
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "OPENAI_SUMMARY_ENDPOINT") as? String,
           !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return endpoint
        }

        return defaultEndpoint
    }

    private var apiKey: String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           key != "REPLACE_WITH_YOUR_KEY" {
            return key
        }

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let key = plist["OPENAI_API_KEY"] as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }

        let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        if let environmentKey, !environmentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentKey
        }

        return nil
    }

    private func buildArticleText(for article: Article) throws -> String {
        let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = article.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !title.isEmpty, !description.isEmpty {
            return "Article title: \(title)\n\nArticle details: \(description)"
        }

        if !title.isEmpty {
            return "Article title: \(title)"
        }

        if !description.isEmpty {
            return "Article details: \(description)"
        }

        throw ArticleSummaryError.noContentToSummarize
    }

    private func normalizeSummary(_ summary: String) -> String {
        let lines = summary
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.isEmpty {
            return ""
        }

        return Array(lines.prefix(4)).joined(separator: "\n")
    }

    private func logRequest(_ request: URLRequest) {
        print("[ArticleSummary] ---- API REQUEST START ----")
        print("[ArticleSummary] URL: \(request.url?.absoluteString ?? "nil")")
        print("[ArticleSummary] Method: \(request.httpMethod ?? "nil")")

        var headers = request.allHTTPHeaderFields ?? [:]
        if headers["Authorization"] != nil {
            headers["Authorization"] = "Bearer ***"
        }
        print("[ArticleSummary] Headers: \(headers)")

        if let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            print("[ArticleSummary] Body JSON: \(bodyString)")
        } else {
            print("[ArticleSummary] Body JSON: nil")
        }

        print("[ArticleSummary] ---- API REQUEST END ----")
    }

    private func logResponse(httpResponse: HTTPURLResponse, data: Data) {
        print("[ArticleSummary] ---- API RESPONSE START ----")
        print("[ArticleSummary] Status: \(httpResponse.statusCode)")
        print("[ArticleSummary] Headers: \(httpResponse.allHeaderFields)")

        if let rawJSON = String(data: data, encoding: .utf8) {
            print("[ArticleSummary] Raw JSON: \(rawJSON)")
        } else {
            print("[ArticleSummary] Raw JSON: <non-UTF8 data, \(data.count) bytes>")
        }

        print("[ArticleSummary] ---- API RESPONSE END ----")
    }

    private func extractAPIErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            let primary = decoded.error.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !primary.isEmpty {
                return primary
            }

            if let type = decoded.error.type, !type.isEmpty {
                return type
            }
        }

        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return raw
        }

        return "Unknown API error"
    }
}

@MainActor
final class ArticleSummaryViewModel: ObservableObject {
    @Published private(set) var summaryText: String?
    @Published private(set) var isSummaryVisible = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let summaryService: ArticleSummaryProviding
    private static var summaryCache: [String: String] = [:]

    init(summaryService: ArticleSummaryProviding = OpenAIArticleSummaryService()) {
        self.summaryService = summaryService
    }

    var buttonTitle: String {
        if isLoading {
            return "Generating..."
        }

        if summaryText != nil {
            return isSummaryVisible ? "Hide Summary" : "Show Summary"
        }

        return "Summarize"
    }

    func onSummaryButtonTap(for article: Article) {
        if summaryText != nil {
            isSummaryVisible.toggle()
            return
        }

        Task {
            await generateSummaryIfNeeded(for: article)
        }
    }

    func retry(for article: Article) {
        Task {
            await generateSummaryIfNeeded(for: article, forceRefresh: true)
        }
    }

    private func generateSummaryIfNeeded(for article: Article, forceRefresh: Bool = false) async {
        guard !isLoading else {
            return
        }

        errorMessage = nil
        let cacheKey = article.id

        if !forceRefresh, let cachedSummary = Self.summaryCache[cacheKey] {
            summaryText = cachedSummary
            isSummaryVisible = true
            return
        }

        isLoading = true

        defer {
            isLoading = false
        }

        do {
            let summary = try await summaryService.generateSummary(for: article)
            Self.summaryCache[cacheKey] = summary
            DispatchQueue.main.async {
                self.summaryText = summary
                self.isSummaryVisible = true
                self.errorMessage = nil
            }
        } catch let summaryError as ArticleSummaryError {
            print("[ArticleSummary] Summary error: \(summaryError)")
            DispatchQueue.main.async {
                self.summaryText = nil
                self.isSummaryVisible = false
                self.errorMessage = summaryError.userMessage
            }
        } catch {
            print("[ArticleSummary] Unexpected error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.summaryText = nil
                self.isSummaryVisible = false
                self.errorMessage = "Failed to generate summary. Please try again."
            }
        }
    }
}
