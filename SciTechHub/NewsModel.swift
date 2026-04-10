import Foundation

// MARK: - News Response Model
struct NewsResponse: Codable {
    let status: String
    let articles: [Article]
}

// MARK: - Article Model
struct Article: Codable, Identifiable {
    // Use a stable ID so NavigationLink state is not broken by re-renders.
    var id: String {
        if let articleURL = url, !articleURL.isEmpty {
            return articleURL
        }
        return "\(title)|\(description ?? "")|\(urlToImage ?? "")"
    }
    
    let title: String
    let description: String? // Made optional as NewsAPI sometimes returns null for missing descriptions
    let urlToImage: String?
    let url: String? // The URL to the full article
    
    // Codable automatically maps these stored properties from NewsAPI fields.
}
