import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        TabView {
            // Tab 1: Home
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            
            // Tab 2: Trending
            TrendingView()
                .tabItem {
                    Label("Trending", systemImage: "flame")
                }
            
            // Tab 3: Bookmarks
            BookmarkWrapperView()
                .tabItem {
                    Label("Saved", systemImage: "bookmark")
                }
            
            // Tab 4: Notes
            NotesWrapperView()
                .tabItem {
                    Label("My Notes", systemImage: "note.text")
                }
        }
        // Change the accent color of selected tab
        .accentColor(.blue)
    }
}

// Wrapper for Bookmarks to give it its own NavigationView independently of the Home tab
struct BookmarkWrapperView: View {
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        NavigationView {
            BookmarkView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// Wrapper for Notes to give it its own NavigationView independently of the Home tab
struct NotesWrapperView: View {
    var body: some View {
        NavigationView {
            NotesView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(AuthViewModel())
            .environmentObject(BookmarkManager())
    }
}
