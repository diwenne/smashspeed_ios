import SwiftUI

struct ContentView: View {
    @StateObject private var authViewModel = AuthenticationViewModel()
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        ZStack {
            // --- MODIFICATION ---
            // The view now checks the authState. The main app (MainTabView) is only shown
            // when the user is signed in. Otherwise, the AccountView is shown.
            switch authViewModel.authState {
            case .unknown:
                LoadingView()
            case .signedIn:
                MainTabView()
                    .environmentObject(authViewModel)
            case .signedOut:
                AccountView()
                    .environmentObject(authViewModel)
            }
        }
        .sheet(isPresented: .constant(!hasCompletedOnboarding && authViewModel.authState != .unknown)) {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}

// --- LoadingView and MainTabView are unchanged ---

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("AppIconTransparent")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)

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
                    Label("tab_detect", systemImage: "camera.viewfinder")
                }
            
            NavigationStack {
                HistoryView()
                    .navigationTitle(Text("history_navTitle"))
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                    }
            }
            .tabItem { Label("tab_results", systemImage: "chart.bar.xaxis") }

            NavigationStack {
                AccountView()
                    .navigationTitle(Text("account_navTitle"))
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                    }
            }
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

            Text("appName")
                .font(.headline)
                .fontWeight(.bold)
        }
    }
}
