import Foundation
import SwiftUI

// MARK: - 1. Model
struct Topic: Codable, Identifiable, Equatable {
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
        
        ScrollView {
            VStack(spacing: 16) {
                ForEach(filteredTopics) { topic in
                    // Tap a topic -> Go to Detail View
                    NavigationLink(destination: TopicDetailView(topic: topic)) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(topic.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text(topic.description)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .lineLimit(2) // Keeps it as a short preview
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(12)
                        // Add shadow to create a nice pop-out card effect
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground)) // Subtle gray background to make white cards pop
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - 4. TopicDetailView
struct TopicDetailView: View {
    let topic: Topic // Received from TopicListView
    
    // Connect to our global BookmarkManager
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title & Tag Group
                VStack(alignment: .leading, spacing: 10) {
                    Text(topic.title)
                        // Make font even larger and bold
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    
                    // Styled Category Tag / Pill
                    Text(topic.category.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(20)
                }
                
                Divider() // Clean separator line
                
                // Main Description Group
                VStack(alignment: .leading, spacing: 15) {
                    Text("Overview")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(topic.description)
                        .font(.body)
                        .lineSpacing(6) // Better reading layout
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 40)
            }
            .padding(20)
            // Make the VStack take up the whole width, aligning items left
            .frame(maxWidth: .infinity, alignment: .leading) 
        }
        .background(Color(.systemBackground))
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        // Add the Bookmark button to the top right of the screen
        .navigationBarItems(trailing: Button(action: {
            bookmarkManager.toggleBookmark(topic: topic)
        }) {
            Image(systemName: bookmarkManager.isBookmarked(topic: topic) ? "heart.fill" : "heart")
                .foregroundColor(bookmarkManager.isBookmarked(topic: topic) ? .red : .blue)
                .font(.title2)
                .padding(8)
                .background(Circle().fill(Color.gray.opacity(0.1))) // Soft circular background for button
        })
    }
}