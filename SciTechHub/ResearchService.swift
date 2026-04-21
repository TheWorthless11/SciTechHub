import Foundation

enum ResearchServiceError: LocalizedError {
    case emptyQuery
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case rateLimited(retryAfter: Int?)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Please enter a search keyword."
        case .invalidURL:
            return "Failed to prepare research request URL."
        case .invalidResponse:
            return "Invalid response from research server."
        case let .serverError(code):
            return "Research server returned error code \(code)."
        case let .rateLimited(retryAfter):
            if let retryAfter, retryAfter > 0 {
                return "Research server is busy. Please try again in about \(retryAfter) seconds."
            }
            return "Research server is busy. Please wait a moment and try again."
        case .decodingError:
            return "Could not decode research papers response."
        }
    }
}

protocol ResearchServiceProtocol {
    func fetchLatestPapers(limit: Int, offset: Int) async throws -> [ResearchPaper]
    func searchPapers(keyword: String, limit: Int, offset: Int, sort: ResearchSortOption) async throws -> [ResearchPaper]
}

final class ResearchService: ResearchServiceProtocol {
    private let session: URLSession
    private let rateLimiter = ArxivRateLimiter()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestPapers(limit: Int = 20, offset: Int = 0) async throws -> [ResearchPaper] {
        do {
            let primary = try await fetchFromArxiv(
                searchQuery: "cat:cs.*",
                limit: limit,
                offset: offset,
                sortBy: .latest
            )
            if !primary.isEmpty {
                return primary
            }
        } catch let error as ResearchServiceError {
            if case .rateLimited = error {
                throw error
            }
        } catch {
            // Fallback to AI category below if broad CS query fails.
        }

        return try await fetchFromArxiv(
            searchQuery: "cat:cs.AI",
            limit: limit,
            offset: offset,
            sortBy: .latest
        )
    }

    func searchPapers(
        keyword: String,
        limit: Int = 20,
        offset: Int = 0,
        sort: ResearchSortOption = .mostRelevant
    ) async throws -> [ResearchPaper] {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else {
            throw ResearchServiceError.emptyQuery
        }

        let query = buildSearchQuery(from: trimmedKeyword)
        return try await fetchFromArxiv(searchQuery: query, limit: limit, offset: offset, sortBy: sort)
    }

    private func fetchFromArxiv(
        searchQuery: String,
        limit: Int,
        offset: Int,
        sortBy: ResearchSortOption
    ) async throws -> [ResearchPaper] {
        try await rateLimiter.waitIfNeeded()

        guard var components = URLComponents(string: "https://export.arxiv.org/api/query") else {
            throw ResearchServiceError.invalidURL
        }

        let remoteSortBy: String
        switch sortBy {
        case .latest:
            remoteSortBy = "submittedDate"
        case .mostRelevant:
            remoteSortBy = "relevance"
        }

        components.queryItems = [
            URLQueryItem(name: "search_query", value: searchQuery),
            URLQueryItem(name: "start", value: String(max(0, offset))),
            URLQueryItem(name: "max_results", value: String(max(1, min(limit, 50)))),
            URLQueryItem(name: "sortBy", value: remoteSortBy),
            URLQueryItem(name: "sortOrder", value: "descending")
        ]

        guard let url = components.url else {
            throw ResearchServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("SciTechHub/1.0 (Research feature)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResearchServiceError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = Self.parseRetryAfter(from: httpResponse.value(forHTTPHeaderField: "Retry-After"))
            throw ResearchServiceError.rateLimited(retryAfter: retryAfter)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ResearchServiceError.serverError(httpResponse.statusCode)
        }

        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw ResearchServiceError.decodingError
        }

        let parser = ArxivFeedParser()
        guard let papers = parser.parse(xmlString: xmlString) else {
            throw ResearchServiceError.decodingError
        }

        return papers
    }

    private func buildSearchQuery(from keyword: String) -> String {
        let tokens = keyword
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return "all:science"
        }

        return tokens
            .map { "all:\($0)" }
            .joined(separator: "+AND+")
    }

    private static func parseRetryAfter(from header: String?) -> Int? {
        guard let header else {
            return nil
        }

        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let seconds = Int(trimmed), seconds >= 0 {
            return seconds
        }

        return nil
    }
}

private actor ArxivRateLimiter {
    private var lastRequestDate: Date?
    private let minimumInterval: TimeInterval = 1.25

    func waitIfNeeded() async throws {
        let now = Date()

        if let lastRequestDate {
            let elapsed = now.timeIntervalSince(lastRequestDate)
            let remaining = minimumInterval - elapsed

            if remaining > 0 {
                let delay = UInt64(remaining * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }

        lastRequestDate = Date()
    }
}

private final class ArxivFeedParser: NSObject, XMLParserDelegate {
    private var papers: [ResearchPaper] = []

    private var currentElement = ""
    private var currentId = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentPublished = ""
    private var currentAuthors: [String] = []
    private var currentAuthorName = ""
    private var currentCategoryCode = ""
    private var currentPDFURLString = ""

    private var isInsideEntry = false
    private var isInsideAuthor = false

    func parse(xmlString: String) -> [ResearchPaper]? {
        papers = []

        guard let data = xmlString.data(using: .utf8) else {
            return nil
        }

        let parser = XMLParser(data: data)
        parser.delegate = self
        let success = parser.parse()
        return success ? papers : nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        if elementName == "entry" {
            isInsideEntry = true
            currentId = ""
            currentTitle = ""
            currentSummary = ""
            currentPublished = ""
            currentAuthors = []
            currentCategoryCode = ""
            currentPDFURLString = ""
        } else if elementName == "author" {
            isInsideAuthor = true
            currentAuthorName = ""
        } else if elementName == "category" && isInsideEntry {
            if currentCategoryCode.isEmpty {
                currentCategoryCode = attributeDict["term"] ?? ""
            }
        } else if elementName == "link" && isInsideEntry {
            let title = attributeDict["title"] ?? ""
            if title.lowercased() == "pdf" {
                currentPDFURLString = attributeDict["href"] ?? ""
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideEntry else {
            return
        }

        switch currentElement {
        case "id":
            currentId += string
        case "title":
            currentTitle += string
        case "summary":
            currentSummary += string
        case "published":
            currentPublished += string
        case "name" where isInsideAuthor:
            currentAuthorName += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "author" {
            isInsideAuthor = false
            let trimmedAuthor = normalize(currentAuthorName)
            if !trimmedAuthor.isEmpty {
                currentAuthors.append(trimmedAuthor)
            }
        }

        if elementName == "entry" {
            isInsideEntry = false

            let normalizedTitle = normalize(currentTitle)
            guard !normalizedTitle.isEmpty else {
                return
            }

            let normalizedId = normalize(currentId)
            if normalizedTitle.lowercased() == "error"
                || normalizedId.lowercased().contains("/api/errors") {
                return
            }

            let publishedDate = normalizeDate(currentPublished)
            let publishedAt = parsePublishedDate(currentPublished)
            let normalizedSummary = normalize(currentSummary)
            let paperURL = URL(string: normalizedId)
            let pdfURL = URL(string: normalize(currentPDFURLString))

            let paper = ResearchPaper(
                id: normalizedId.isEmpty ? UUID().uuidString : normalizedId,
                title: normalizedTitle,
                authors: currentAuthors,
                abstract: normalizedSummary,
                publishedDate: publishedDate,
                publishedAt: publishedAt,
                categoryCode: currentCategoryCode.isEmpty ? nil : currentCategoryCode,
                paperURL: paperURL,
                pdfURL: pdfURL
            )

            papers.append(paper)
        }

        currentElement = ""
    }

    private func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeDate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown date"
        }

        if trimmed.count >= 10 {
            let index = trimmed.index(trimmed.startIndex, offsetBy: 10)
            return String(trimmed[..<index])
        }

        return trimmed
    }

    private func parsePublishedDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return ISO8601DateFormatter().date(from: trimmed)
    }
}
