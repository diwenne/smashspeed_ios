import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

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
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var recordedVideoURL: URL?
    
    @State private var showInputSelector = false
    
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
                Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)

                switch viewModel.appState {
                
                case .idle:
                    MainView(showInputSelector: $showInputSelector)
                        // ✅ MODIFIED: This logic now directly imports the video without trimming.
                        .onChange(of: selectedItem) {
                            Task {
                                guard let item = selectedItem else { return }
                                selectedItem = nil // Clear selection
                                
                                do {
                                    guard let videoFile = try await item.loadTransferable(type: VideoFile.self) else {
                                        viewModel.appState = .error("Could not load the selected video.")
                                        return
                                    }
                                    
                                    let url = videoFile.url
                                    if await isVideoLandscape(url: url) {
                                        viewModel.videoSelected(url: url)
                                    } else {
                                        viewModel.appState = .error("Please select a landscape video. Portrait videos are not supported.")
                                    }
                                } catch {
                                    viewModel.appState = .error("An error occurred while selecting the video.")
                                }
                            }
                        }
                        .onChange(of: recordedVideoURL) {
                            guard let url = recordedVideoURL else { return }
                            Task {
                                if await isVideoLandscape(url: url) {
                                    viewModel.videoSelected(url: url)
                                } else {
                                    viewModel.appState = .error("Please record in landscape mode. Portrait videos are not supported.")
                                }
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
            .presentationDetents([.height(260)])
            .background(ClearBackgroundView())
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(videoURL: $recordedVideoURL)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
    }
}


// MARK: - Video Orientation Helper
private func isVideoLandscape(url: URL) async -> Bool {
    let asset = AVAsset(url: url)
    guard let tracks = try? await asset.load(.tracks) else { return false }
    guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else { return false }
    guard let size = try? await videoTrack.load(.naturalSize) else { return false }
    guard let transform = try? await videoTrack.load(.preferredTransform) else { return size.width >= size.height }
    let sizeWithTransform = size.applying(transform)
    return abs(sizeWithTransform.width) >= abs(sizeWithTransform.height)
}


// MARK: - Subviews for DetectView (Main, InputSource, Processing, Error)
struct MainView: View {
    @Binding var showInputSelector: Bool
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Button(action: { showInputSelector = true }) {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                        .overlay(LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                        .frame(width: 160, height: 160)
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 70, weight: .thin)).foregroundColor(.white.opacity(0.8)).shadow(radius: 5)
                }
            }.clipShape(Circle()).buttonStyle(ScaleAndOpacityButtonStyle())
            Text("Select a video to begin").font(.headline).fontWeight(.semibold).foregroundColor(.secondary).shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            Spacer()
        }
    }
}

struct InputSourceSelectorView: View {
    @Binding var isPresented: Bool
    @Binding var showCamera: Bool
    @Binding var selectedItem: PhotosPickerItem?
    var body: some View {
        VStack(spacing: 15) {
            Text("Analyze a Smash").font(.headline).padding(.top)
            Label {
                Text("Only landscape videos are supported.")
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.subheadline).foregroundColor(.secondary).padding(10).background(.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(spacing: 16) {
                Button {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showCamera = true }
                } label: { Label("Record New Video", systemImage: "camera.fill").font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity) }
                .controlSize(.large).buttonStyle(.borderedProminent)
                
                PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle.angled").font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity)
                }.controlSize(.large).buttonStyle(.bordered).onChange(of: selectedItem) { isPresented = false }

            }.padding(30).background(GlassPanel()).clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        }.padding()
    }
}

struct ProcessingView: View {
    let progress: Progress
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Analyzing Video...").font(.title2).fontWeight(.bold)
            ProgressView(value: progress.fractionCompleted) { Text("\(Int(progress.fractionCompleted * 100))%") }.padding(.horizontal, 40)
            Button("Cancel", role: .destructive, action: onCancel)
        }.padding(40).background(GlassPanel()).clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous)).padding()
    }
}

struct ErrorView: View {
    let message: String
    let onReset: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.red)
            Text(message).multilineTextAlignment(.center).padding()
            Button("Try Again", action: onReset).buttonStyle(.borderedProminent)
        }.padding(40).background(GlassPanel()).clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous)).padding()
    }
}

// MARK: - Result View & Sharing Components
struct ResultView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    let speed: Double
    let onReset: () -> Void
    @State private var shareableImage: UIImage?
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                VStack(spacing: 20) {
                    Text("Maximum Speed").font(.title).foregroundColor(.secondary)
                    Text(String(format: "%.1f", speed)).font(.system(size: 80, weight: .bold, design: .rounded)).foregroundColor(.accentColor)
                    Text("km/h").font(.title2).foregroundColor(.secondary)
                    if viewModel.authState != .signedIn {
                        NavigationLink(destination: AccountView()) { Text("Want to save your result? Sign In") }.padding(.top, 10)
                    }
                }
                .padding(40).background(GlassPanel()).clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                Button(action: onReset) { Label("Analyze Another Video", systemImage: "arrow.uturn.backward.circle") }
                .buttonStyle(.bordered).controlSize(.large)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: renderImageForSharing) { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(item: $shareableImage) { image in
                SharePreviewView(image: image)
            }
        }
    }
    
    @MainActor
    private func renderImageForSharing() {
        let shareView = ShareableView(speed: self.speed)
        self.shareableImage = shareView.snapshot()
    }
}

struct SharePreviewView: View {
    @Environment(\.dismiss) var dismiss
    let image: UIImage
    @State private var showShareSheet = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Shareable Image Preview").font(.headline)
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.2), radius: 8)
                Spacer()
                Button { showShareSheet = true } label: {
                    Label("Share Now", systemImage: "square.and.arrow.up").fontWeight(.bold).frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showShareSheet) { ShareSheet(activityItems: [image]) }
        }
    }
}

struct ShareableView: View {
    let speed: Double
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Circle().fill(Color.blue.opacity(0.8)).blur(radius: 120).offset(x: -120, y: -200)
            Circle().fill(Color.blue.opacity(0.5)).blur(radius: 150).offset(x: 120, y: 150)
            VStack(spacing: 16) {
                AppLogoView().scaleEffect(0.95).padding(.top, 20)
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", speed)).font(.system(size: 80, weight: .heavy, design: .rounded)).foregroundColor(.accentColor)
                    Text("km/h").font(.title2).fontWeight(.medium).foregroundColor(.secondary)
                }
                .padding(22).background(GlassPanel()).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                VStack(spacing: 2) {
                    Text("How fast do you smash?").font(.headline).fontWeight(.semibold)
                    Text("Download Smashspeed to find out!").font(.subheadline).fontWeight(.regular).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center).padding(.top, 10)
                VStack(spacing: 1) {
                    Text("Generated by Smashspeed").font(.caption2).fontWeight(.medium).foregroundColor(.secondary.opacity(0.8))
                    Text("@smashspeedai").font(.caption2).fontWeight(.medium).foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: 320).padding(.vertical, 40)
        }
        .frame(width: 414, height: 736)
    }
}

// MARK: - Reusable Helper Views & Extensions
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: activityItems, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
extension UIImage: Identifiable {
    public var id: String { return UUID().uuidString }
}
extension View {
    @MainActor func snapshot() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
struct ScaleAndOpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1.0).opacity(configuration.isPressed ? 0.8 : 1.0).animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { ClearBackgroundUIView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
    private class ClearBackgroundUIView: UIView {
        override func layoutSubviews() { super.layoutSubviews(); superview?.superview?.backgroundColor = .clear }
    }
}
