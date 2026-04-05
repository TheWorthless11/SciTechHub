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
    // Sample categories
    let categories = [
        Category(name: "Science", emoji: "🔬"),
        Category(name: "Artificial Intelligence", emoji: "🤖"),
        Category(name: "Space", emoji: "🚀"),
        Category(name: "Health", emoji: "🩺")
    ]
    
    var body: some View {
        NavigationView {
            List(categories) { category in
                NavigationLink(destination: TopicListView(categoryName: category.name)) {
                    HStack(spacing: 15) {
                        Text(category.emoji)
                            .font(.title)
                        
                        Text(category.name)
                            .font(.headline)
                    }
                    .padding(.vertical, 8) // Makes the row look more like a button/card
                }
            }
            .navigationTitle("SciTech Hub")
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
