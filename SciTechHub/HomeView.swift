//
//  HomeView.swift
//  SciTechHub
//
//  Created by Sayaka Alam on 5/4/26.
//

import Foundation
import SwiftUI

// 1. Simple Category Model
struct Category: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
}

// 2. Main Home Screen
struct HomeView: View {
    // Access the shared authentication ViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager // Add bookmarkManager access
    
    // Sample categories
    let categories = [
        Category(name: "Science", emoji: "🔬"),
        Category(name: "Artificial Intelligence", emoji: "🤖"),
        Category(name: "Space", emoji: "🚀"),
        Category(name: "Health", emoji: "🩺")
    ]
    
    // Grid layout configuration
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    
                    // MARK: - Topics Grid Section
                    Text("Explore Topics")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(categories) { category in
                            NavigationLink(destination: TopicListView(categoryName: category.name)) {
                                VStack(spacing: 12) {
                                    Text(category.emoji)
                                        .font(.system(size: 40))
                                    
                                    Text(category.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.8)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, minHeight: 120)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(16)
                            }
                            // Removing default button styling so the card looks clean
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Home")
            // Profile Icon
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ProfileView().environmentObject(authViewModel)) {
                        Image(systemName: "person.circle")
                            .font(.title2)
                    }
                }
            }
            // Reload bookmarks based on current user
            .onAppear {
                bookmarkManager.loadBookmarks()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(BookmarkManager())
            .environmentObject(AuthViewModel())
    }
}
