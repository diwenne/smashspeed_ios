import SwiftUI

// MARK: - Main Onboarding Container

/// A view that presents a swipeable, multi-page onboarding experience with a glassmorphism design.
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
        ZStack {
            // 1. A monochromatic blue aurora background to reinforce the accent color.
            Color(.systemBackground).ignoresSafeArea()
            
            Circle()
                .fill(Color.blue.opacity(0.8))
                .blur(radius: 150)
                .offset(x: -150, y: -200)

            Circle()
                .fill(Color.blue.opacity(0.5))
                .blur(radius: 180)
                .offset(x: 150, y: 150)
                
            // A TabView with a page style creates the swipeable carousel interface.
            TabView {
                // --- Slide 1: Welcome ---
                OnboardingWelcomeView()
                
                // --- Slide 2: How to Record ---
                OnboardingInstructionView(
                    imageNames: ["OnboardingSlide1.1", "OnboardingSlide1.2"],
                    title: "1. Record Your Smash",
                    instructions: [
                        (icon: "arrow.left.and.right.square.fill", text: "Place the camera at the sideline, facing directly across the width of the court — not at an angle."),
                        (icon: "bird.fill", text: "Make sure the shuttle is clearly visible during the smash — avoid bright light or backgrounds that make it blend in."),
                        (icon: "video.slash.fill", text: "Use regular video mode. Avoid Slo-Mo or cinematic filters.")
                    ]
                )
                
                // --- Slide 3: How to put reference line ---
                OnboardingInstructionView(
                    imageNames: ["OnboardingSlide2"],
                    title: "2. Mark a Known Distance",
                    instructions: [
                        (icon: "scope", text: "Place one point on the front service line and one on the doubles flick line — 3.87 m apart."),
                        (icon: "person.fill", text: "Points must be aligned with the player’s position — along the same depth from the camera."),
                        (icon: "ruler.fill", text: "The default length is 3.87 m. Only change it if you used a different line — this may reduce accuracy.")
                    ]
                )
                
                // --- Slide 4: Reviewing the frames ---
                OnboardingInstructionView(
                    imageNames: ["OnboardingSlide3"],
                    title: "3. Review Detection",
                    instructions: [
                        (icon: "arrow.left.and.right.circle.fill", text: "Use the arrow keys to move through each frame of the video."),
                        (icon: "rectangle.dashed", text: "If the shuttle is detected incorrectly, adjust the red box to tightly fit around it."),
                        (icon: "slider.horizontal.3", text: "Use the controls below to manually move, resize, or fine-tune the red box."),
                        (icon: "bolt.fill", text: "If you're only interested in the smash, skip ahead to those key frames.")
                    ],
                    isLastSlide: true, // Mark this as the final slide
                    onComplete: onComplete // Pass the completion handler
                )
            }
            .tabViewStyle(.page(indexDisplayMode: .always)) // Enables the paging dots
        }
    }
}

// MARK: - Welcome Slide with Glassmorphism

struct OnboardingWelcomeView: View {
    @State private var showContent: Bool = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 25) {
                Image("AppIconTransparent")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 5, y: 5)
                    .opacity(showContent ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: showContent)
                
                VStack(spacing: 15) {
                    Text("Welcome to")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text("Smashspeed")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                }
                .opacity(showContent ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: showContent)
                
                Text("Wanna know how fast you really smash?")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .opacity(showContent ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6), value: showContent)
            }
            .padding(.vertical, 50)
            .padding(.horizontal, 20)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
            .padding(.horizontal, 20)
            // FIX: Simplified animation for a smoother effect. Removed rotation.
            .offset(y: showContent ? 0 : -30)
            .opacity(showContent ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: showContent)
            
            Spacer()
            
            Label("Swipe to get started", systemImage: "chevron.right")
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .symbolEffect(.bounce, options: .repeating.speed(0.8))
                .opacity(showContent ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.8), value: showContent)
                .padding(.bottom, 40)
        }
        .onAppear {
            if !showContent {
                showContent = true
            }
        }
    }
}

// MARK: - Instructional Slide with Glassmorphism

struct OnboardingInstructionView: View {
    let imageNames: [String]
    let title: String
    let instructions: [(icon: String, text: String)]
    var isLastSlide: Bool = false
    var onComplete: (() -> Void)? = nil
    
    @State private var showContent: Bool = false
    @State private var imageSelection = 0
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 60)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : -20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: showContent)

                VStack(spacing: 25) {
                    // FIX: Staggered animation for the content inside the panel
                    TabView(selection: $imageSelection) {
                        ForEach(0..<imageNames.count, id: \.self) { i in
                            Image(imageNames[i])
                                .resizable()
                                .scaledToFit()
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 250)
                    .opacity(showContent ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: showContent)
                    .onReceive(timer) { _ in
                        guard imageNames.count > 1 else { return }
                        withAnimation {
                            imageSelection = (imageSelection + 1) % imageNames.count
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 25) {
                        ForEach(instructions, id: \.text) { item in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: item.icon)
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 30)
                                Text(item.text)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .opacity(showContent ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: showContent)
                }
                .padding(30)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                // FIX: Simplified panel animation for a smoother effect.
                .offset(y: showContent ? 0 : -30)
                .opacity(showContent ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: showContent)
                
                if isLastSlide {
                    Button("Get Started", action: { onComplete?() })
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 10)
                        .opacity(showContent ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6), value: showContent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
        .onAppear {
            if !showContent {
                showContent = true
            }
        }
    }
}

