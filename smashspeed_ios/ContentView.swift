//
//  ContentView.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthenticationViewModel()
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        ZStack {
            switch authViewModel.authState {
            case .unknown:
                LoadingView()
            case .signedIn, .signedOut:
                MainTabView()
                    .environmentObject(authViewModel)
            }
        }
        .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            Text("SmashSpeed")
                .font(.largeTitle)
                .fontWeight(.bold)
            ProgressView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            // --- The NavigationStack has been removed from here ---
            // It is now managed inside DetectView.swift
            DetectView()
                .tabItem {
                    Label("Detect", systemImage: "camera.viewfinder")
                }
            
            NavigationStack {
                HistoryView()
                    .navigationTitle("Results")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                    }
            }
            .tabItem { Label("Results", systemImage: "chart.bar.xaxis") }

            NavigationStack {
                AccountView()
                    .navigationTitle("Account")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                    }
            }
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}

struct AppLogoView: View {
    var body: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundColor(.blue)
            Text("SmashSpeed")
                .font(.headline)
                .fontWeight(.bold)
        }
    }
}
