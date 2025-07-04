//
//  smashspeedApp.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.


import SwiftUI
import FirebaseCore

// This class is used to configure Firebase when the app starts.
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    // This is the central configuration call for Firebase.
    FirebaseApp.configure()
    return true
  }
}

@main
struct smashspeed_iosApp: App {
  // Register the app delegate for Firebase setup
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
