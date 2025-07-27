//
//  smashspeedApp.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

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

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: Self { self }
}

@main
struct smashspeed_iosApp: App {
  // Register the app delegate for Firebase setup
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
  @StateObject private var versionChecker = VersionChecker()
    
  @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
  // ❗️ IMPORTANT: Replace this with your actual App Store ID
  private let appStoreID = "6748543435"
  private var appStoreURL: URL {
      URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
  }

  var body: some Scene {
    WindowGroup {
        ContentView()
            .alert("Update Required", isPresented: $versionChecker.needsForceUpdate) {
                // This button takes the user directly to the App Store.
                // Because it's the only button, the user must tap it.
                Link("Update Now", destination: appStoreURL)
            } message: {
                Text("A new version of the app is available. Please update to continue using the app.")
            }
            .task {
                // Run the version check as soon as the app's UI is ready
                await versionChecker.checkVersion()
            }
        
            .preferredColorScheme(appearanceMode == .light ? .light : (appearanceMode == .dark ? .dark : nil))
    }
  }
}
