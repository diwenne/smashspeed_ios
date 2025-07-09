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
            Image("AppIconTransparent")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80) // Matches .font(.system(size: 80))
                .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)

            Text("Smashspeed")
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
            Image("AppIconTransparent")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30) // Adjust to match symbol size
                .shadow(color: .blue.opacity(0.3), radius: 4, y: 1)

            Text("Smashspeed")
                .font(.headline)
                .fontWeight(.bold)
        }
    }
}
