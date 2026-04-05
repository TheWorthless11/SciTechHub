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
                    
                    // MARK: - My Stuff Section
                    Text("My Stuff")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                        .padding(.top, 10)
                    
                    VStack(spacing: 16) {
                        NavigationLink(destination: BookmarkView()) {
                            HStack(spacing: 15) {
                                Text("❤️")
                                    .font(.title2)
                                
                                Text("Bookmarks")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        NavigationLink(destination: NotesView()) {
                            HStack(spacing: 15) {
                                Text("📝")
                                    .font(.title2)
                                
                                Text("My Notes")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("SciTech Hub")
            // Logout button
            .navigationBarItems(trailing: Button(action: {
                authViewModel.signOut()
            }) {
                Text("Logout")
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .cornerRadius(8)
            })
            // Reload bookmarks based on current user
            .onAppear {
                bookmarkManager.loadBookmarks()
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(BookmarkManager())
            .environmentObject(AuthViewModel())
    }
}
