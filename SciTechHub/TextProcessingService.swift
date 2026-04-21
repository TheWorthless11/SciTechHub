import Foundation

@MainActor
protocol TextProcessingServicing {
    var lastErrorMessage: String? { get }
    func summarize(text: String) async -> String
    func simplify(text: String) async -> String
}

@MainActor
final class TextProcessingService: TextProcessingServicing {
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
                    let text: String?
                }

                enum CodingKeys: String, CodingKey {
                    case content
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)

                    if let direct = try? container.decode(String.self, forKey: .content) {
                        content = direct
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
        }

        let error: APIError
    }

    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let placeholderKey = "YOUR_OPENAI_API_KEY"

    private(set) var lastErrorMessage: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func summarize(text: String) async -> String {
        let fallback = fallbackSummary(from: text)
        return await process(
            text: text,
            instruction: "Summarize this news article in 2-3 short sentences.",
            maxTokens: 140,
            fallback: fallback
        )
    }

    func simplify(text: String) async -> String {
        let fallback = fallbackSimplified(from: text)
        return await process(
            text: text,
            instruction: "Explain this article in beginner-friendly language with simple words and short sentences.",
            maxTokens: 180,
            fallback: fallback
        )
    }

    private func process(text: String, instruction: String, maxTokens: Int, fallback: String) async -> String {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            lastErrorMessage = "No content available for text processing."
            return fallback
        }

        guard let key = apiKey else {
            lastErrorMessage = "AI service is not configured. Showing a quick local result."
            return fallback
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let payload = ChatCompletionRequest(
            model: "gpt-4o-mini",
            messages: [
                .init(role: "system", content: "You are a concise assistant for science and technology news."),
                .init(role: "user", content: "\(instruction)\n\nArticle:\n\(clipped(input))")
            ],
            temperature: 0.3,
            maxTokens: maxTokens
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastErrorMessage = "Invalid response from AI service. Showing a quick local result."
                return fallback
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let apiMessage = extractAPIErrorMessage(from: data)
                if apiMessage.isEmpty {
                    lastErrorMessage = "AI request failed. Showing a quick local result."
                } else {
                    lastErrorMessage = "AI request failed: \(apiMessage). Showing a quick local result."
                }
                return fallback
            }

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            let output = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !output.isEmpty else {
                lastErrorMessage = "AI returned an empty response. Showing a quick local result."
                return fallback
            }

            lastErrorMessage = nil
            return output
        } catch {
            lastErrorMessage = "Couldn't reach AI service. Showing a quick local result."
            return fallback
        }
    }

    private var apiKey: String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               trimmed != "REPLACE_WITH_YOUR_KEY",
               trimmed != placeholderKey {
                return trimmed
            }
        }

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let key = plist["OPENAI_API_KEY"] as? String {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != placeholderKey {
                return trimmed
            }
        }

        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            let trimmed = envKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != placeholderKey {
                return trimmed
            }
        }

        return nil
    }

    private func clipped(_ text: String, maxCharacters: Int = 5000) -> String {
        if text.count <= maxCharacters {
            return text
        }
        return String(text.prefix(maxCharacters))
    }

    private func fallbackSummary(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No content available to summarize."
        }

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !lines.isEmpty {
            return Array(lines.prefix(2)).joined(separator: "\n")
        }

        let sentences = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if sentences.isEmpty {
            return trimmed
        }

        let fallback = Array(sentences.prefix(2)).joined(separator: ". ")
        return fallback.hasSuffix(".") ? fallback : fallback + "."
    }

    private func fallbackSimplified(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No content available to simplify."
        }

        if trimmed.count <= 220 {
            return "Simple version: \(trimmed)"
        }

        return "Simple version: \(String(trimmed.prefix(220)))..."
    }

    private func extractAPIErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            let message = decoded.error.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                return message
            }
        }

        if let raw = String(data: data, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed
        }

        return ""
    }
}
