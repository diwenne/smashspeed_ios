//
//  GlassPanel.swift
//  smashspeed_ios
//
//  Frosty (icy) glassmorphism — visual-only
//

import SwiftUI

public struct GlassPanel: View {
    public enum Preset {
        case icy                 // frosty blue/white (default)
        case neutral             // desaturated clear/white
        case custom(tint: Color) // supply any tint
    }

    public var cornerRadius: CGFloat
    public var shadowOpacity: Double
    public var preset: Preset

    // Backwards-compatible init (defaults to icy look)
    public init(
        cornerRadius: CGFloat = 28,
        shadowOpacity: Double = 0.18,
        preset: Preset = .icy
    ) {
        self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity
        self.preset = preset
    }

    // MARK: - Palette
    private var baseTintA: Color {
        switch preset {
        case .icy:     return Color.white.opacity(0.40)
        case .neutral: return Color.white.opacity(0.32)
        case .custom:  return Color.white.opacity(0.36)
        }
    }
    private var baseTintB: Color {
        switch preset {
        case .icy:     return Color.white.opacity(0.20)
        case .neutral: return Color.white.opacity(0.14)
        case .custom:  return Color.white.opacity(0.16)
        }
    }
    private var accentA: Color {
        switch preset {
        case .icy:     return Color.cyan.opacity(0.25)
        case .neutral: return Color.white.opacity(0.10)
        case .custom:  return Color.white.opacity(0.15)
        }
    }
    private var accentB: Color {
        switch preset {
        case .icy:     return Color.blue.opacity(0.08)
        case .neutral: return Color.clear
        case .custom:  return Color.clear
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // 1) Bright frosty base so it never looks dark over a dark bg
            shape
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [baseTintA, baseTintB]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 2) Frosted blur + cool tint wash for color coherence
            shape
                .fill(.ultraThinMaterial)
                .background(
                    shape
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [accentA, accentB]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: 8)
                )

            // 3) Subtle inner highlight (light bleed)
            shape
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.65),
                            .white.opacity(0.12)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.3
                )
                .blendMode(.overlay)

            // 4) Gentle rim glow for realism
            shape
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .white.opacity(0.9), .clear,
                            .white.opacity(0.6), .clear,
                            .white.opacity(0.8), .clear
                        ]),
                        center: .center
                    ),
                    lineWidth: 0.9
                )
                .blur(radius: 1.2)
        }
        // Depth
        .shadow(color: .black.opacity(shadowOpacity), radius: 20, x: 0, y: 12)
        .shadow(color: .black.opacity(shadowOpacity * 0.6), radius: 8, x: 0, y: 4)
    }
}
