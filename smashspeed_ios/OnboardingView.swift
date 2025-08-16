import SwiftUI

// MARK: - View State Management
fileprivate class ViewState: ObservableObject {
    @Published var showContent = false
}

// MARK: - Main Onboarding Container
struct OnboardingView: View {
    let onComplete: () -> Void
    
    @State private var currentTab = 0
    private let lastSlideIndex = 3
    
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        UIPageControl.appearance().currentPageIndicatorTintColor = .systemBlue
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.systemBlue.withAlphaComponent(0.3)
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
            Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)
                
            TabView(selection: $currentTab) {
                OnboardingWelcomeView(
                    slideIndex: 0,
                    currentTab: $currentTab
                )
                .tag(0)
                
                // LOCALIZED: The title and instructions now use keys.
                OnboardingInstructionView(
                    slideIndex: 1,
                    currentTab: $currentTab,
                    imageNames: ["OnboardingSlide1.2", "OnboardingSlide1.1"],
                    titleKey: "onboarding_slide1_title",
                    instructions: [
                        (icon: "arrow.left.and.right.square.fill", textKey: "onboarding_slide1_instruction1"),
                        (icon: "bird.fill", textKey: "onboarding_slide1_instruction2"),
                        (icon: "video.slash.fill", textKey: "onboarding_slide1_instruction3"),
                        (icon: "scissors", textKey: "onboarding_slide1_instruction4")
                    ]
                )
                .tag(1)
                
                // LOCALIZED: The title and instructions now use keys.
                OnboardingInstructionView(
                    slideIndex: 2,
                    currentTab: $currentTab,
                    imageNames: ["OnboardingSlide2.1", "OnboardingSlide2.2", "OnboardingSlide2.3"],
                    titleKey: "onboarding_slide2_title",
                    instructions: [
                        (icon: "scope", textKey: "onboarding_slide2_instruction1"),
                        (icon: "person.fill", textKey: "onboarding_slide2_instruction2"),
                        (icon: "ruler.fill", textKey: "onboarding_slide2_instruction3")
                    ]
                )
                .tag(2)
                
                // LOCALIZED: The title and instructions now use keys.
                OnboardingInstructionView(
                    slideIndex: 3,
                    currentTab: $currentTab,
                    imageNames: ["OnboardingSlide3.1", "OnboardingSlide3.2"],
                    titleKey: "onboarding_slide3_title",
                    instructions: [
                        (icon: "arrow.left.and.right.circle.fill", textKey: "onboarding_slide3_instruction1"),
                        (icon: "rectangle.dashed", textKey: "onboarding_slide3_instruction2"),
                        (icon: "slider.horizontal.3", textKey: "onboarding_slide3_instruction3"),
                        (icon: "checkmark.circle.fill", textKey: "onboarding_slide3_instruction4")
                    ],
                    isLastSlide: true,
                    onComplete: onComplete
                )
                .tag(lastSlideIndex)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
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
                    // LOCALIZED
                    Text("onboarding_welcome_title")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    // LOCALIZED
                    Text("onboarding_welcome_brand")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                }
                .opacity(viewState.showContent ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: viewState.showContent)
                
                // LOCALIZED
                Text("onboarding_welcome_prompt")
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
            
            // LOCALIZED
            Label("onboarding_swipePrompt", systemImage: "chevron.right")
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
// LOCALIZED: Modified this struct to accept localization keys.
struct OnboardingInstructionView: View {
    let slideIndex: Int
    @Binding var currentTab: Int
    
    let imageNames: [String]
    let titleKey: LocalizedStringKey
    let instructions: [(icon: String, textKey: LocalizedStringKey)]
    var isLastSlide: Bool = false
    var onComplete: (() -> Void)? = nil
    
    @StateObject private var viewState = ViewState()
    @State private var imageSelection = 0
    @State private var showLeftArrow = false
    @State private var showRightArrow = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // LOCALIZED
                Text(titleKey)
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
                        // LOCALIZED
                        ForEach(instructions, id: \.icon) { item in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: item.icon)
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 30)
                                Text(item.textKey)
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
                    // LOCALIZED
                    Button("onboarding_getStartedButton", action: { onComplete?() })
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
