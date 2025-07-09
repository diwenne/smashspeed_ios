//
//  OnboardingView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import SwiftUI

/// A view that presents a swipeable, multi-page onboarding experience to the user.
struct OnboardingView: View {
    /// The action to perform when the user taps the final "Get Started" button.
    let onComplete: () -> Void
    
    /// Custom initializer to style the page control dots for the TabView.
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        UIPageControl.appearance().currentPageIndicatorTintColor = .systemBlue
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.systemBlue.withAlphaComponent(0.3)
    }
    
    var body: some View {
        // A TabView with a page style creates the swipeable carousel interface.
        TabView {
            // --- Slide 1: Welcome ---
            OnboardingWelcomeView()
            
            // --- Slide 2: How to Record ---
            // MODIFIED: This now passes an array of image names to the view.
            OnboardingInstructionView(
                imageNames: ["OnboardingSlide1.1", "OnboardingSlide1.2"], // Add all image names you want to loop through
                title: "1. Record Your Smash",
                instructions: [
                    (
                        icon: "arrow.left.and.right.square.fill",
                        text: "Place the camera at the sideline, facing directly across the width of the court — not at an angle."
                    ),
                    (
                        icon: "bird.fill",
                        text: "Make sure the shuttle is clearly visible during the smash — avoid bright light or backgrounds that make it blend in."
                    ),
                    (
                        icon: "video.slash.fill",
                        text: "Use regular video mode. Avoid Slo-Mo or cinematic filters."
                    )
                ]
            )
            
            // --- Slide 3: How to put reference line ---
            OnboardingInstructionView(
                imageNames: ["OnboardingSlide2"], // Static image showing reference line placement
                title: "2. Mark a Known Distance",
                instructions: [
                    (
                        icon: "scope",
                        text: "Place one point on the front service line and one on the doubles flick line — 3.87 m apart."
                    ),
                    (
                        icon: "person.fill",
                        text: "Points must be aligned with the player’s position — along the same depth from the camera."
                    ),
                    (
                        icon: "ruler.fill",
                        text: "The default length is 3.87 m. Only change it if you used a different line — this may reduce accuracy."
                    )
                ]
            )
            
            // --- Slide 4: Reviewing the frames
            OnboardingInstructionView(
                imageNames: ["OnboardingSlide3"], // Static image showing frame review and box editing
                title: "3. Review Detection",
                instructions: [
                    (
                        icon: "arrow.left.and.right.circle.fill",
                        text: "Use the arrow keys to move through each frame of the video."
                    ),
                    (
                        icon: "rectangle.dashed",
                        text: "If the shuttle is detected incorrectly, adjust the red box to tightly fit around it."
                    ),
                    (
                        icon: "slider.horizontal.3",
                        text: "Use the controls below to manually move, resize, or fine-tune the red box."
                    ),
                    (
                        icon: "bolt.fill",
                        text: "If you're only interested in the smash, skip ahead to those key frames."
                    )
                ]
            )
        }
        .tabViewStyle(.page(indexDisplayMode: .always)) // Enables the paging dots
        .background(Color(.systemBackground))
        .ignoresSafeArea(.all)
    }
}

// MARK: - Welcome Slide

/// A dedicated view for the first, simple welcome slide.
struct OnboardingWelcomeView: View {
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                Text("Welcome to")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                
                Text("SmashSpeed")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            Text("Swipe to learn how to measure your smash speed.")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
        }
        .padding()
    }
}


// MARK: - Instructional Slide

/// A reusable view for a single onboarding slide that can contain a looping image carousel.
struct OnboardingInstructionView: View {
    // MODIFIED: Now takes an array of image names.
    let imageNames: [String]
    let title: String
    let instructions: [(icon: String, text: String)]
    var isLastSlide: Bool = false
    var onComplete: (() -> Void)? = nil
    
    // State to manage the automatic image cycling.
    @State private var imageSelection = 0
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Header ---
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 60)
                .padding(.bottom, 20)
                .padding(.horizontal, 15)
                .multilineTextAlignment(.center)
                
            
            // --- Image Carousel ---
            // This view now contains a TabView to loop through the images.
            TabView(selection: $imageSelection) {
                ForEach(0..<imageNames.count, id: \.self) { i in
                    Image(imageNames[i])
                        .resizable()
                        .scaledToFit()
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)) // Hide the inner page dots
            .padding(.horizontal, 15)
            .padding(.bottom, 20)
            .onReceive(timer) { _ in
                // This logic cycles the image selection.
                withAnimation {
                    imageSelection = (imageSelection + 1) % imageNames.count
                }
            }

            // --- Instructions ---
            Spacer()
            
            VStack(alignment: .leading, spacing: 20) {
                ForEach(instructions, id: \.text) { item in
                    HStack(spacing: 16) {
                        Image(systemName: item.icon)
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 30)
                        Text(item.text)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 15)
            
            Spacer()
            
            // --- Completion Button ---
            if isLastSlide {
                Button("Get Started", action: {
                    onComplete?()
                })
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 80)
            } else {
                Color.clear.frame(height: 100)
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
}
