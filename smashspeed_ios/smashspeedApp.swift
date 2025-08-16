import SwiftUI
import FirebaseCore
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: Self { self }
    
    var localizedKey: String {
        switch self {
        case .system: return "account_loggedIn_appearanceSystem"
        case .light: return "account_loggedIn_appearanceLight"
        case .dark: return "account_loggedIn_appearanceDark"
        }
    }
}

@main
struct smashspeed_iosApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
  @StateObject private var versionChecker = VersionChecker()
    
  @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
  private let appStoreID = "6748543435" // Replace with your actual App Store ID
  private var appStoreURL: URL {
      URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
  }

  var body: some Scene {
    WindowGroup {
        ContentView()
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            // LOCALIZED
            .alert(Text("updateAlert_title"), isPresented: $versionChecker.needsForceUpdate) {
                // LOCALIZED
                Link(NSLocalizedString("updateAlert_button", comment: ""), destination: appStoreURL)
            } message: {
                // LOCALIZED
                Text("updateAlert_message")
            }
            .task {
                await versionChecker.checkVersion()
            }
            .preferredColorScheme(appearanceMode == .light ? .light : (appearanceMode == .dark ? .dark : nil))
    }
  }
}
