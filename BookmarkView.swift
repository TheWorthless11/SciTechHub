//
//  BookmarkView.swift
//  SciTechHub
//
//  Created by Sayaka Alam on 5/4/26.
//

import SwiftUI

struct BookmarkView: View {
    // Access the shared bookmarks from the environment
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        Group {
            if bookmarkManager.bookmarks.isEmpty {
                // Empty state view
                VStack(spacing: 20) {
                    Text("No bookmarks yet!")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Tap the heart icon on any topic to save it here.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                // List of saved topics
                List {
                    ForEach(bookmarkManager.bookmarks) { topic in
                        NavigationLink(destination: TopicDetailView(topic: topic)) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(topic.title)
                                    .font(.headline)
                                Text(topic.category)
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    // Simple swipe removal directly from the list
                    .onDelete { indexSet in
                        for index in indexSet {
                            let topic = bookmarkManager.bookmarks[index]
                            bookmarkManager.removeBookmark(topic: topic)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
    }
}

struct BookmarkView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BookmarkView()
                .environmentObject(BookmarkManager())
        }
    }
}
