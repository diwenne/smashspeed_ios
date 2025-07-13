import SwiftUI
import PhotosUI

// This Equatable extension matches the simplified AppState
extension SmashSpeedViewModel.AppState: Equatable {
    static func == (lhs: SmashSpeedViewModel.AppState, rhs: SmashSpeedViewModel.AppState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.review, .review): return true
        case (.awaitingCalibration, .awaitingCalibration): return true
        case (.processing, .processing): return true
        case (.completed, .completed): return true
        case (.error, .error): return true
        default: return false
        }
    }
}

struct DetectView: View {
    @StateObject private var viewModel = SmashSpeedViewModel()
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    // State variables for the input methods
    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var recordedVideoURL: URL?
    
    // State to control our custom pop-up menu
    @State private var showInputSelector = false
    
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            // ZStack to hold the glassmorphism background
            ZStack {
                // 1. A monochromatic blue aurora background to match other views.
                Color(.systemBackground).ignoresSafeArea()
                
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .blur(radius: 150)
                    .offset(x: -150, y: -200)

                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .blur(radius: 180)
                    .offset(x: 150, y: 150)

                // Main content switcher
                switch viewModel.appState {
                
                case .idle:
                    MainView(showInputSelector: $showInputSelector)
                        .onChange(of: selectedItem) { _, newItem in
                            Task {
                                if let item = newItem,
                                   let videoFile = try? await item.loadTransferable(type: VideoFile.self) {
                                    viewModel.videoSelected(url: videoFile.url)
                                    selectedItem = nil
                                }
                            }
                        }
                        .onChange(of: recordedVideoURL) { _, newURL in
                            if let url = newURL {
                                viewModel.videoSelected(url: url)
                                recordedVideoURL = nil
                            }
                        }
                        .navigationTitle("Detect")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button(action: { showOnboarding = true }) {
                                    Image(systemName: "info.circle").foregroundColor(.accentColor)
                                }
                            }
                        }
                
                case .review(let videoURL, let result):
                    ReviewView(videoURL: videoURL, initialResult: result) { editedFrames in
                        viewModel.finishReview(andShowResultsFrom: editedFrames, for: authViewModel.user?.uid, videoURL: videoURL)
                    }
                case .awaitingCalibration(let url):
                    CalibrationView(videoURL: url, onComplete: { scaleFactor in
                        viewModel.startProcessing(videoURL: url, scaleFactor: scaleFactor)
                    }, onCancel: { viewModel.cancelCalibration() })
                case .processing(let progress):
                    ProcessingView(progress: progress) { viewModel.cancelProcessing() }
                case .completed(let speed):
                    ResultView(speed: speed, onReset: viewModel.reset)
                case .error(let message):
                    ErrorView(message: message, onReset: viewModel.reset)
                }
            }
        }
        .sheet(isPresented: $showInputSelector) {
            InputSourceSelectorView(
                isPresented: $showInputSelector,
                showCamera: $showCamera,
                selectedItem: $selectedItem
            )
            .presentationDetents([.height(220)])
            // Make the sheet background clear to see the aurora behind it
            .background(ClearBackgroundView())
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(videoURL: $recordedVideoURL)
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
    }
}

// MARK: - Subviews for DetectView

struct MainView: View {
    @Binding var showInputSelector: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Button(action: {
                showInputSelector = true
            }) {
                ZStack {
                    // The glass effect is created using a Circle shape directly.
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .white.opacity(0.05), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                        .frame(width: 160, height: 160)
                    
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 70, weight: .thin))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(radius: 5)
                }
            }
            .clipShape(Circle())
            .buttonStyle(ScaleAndOpacityButtonStyle())
            
            Text("Select a video to begin")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)

            Spacer()
        }
    }
}

struct InputSourceSelectorView: View {
    @Binding var isPresented: Bool
    @Binding var showCamera: Bool
    @Binding var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 20) {
            Text("Analyze a Smash")
                .font(.headline)
                .padding(.top)

            // Buttons are now on a glass panel
            VStack(spacing: 16) {
                Button {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showCamera = true
                    }
                } label: {
                    Label("Record New Video", systemImage: "camera.fill")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .onChange(of: selectedItem) { _, _ in
                    isPresented = false
                }
            }
            .padding(30)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        }
        .padding()
    }
}


struct ProcessingView: View {
    let progress: Progress
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Analyzing Video...")
                .font(.title2)
                .fontWeight(.bold)
            
            ProgressView(value: progress.fractionCompleted) {
                Text("\(Int(progress.fractionCompleted * 100))%")
            }
            .padding(.horizontal, 40)
            
            Button("Cancel", role: .destructive, action: onCancel)
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
    }
}


struct ResultView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    
    let speed: Double
    let onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 20) {
                Text("Maximum Speed")
                    .font(.title)
                    .foregroundColor(.secondary)
            
                Text(String(format: "%.1f", speed))
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
            
                Text("km/h")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                if viewModel.authState != .signedIn {
                    NavigationLink(destination: AccountView()) {
                        Text("Want to save your result? Sign In")
                    }
                    .padding(.top, 10)
                }
            }
            .padding(40)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
            
            Button(action: onReset) {
                Label("Analyze Another Video", systemImage: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
    }
}

struct ErrorView: View {
    let message: String
    let onReset: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            
            Text(message)
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Try Again", action: onReset)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
    }
}

// MARK: - Reusable Helper Views
// NOTE: These components should be in their own separate files for best practice.

/// A custom button style that scales the content down and reduces opacity when pressed.
struct ScaleAndOpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A helper view to make a sheet's background clear.
struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        return ClearBackgroundUIView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private class ClearBackgroundUIView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            superview?.superview?.backgroundColor = .clear
        }
    }
}
