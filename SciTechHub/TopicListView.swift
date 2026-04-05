import Foundation
import SwiftUI

// MARK: - 1. Model
struct Topic: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let category: String
}

// MARK: - 2. ViewModel
class TopicViewModel: ObservableObject {
    // This will hold our topics and tell the View to update when it changes
    @Published var topics: [Topic] = []
    
    // Automatically load the topics when the ViewModel is created
    init() {
        loadTopics()
    }
    
    func loadTopics() {
        // 1. Find the file in our app bundle
        guard let url = Bundle.main.url(forResource: "topics", withExtension: "json") else {
            print("Failed to find topics.json in bundle.")
            return
        }
        
        do {
            // 2. Load the data from the file
            let data = try Data(contentsOf: url)
            
            // 3. Decode the JSON data into an array of strictly-typed `Topic` objects
            let decodedTopics = try JSONDecoder().decode([Topic].self, from: data)
            
            // 4. Update the published UI variable
            self.topics = decodedTopics
        } catch {
            // Very simple error handling
            print("Failed to decode topics.json: \(error.localizedDescription)")
        }
    }
}

// MARK: - 3. TopicListView (Replaces old placeholder)
struct TopicListView: View {
    let categoryName: String // Received from HomeView
    
    // Connect to the ViewModel
    @StateObject private var viewModel = TopicViewModel()
    
    var body: some View {
        // Filter the topics to only show ones matching our current category
        let filteredTopics = viewModel.topics.filter { $0.category == categoryName }
        
        List(filteredTopics) { topic in
            // Tap a topic -> Go to Detail View
            NavigationLink(destination: TopicDetailView(topic: topic)) {
                Text(topic.title)
                    .font(.headline)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 4. TopicDetailView
struct TopicDetailView: View {
    let topic: Topic // Received from TopicListView
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text(topic.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Category Tag
                Text("Category: \(topic.category)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Main Description
                Text(topic.description)
                    .font(.body)
                    .padding(.top, 10)
            }
            .padding()
            // Make the VStack take up the whole width, aligning items left
            .frame(maxWidth: .infinity, alignment: .leading) 
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}