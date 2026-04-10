//
//  SciTechHubApp.swift
//  SciTechHub
//
//  Created by Sayaka Alam on 5/4/26.
// Roll: 2107081 & 2107082

import SwiftUI
import FirebaseCore
class AppDelegate: NSObject, UIApplicationDelegate {
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
  FirebaseApp.configure()

  return true
}
}


@main
struct SciTechHubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var authViewModel = AuthViewModel()
    @StateObject var bookmarkManager = BookmarkManager() // Initialize Bookmark Manager globally
    @StateObject var userActivityViewModel = UserActivityViewModel()
    @AppStorage("isDarkMode") private var isDarkMode = false
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(bookmarkManager) // Inject down for all tabs
                .environmentObject(authViewModel)   // Provide auth access globally
                .environmentObject(userActivityViewModel)
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}
