//
//  VersionChecker.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-26.
//

import Foundation
import FirebaseRemoteConfig

@MainActor
class VersionChecker: ObservableObject {
    @Published var needsForceUpdate = false
    private var remoteConfig: RemoteConfig
    
    init() {
        self.remoteConfig = RemoteConfig.remoteConfig()
        
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #endif
        self.remoteConfig.configSettings = settings
        
        self.remoteConfig.setDefaults(["minimum_required_version": "1.0.0" as NSObject])
    }
    
    func checkVersion() async {
        guard let currentVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            print("🚨 Version Check Error: Could not read the app's current version from the bundle.")
            return
        }
        
        do {
            let status = try await remoteConfig.fetchAndActivate()
            
            if status == .successFetchedFromRemote || status == .successUsingPreFetchedData {
                let minimumVersionString = remoteConfig.configValue(forKey: "minimum_required_version").stringValue
                
                // --- ❗️ ADDED DEBUG PRINTS ---
                #if DEBUG
                print("--- Version Check ---")
                print("📲 App Version (Current): \(currentVersionString)")
                print("☁️ Firebase (Required): \(minimumVersionString ?? "Not Found")")
                #endif
                
                if isVersion(currentVersionString, olderThan: minimumVersionString ?? "999.0.0") {
                    self.needsForceUpdate = true
                }
            }
        } catch {
            print("🚨 Version Check Error: Error fetching Remote Config: \(error.localizedDescription)")
        }
    }
    
    private func isVersion(_ versionA: String, olderThan versionB: String) -> Bool {
        let componentsA = versionA.split(separator: ".").map { Int($0) ?? 0 }
        let componentsB = versionB.split(separator: ".").map { Int($0) ?? 0 }
        let maxCount = max(componentsA.count, componentsB.count)
        
        for i in 0..<maxCount {
            let valA = i < componentsA.count ? componentsA[i] : 0
            let valB = i < componentsB.count ? componentsB[i] : 0
            
            if valA < valB { return true }
            if valA > valB { return false }
        }
        return false
    }
}
