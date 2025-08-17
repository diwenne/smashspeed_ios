//
//  LanguageManager.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-08-16.
//


import SwiftUI

// An ObservableObject to manage and store the current language setting.
final class LanguageManager: ObservableObject {
    @AppStorage("selectedLanguage") var languageCode: String = "en"
}