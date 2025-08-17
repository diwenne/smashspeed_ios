//
//  LanguagePickerView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-08-16.
//


import SwiftUI

struct LanguagePickerView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.dismiss) var dismiss

    // Add all the languages you support here
    let languages: [(code: String, name: String)] = [
        ("en", "English"),
        ("fr", "Français (French)"),
        ("vi", "Tiếng Việt (Vietnamese)"),
        ("ms", "Bahasa Melayu (Malay)"),
        ("th", "ไทย (Thai)"),
        ("id", "Bahasa Indonesia (Indonesian)"),
        ("fil", "Filipino (Tagalog)"),
        ("km", "ភាសាខ្មែរ (Khmer)"),
        ("zh-Hant", "繁體中文 (Traditional Chinese)"),
        ("de", "Deutsch (German)"),
        ("zh-Hans", "简体中文 (Simplified Chinese)"),
        ("ja", "日本語 (Japanese)"),
        ("da", "Dansk (Danish)"),
        ("es", "Español (Spanish)"),
        ("ko", "한국어 (Korean)")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(languages, id: \.code) { language in
                    Button(action: {
                        languageManager.languageCode = language.code
                        dismiss()
                    }) {
                        HStack {
                            Text(language.name)
                            Spacer()
                            if languageManager.languageCode == language.code {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle(Text("account_menu_changeLanguage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common_done") { dismiss() }
                }
            }
        }
    }
}