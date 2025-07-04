//
//  OnboardingView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import SwiftUI

struct OnboardingView: View {
    // The action to perform when the user taps the final button.
    let onComplete: () -> Void
    
    var body: some View {
        // A TabView with a page style creates a swipeable carousel.
        TabView {
            // Slide 1: Welcome
            OnboardingSlideView(
                imageName: "bolt.circle.fill",
                title: "Welcome to SmashSpeed",
                description: "The easiest way to measure the speed of your badminton smash."
            )
            
            // Slide 2: Select Video
            OnboardingSlideView(
                imageName: "1.circle.fill",
                title: "Step 1: Select a Video",
                description: "Choose a clear, stable video of the smash you want to analyze from your photo library."
            )
            
            // Slide 3: Calibrate
            OnboardingSlideView(
                imageName: "2.circle.fill",
                title: "Step 2: Calibrate Distance",
                description: "To get an accurate reading, enter the real-world width (in meters) that the video frame covers."
            )
            
            // Slide 4: Review and Save
            OnboardingSlideView(
                imageName: "3.circle.fill",
                title: "Step 3: Review & Save",
                description: "Review the frame-by-frame analysis, make adjustments if needed, and save the result to your history.",
                isLastSlide: true,
                onComplete: onComplete // Pass the completion handler to the last slide
            )
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
    }
}

// A reusable view for a single onboarding slide.
struct OnboardingSlideView: View {
    let imageName: String
    let title: String
    let description: String
    var isLastSlide: Bool = false
    var onComplete: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: imageName)
                .font(.system(size: 100))
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(description)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            if isLastSlide {
                Button("Get Started", action: {
                    onComplete?()
                })
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 60)
            }
        }
    }
}
