//
//  View+Snapshot.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-13.
//

import SwiftUI

extension View {
    /// Renders the view into a `UIImage`.
    @MainActor
    func snapshot() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        // Ensure the renderer uses the device's display scale for high-quality images.
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
