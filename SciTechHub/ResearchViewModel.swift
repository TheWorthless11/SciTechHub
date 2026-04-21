import Foundation

@MainActor
final class ResearchViewModel: ObservableObject {
    @Published var papers: [ResearchPaper] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var selectedCategory: ResearchCategoryChip?
    @Published var sortOption: ResearchSortOption = .latest {
        didSet {
            applySorting()
        }
    }
    @Published private(set) var recommendationBannerText: String?
    @Published private(set) var hasMoreResults = true

    private let service: ResearchServiceProtocol
    private let pageSize = 20
    private var currentOffset = 0
    private var activeKeyword: String?
    private var fetchedPapers: [ResearchPaper] = []

    init(service: ResearchServiceProtocol = ResearchService()) {
        self.service = service
    }

    func loadInitialPapersIfNeeded() async {
        guard papers.isEmpty else {
            return
        }

        if let recommendedCategory = ResearchPreferenceStore.shared.topCategory() {
            recommendationBannerText = "Recommended for you: \(recommendedCategory.rawValue)"
            await selectCategory(recommendedCategory, keepRecommendationBanner: true)
            return
        }

        recommendationBannerText = nil
        await loadLatestPapers()
    }

    func loadLatestPapers(clearRecommendationBanner: Bool = true) async {
        if clearRecommendationBanner {
            recommendationBannerText = nil
        }

        currentOffset = 0
        activeKeyword = nil
        hasMoreResults = true
        isLoading = true
        errorMessage = nil

        do {
            let result = try await service.fetchLatestPapers(limit: pageSize, offset: currentOffset)
            fetchedPapers = result
            currentOffset += result.count
            hasMoreResults = result.count == pageSize
            applySorting()

            if result.isEmpty {
                errorMessage = "No latest papers available right now."
            }
        } catch {
            fetchedPapers = []
            papers = []
            hasMoreResults = false
            if let localized = (error as? LocalizedError)?.errorDescription {
                errorMessage = localized
            } else {
                errorMessage = "Failed to load latest papers."
            }
        }

        isLoading = false
    }

    func searchPapers() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            selectedCategory = nil
            await loadLatestPapers()
            return
        }

        recommendationBannerText = nil

        if let selectedCategory,
           selectedCategory.searchKeyword.caseInsensitiveCompare(query) != .orderedSame {
            self.selectedCategory = nil
        }

        await fetchSearchResults(keyword: query)
    }

    func selectCategory(_ category: ResearchCategoryChip, keepRecommendationBanner: Bool = false) async {
        if !keepRecommendationBanner {
            recommendationBannerText = nil
        }

        selectedCategory = category
        searchText = category.searchKeyword
        await fetchSearchResults(keyword: category.searchKeyword)
    }

    func recordBookmarkInterest(for paper: ResearchPaper) {
        ResearchPreferenceStore.shared.recordInterest(for: paper, weight: 1)
    }

    func recordLoveInterest(for paper: ResearchPaper) {
        ResearchPreferenceStore.shared.recordInterest(for: paper, weight: 2)
    }

    private func fetchSearchResults(keyword: String) async {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return
        }

        currentOffset = 0
        activeKeyword = query
        hasMoreResults = true
        isLoading = true
        errorMessage = nil

        do {
            let result = try await service.searchPapers(
                keyword: query,
                limit: pageSize,
                offset: currentOffset,
                sort: sortOption
            )
            fetchedPapers = result
            currentOffset += result.count
            hasMoreResults = result.count == pageSize
            applySorting()

            if result.isEmpty {
                errorMessage = "No papers found for \"\(query)\"."
            }
        } catch {
            fetchedPapers = []
            papers = []
            hasMoreResults = false
            if let localized = (error as? LocalizedError)?.errorDescription {
                errorMessage = localized
            } else {
                errorMessage = "Failed to load research papers."
            }
        }

        isLoading = false
    }

    func loadMoreIfNeeded(currentPaper: ResearchPaper) async {
        guard hasMoreResults,
              !isLoading,
              !isLoadingMore,
              currentPaper.id == papers.last?.id else {
            return
        }

        isLoadingMore = true

        do {
            let nextPage: [ResearchPaper]
            if let keyword = activeKeyword, !keyword.isEmpty {
                nextPage = try await service.searchPapers(
                    keyword: keyword,
                    limit: pageSize,
                    offset: currentOffset,
                    sort: sortOption
                )
            } else {
                nextPage = try await service.fetchLatestPapers(limit: pageSize, offset: currentOffset)
            }

            if nextPage.isEmpty {
                hasMoreResults = false
            } else {
                let existingIds = Set(fetchedPapers.map { $0.id })
                let uniqueNewItems = nextPage.filter { !existingIds.contains($0.id) }

                if uniqueNewItems.isEmpty {
                    hasMoreResults = false
                } else {
                    currentOffset += nextPage.count
                    hasMoreResults = nextPage.count == pageSize
                    fetchedPapers.append(contentsOf: uniqueNewItems)
                    applySorting()
                }
            }
        } catch {
            if let localized = (error as? LocalizedError)?.errorDescription {
                errorMessage = localized
            } else {
                errorMessage = "Failed to load more papers."
            }
        }

        isLoadingMore = false
    }

    private func applySorting() {
        switch sortOption {
        case .latest:
            papers = fetchedPapers.sorted {
                publishDate(for: $0) > publishDate(for: $1)
            }
        case .mostRelevant:
            let currentQuery = activeKeyword ?? selectedCategory?.searchKeyword ?? searchText
            papers = fetchedPapers.sorted { left, right in
                let leftScore = relevanceScore(for: left, query: currentQuery)
                let rightScore = relevanceScore(for: right, query: currentQuery)

                if leftScore == rightScore {
                    return publishDate(for: left) > publishDate(for: right)
                }

                return leftScore > rightScore
            }
        }
    }

    private func relevanceScore(for paper: ResearchPaper, query: String) -> Int {
        let normalizedQuery = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard !normalizedQuery.isEmpty else {
            return Int(publishDate(for: paper).timeIntervalSince1970 / 86_400)
        }

        let titleText = paper.title.lowercased()
        let abstractText = paper.abstract.lowercased()
        let categoryText = (paper.categoryLabel ?? "").lowercased()

        var score = 0
        for token in normalizedQuery {
            if titleText.contains(token) {
                score += 5
            }
            if abstractText.contains(token) {
                score += 2
            }
            if categoryText.contains(token) {
                score += 3
            }
        }

        if let selectedCategory, paper.categoryLabel == selectedCategory.rawValue {
            score += 6
        }

        return score
    }

    private func publishDate(for paper: ResearchPaper) -> Date {
        paper.publishedAt ?? .distantPast
    }
}
