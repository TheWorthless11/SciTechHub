//
//  SciTechHubApp.swift
//  SciTechHub
//
//  Created by Sayaka Alam on 5/4/26.
//

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
        

        var body: some Scene {
            WindowGroup {
                if authViewModel.isSignedIn {
                    HomeView()
                } else {
                    AuthView()
                        .environmentObject(authViewModel)
                }
            }
        }
    }
