import SwiftUI

struct TrendingView: View {
    @EnvironmentObject var bookmarkManager: BookmarkManager
    
    var body: some View {
        NavigationView {
            NewsView() // Reuse our existing news view logic perfectly here
                .navigationTitle("Trending")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct TrendingView_Previews: PreviewProvider {
    static var previews: some View {
        TrendingView()
            .environmentObject(BookmarkManager())
    }
}
