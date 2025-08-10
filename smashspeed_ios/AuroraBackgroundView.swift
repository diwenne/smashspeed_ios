//
//  AuroraBackgroundView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-08-02.
//


import SwiftUI

// This is the main view that will display your background effect.
struct AuroraBackgroundView: View {
    var body: some View {
        // ZStack allows you to layer views on top of each other.
        ZStack {
            // 1. A base background color that respects light/dark mode.
            //    .ignoresSafeArea() makes it fill the entire screen.
            Color(.systemBackground).ignoresSafeArea()

            // 2. The first blurred circle, positioned top-left.
            Circle()
                .fill(Color.blue.opacity(0.8))
                .blur(radius: 150)
                .offset(x: -150, y: -200)

            // 3. The second blurred circle, positioned bottom-right.
            Circle()
                .fill(Color.blue.opacity(0.5))
                .blur(radius: 180)
                .offset(x: 150, y: 150)
        }
    }
}

// This is a helper to show a live preview in Xcode's canvas.
struct AuroraBackgroundView_Previews: PreviewProvider {
    static var previews: some View {
        AuroraBackgroundView()
    }
}
