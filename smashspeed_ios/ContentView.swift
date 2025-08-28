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
                .frame(width: 80, height: 80)
                .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)

            // LOCALIZED
            Text("appName")
                .font(.largeTitle)
                .fontWeight(.bold)

            ProgressView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var languageManager: LanguageManager
    var body: some View {
        TabView {
            DetectView()
                .tabItem {
                    // LOCALIZED
                    Label("tab_detect", systemImage: "camera.viewfinder")
                }
            
            NavigationStack {
                HistoryView()
                    // LOCALIZED
                    .navigationTitle(Text("history_navTitle"))
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                    }
            }
            // LOCALIZED
            .tabItem { Label("tab_results", systemImage: "chart.bar.xaxis") }

            NavigationStack {
                AccountView()
                    // LOCALIZED
                    .navigationTitle(Text("account_navTitle"))
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                    }
            }
            // LOCALIZED
            .tabItem { Label("tab_account", systemImage: "person.crop.circle") }
        }
        .id(languageManager.languageCode)
    }
}

struct AppLogoView: View {
    var body: some View {
        HStack {
            Image("AppIconTransparent")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .shadow(color: .blue.opacity(0.3), radius: 4, y: 1)

            // LOCALIZED
            Text("appName")
                .font(.headline)
                .fontWeight(.bold)
        }
    }
}
