import Foundation

// MARK: - News Response Model
struct NewsResponse: Codable {
    let status: String
    let articles: [Article]
}

// MARK: - Article Model
struct Article: Codable, Identifiable {
    // Generate a unique ID since NewsAPI doesn't provide one
    var id = UUID()
    
    let title: String
    let description: String? // Made optional as NewsAPI sometimes returns null for missing descriptions
    let urlToImage: String?
    
    // We use CodingKeys to tell Swift to ignore the "id" property when decoding the JSON,
    // and only look for the fields that actually come from NewsAPI.
    enum CodingKeys: String, CodingKey {
        case title
        case description
        case urlToImage
    }
}
