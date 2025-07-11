//
//  GlassPanel.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-09.
//


// GlassPanel.swift
import SwiftUI

struct GlassPanel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 35, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.15), .white.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 35, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
    }
}