import SwiftUI

// MARK: - View State Management
/// This class holds the animation state. Using an ObservableObject ensures the
/// state persists even if SwiftUI recreates the view struct, fixing animation glitches.
fileprivate class ViewState: ObservableObject {
    @Published var showContent = false
}

// MARK: - Main Onboarding Container
/// A view that presents a swipeable, multi-page onboarding experience with a glassmorphism design.
struct OnboardingView: View {
    /// The action to perform when the user taps the final "Get Started" button.
    let onComplete: () -> Void
    
    // Properties to track the current tab for showing the 'X' button.
    @State private var currentTab = 0
    private let lastSlideIndex = 3
    
    /// Custom initializer to style the page control dots for the TabView.
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        UIPageControl.appearance().currentPageIndicatorTintColor = .systemBlue
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.systemBlue.withAlphaComponent(0.3)
    }
    
    var body: some View {
        ZStack {
            // A monochromatic blue aurora background to reinforce the accent color.
            Color(.systemBackground)
                .ignoresSafeArea()
            
            Circle()
                .fill(Color.blue.opacity(0.8))
                .blur(radius: 150)
                .offset(x: -150, y: -200)

            Circle()
                .fill(Color.blue.opacity(0.5))
                .blur(radius: 180)
                .offset(x: 150, y: 150)
                
            // A TabView with a page style creates the swipeable carousel interface.
            TabView(selection: $currentTab) {
                // --- Slide 1: Welcome ---
                OnboardingWelcomeView(
                    slideIndex: 0,
                    currentTab: $currentTab
                )
                .tag(0)
                
                // --- Slide 2: How to Record ---
                OnboardingInstructionView(
                    slideIndex: 1,
                    currentTab: $currentTab,
                    imageNames: ["OnboardingSlide1.2", "OnboardingSlide1.1"],
                    title: "1. Record Your Smash",
                    instructions: [
                        (icon: "arrow.left.and.right.square.fill", text: "Set the camera on the sideline, facing straight across. Court lines should look parallel to the frame."),
                        (icon: "bird.fill", text: "Keep the shuttle visible — avoid glare or busy backgrounds."),
                        (icon: "video.slash.fill", text: "Use regular video. Avoid Slo-Mo or filters."),
                        (icon: "scissors", text: "Trim to just the smash — under 1 second (~10 frames).")
                    ]
                )
                .tag(1)
                
                // --- Slide 3: How to Put Reference Line ---
                OnboardingInstructionView(
                    slideIndex: 2,
                    currentTab: $currentTab,
                    imageNames: ["OnboardingSlide2.1", "OnboardingSlide2.2", "OnboardingSlide2.3"],
                    title: "2. Mark a Known Distance",
                    instructions: [
                        (icon: "scope", text: "Mark the front service line and doubles service line — 3.87 m apart."),
                        (icon: "person.fill", text: "Place the line directly under the player."),
                        (icon: "ruler.fill", text: "Keep 3.87 m unless using different lines — changing it may reduce accuracy.")
                    ]
                )
                .tag(2)
                
                // --- Slide 4: Reviewing the frames ---
                OnboardingInstructionView(
                    slideIndex: 3,
                    currentTab: $currentTab,
                    imageNames: ["OnboardingSlide3.1", "OnboardingSlide3.2"],
                    title: "3. Review Detection",
                    instructions: [
                        (icon: "arrow.left.and.right.circle.fill", text: "Use ← and → keys to step through frames and see shuttle speed per frame."),
                        (icon: "rectangle.dashed", text: "If detection is off, adjust the red box to fit the shuttle tightly."),
                        (icon: "slider.horizontal.3", text: "Use the controls below to move, resize, or fine-tune the box."),
                        (icon: "checkmark.circle.fill", text: "Most videos don’t need manual correction—just review and continue.")
                    ],
                    isLastSlide: true,
                    onComplete: onComplete
                )
                .tag(lastSlideIndex)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            
            // 'X' Button Overlay
            .overlay(alignment: .topTrailing) {
                if currentTab == lastSlideIndex {
                    Button(action: onComplete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.gray.opacity(0.8), .thinMaterial)
                            .shadow(radius: 5)
                    }
                    .padding()
                    .transition(.opacity.animation(.easeIn))
                }
            }
        }
    }
}

// MARK: - Welcome Slide
struct OnboardingWelcomeView: View {
    // Properties to track the active slide
    let slideIndex: Int
    @Binding var currentTab: Int
    
    @StateObject private var viewState = ViewState()
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 25) {
                Image("AppIconTransparent")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 5, y: 5)
                    .opacity(viewState.showContent ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: viewState.showContent)
            
                VStack(spacing: 15) {
                    Text("Welcome to")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text("Smashspeed")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                }
                .opacity(viewState.showContent ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: viewState.showContent)
                
                Text("Wanna know how fast you really smash?")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .opacity(viewState.showContent ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6), value: viewState.showContent)
            }
            .padding(.vertical, 50)
            .padding(.horizontal, 20)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
            .padding(.horizontal, 20)
            .offset(y: viewState.showContent ? 0 : -30)
            .opacity(viewState.showContent ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: viewState.showContent)
            
            Spacer()
            
            Label("Swipe to get started", systemImage: "chevron.right")
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .symbolEffect(.bounce, options: .repeating.speed(0.8))
                .opacity(viewState.showContent ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.8), value: viewState.showContent)
                .padding(.bottom, 40)
        }
        .onAppear {
            if currentTab == slideIndex {
                triggerAnimation()
            }
        }
        .onChange(of: currentTab) {
            if currentTab == slideIndex {
                triggerAnimation()
            }
        }
    }
    
    private func triggerAnimation() {
        guard !viewState.showContent else { return }
        viewState.showContent = true
    }
}

// MARK: - Instructional Slide
struct OnboardingInstructionView: View {
    // Properties to track the active slide
    let slideIndex: Int
    @Binding var currentTab: Int
    
    // Content properties
    let imageNames: [String]
    let title: String
    let instructions: [(icon: String, text: String)]
    var isLastSlide: Bool = false
    var onComplete: (() -> Void)? = nil
    
    @StateObject private var viewState = ViewState()
    @State private var imageSelection = 0
    @State private var showLeftArrow = false
    @State private var showRightArrow = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 60)
                    .opacity(viewState.showContent ? 1 : 0)
                    .offset(y: viewState.showContent ? 0 : -20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: viewState.showContent)

                VStack(spacing: 25) {
                    ZStack {
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
                        
                        HStack {
                            if showLeftArrow {
                                ArrowButton(icon: "chevron.left") {
                                    withAnimation { imageSelection -= 1 }
                                }
                            }
                            Spacer()
                            if showRightArrow {
                                ArrowButton(icon: "chevron.right") {
                                    withAnimation { imageSelection += 1 }
                                }
                            }
                        }
                        .padding(.horizontal, 15)
                    }
                    .opacity(viewState.showContent ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: viewState.showContent)
                    
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
                    .opacity(viewState.showContent ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: viewState.showContent)
                }
                .padding([.horizontal, .bottom], 30)
                .padding(.top, 10)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                .offset(y: viewState.showContent ? 0 : -30)
                .opacity(viewState.showContent ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: viewState.showContent)
                
                if isLastSlide {
                    Button("Get Started", action: { onComplete?() })
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 10)
                        .opacity(viewState.showContent ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6), value: viewState.showContent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
        }
        .onAppear {
            updateArrowVisibility()
            if currentTab == slideIndex {
                triggerAnimation()
            }
        }
        .onChange(of: currentTab) {
            if currentTab == slideIndex {
                triggerAnimation()
            }
        }
        .onChange(of: imageSelection) {
            updateArrowVisibility()
        }
    }
    
    private func triggerAnimation() {
        guard !viewState.showContent else { return }
        viewState.showContent = true
    }
    
    private func updateArrowVisibility() {
        guard imageNames.count > 1 else {
            showLeftArrow = false; showRightArrow = false; return
        }
        showLeftArrow = imageSelection > 0
        showRightArrow = imageSelection < imageNames.count - 1
    }
}

// MARK: - Reusable Arrow Button
struct ArrowButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary.opacity(0.8))
                .padding(12)
                .background(.thinMaterial)
                .clipShape(Circle())
                .shadow(radius: 5)
        }
    }
}
