import Foundation

enum ResearchCategoryChip: String, CaseIterable, Identifiable {
    case ai = "AI"
    case robotics = "Robotics"
    case climate = "Climate"
    case space = "Space"
    case health = "Health"

    var id: String {
        rawValue
    }

    var searchKeyword: String {
        switch self {
        case .ai:
            return "artificial intelligence"
        case .robotics:
            return "robotics"
        case .climate:
            return "climate change"
        case .space:
            return "space"
        case .health:
            return "health"
        }
    }

    static func from(categoryCode: String) -> ResearchCategoryChip? {
        let code = categoryCode.lowercased()
        if code.contains("cs.ai") || code.contains("cs.lg") || code.contains("stat.ml") {
            return .ai
        }
        if code.contains("cs.ro") {
            return .robotics
        }
        if code.hasPrefix("astro-ph") {
            return .space
        }
        if code.contains("q-bio") || code.contains("q-fin") || code.contains("health") {
            return .health
        }
        if code.contains("ao-ph") || code.contains("climate") || code.contains("earth") {
            return .climate
        }
        return nil
    }

    static func detect(from text: String) -> ResearchCategoryChip? {
        let normalized = text.lowercased()

        if normalized.contains("robot") || normalized.contains("autonomous") {
            return .robotics
        }
        if normalized.contains("climate") || normalized.contains("carbon") || normalized.contains("weather") {
            return .climate
        }
        if normalized.contains("space") || normalized.contains("astronomy") || normalized.contains("satellite") {
            return .space
        }
        if normalized.contains("health") || normalized.contains("medical") || normalized.contains("biomed") {
            return .health
        }
        if normalized.contains("ai") || normalized.contains("machine learning") || normalized.contains("neural") {
            return .ai
        }

        return nil
    }
}

enum ResearchSortOption: String, CaseIterable, Identifiable {
    case latest = "Latest"
    case mostRelevant = "Most Relevant"

    var id: String {
        rawValue
    }
}

struct ResearchPaper: Identifiable, Hashable {
    let id: String
    let title: String
    let authors: [String]
    let abstract: String
    let publishedDate: String
    let publishedAt: Date?
    let categoryCode: String?
    let paperURL: URL?
    let pdfURL: URL?

    var authorsText: String {
        if authors.isEmpty {
            return "Unknown authors"
        }

        if authors.count <= 3 {
            return authors.joined(separator: ", ")
        }

        let firstThree = authors.prefix(3).joined(separator: ", ")
        return "\(firstThree) +\(authors.count - 3) more"
    }

    var authorCount: Int {
        authors.count
    }

    var authorCountText: String {
        if authorCount == 1 {
            return "1 author"
        }
        return "\(authorCount) authors"
    }

    var yearText: String {
        if let publishedAt {
            return String(Calendar.current.component(.year, from: publishedAt))
        }

        if publishedDate.count >= 4 {
            let yearEnd = publishedDate.index(publishedDate.startIndex, offsetBy: 4)
            return String(publishedDate[..<yearEnd])
        }

        return "N/A"
    }

    var categoryLabel: String? {
        if let code = categoryCode,
           let matched = ResearchCategoryChip.from(categoryCode: code) {
            return matched.rawValue
        }

        return ResearchCategoryChip.detect(from: "\(title) \(abstract)")?.rawValue
    }

    var shortAbstract: String {
        let normalized = abstract.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "No abstract available."
        }

        if normalized.count <= 220 {
            return normalized
        }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: 220)
        return String(normalized[..<endIndex]) + "..."
    }

    func toArticle() -> Article {
        let descriptionText = abstract.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDescription = "Research paper in \(categoryLabel ?? "Science")"

        return Article(
            title: title,
            description: descriptionText.isEmpty ? fallbackDescription : descriptionText,
            urlToImage: nil,
            url: paperURL?.absoluteString ?? pdfURL?.absoluteString
        )
    }
}

final class ResearchPreferenceStore {
    static let shared = ResearchPreferenceStore()

    private let userDefaults = UserDefaults.standard
    private let weightsKey = "research.preference.weights"

    private init() {}

    func recordInterest(for paper: ResearchPaper, weight: Int = 1) {
        guard weight > 0,
              let category = paper.categoryLabel,
              let chip = ResearchCategoryChip(rawValue: category) else {
            return
        }

        var weights = loadWeights()
        weights[chip.rawValue, default: 0] += weight
        userDefaults.set(weights, forKey: weightsKey)
    }

    func topCategory() -> ResearchCategoryChip? {
        let weights = loadWeights()
        guard let best = weights.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        return ResearchCategoryChip(rawValue: best)
    }

    private func loadWeights() -> [String: Int] {
        guard let dictionary = userDefaults.dictionary(forKey: weightsKey) else {
            return [:]
        }

        var normalized: [String: Int] = [:]
        for (key, value) in dictionary {
            if let intValue = value as? Int {
                normalized[key] = intValue
            } else if let numberValue = value as? NSNumber {
                normalized[key] = numberValue.intValue
            }
        }
        return normalized
    }
}
