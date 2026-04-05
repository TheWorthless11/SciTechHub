import Foundation

class NewsViewModel: ObservableObject {
    @Published var scienceArticles: [Article] = []
    @Published var techArticles: [Article] = []
    @Published var isLoading: Bool = false
    
    
    private let apiKey = "635dcde799d14101b7b967df87c7106e"
    
    func fetchScienceNews() {
        isLoading = true
        
        let urlString = "https://newsapi.org/v2/top-headlines?category=science&apiKey=\(apiKey)"
        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            // Handle network error
            if let error = error {
                print("Error fetching science news: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            // Decode the JSON
            do {
                let decodedResponse = try JSONDecoder().decode(NewsResponse.self, from: data)
                // Always update UI on the Main Thread
                DispatchQueue.main.async {
                    self.scienceArticles = decodedResponse.articles
                    self.isLoading = false
                }
            } catch {
                print("Failed to decode science news: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }.resume()
    }
    
    func fetchTechNews() {
        isLoading = true
        
        let urlString = "https://newsapi.org/v2/top-headlines?category=technology&apiKey=\(apiKey)"
        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            // Handle network error
            if let error = error {
                print("Error fetching tech news: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            // Decode the JSON
            do {
                let decodedResponse = try JSONDecoder().decode(NewsResponse.self, from: data)
                // Always update UI on the Main Thread
                DispatchQueue.main.async {
                    self.techArticles = decodedResponse.articles
                    self.isLoading = false
                }
            } catch {
                print("Failed to decode tech news: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }.resume()
    }
}
