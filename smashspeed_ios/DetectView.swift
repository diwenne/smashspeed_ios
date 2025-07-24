import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import UIKit

// This Equatable extension matches the simplified AppState
extension SmashSpeedViewModel.AppState: Equatable {
    static func == (lhs: SmashSpeedViewModel.AppState, rhs: SmashSpeedViewModel.AppState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.trimming, .trimming): return true
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
                        .onChange(of: selectedItem) {
                            Task {
                                guard let item = selectedItem else { return }
                                selectedItem = nil
                                
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
                
                case .trimming(let videoURL):
                    TrimmingView(videoURL: videoURL, onComplete: { trimmedURL in
                        viewModel.videoTrimmed(url: trimmedURL)
                    }, onCancel: {
                        viewModel.reset()
                    })

                case .review(let videoURL, let result):
                    ReviewView(videoURL: videoURL, initialResult: result) { editedFrames in
                        viewModel.finishReview(andShowResultsFrom: editedFrames, for: authViewModel.user?.uid, videoURL: videoURL)
                    }
                case .awaitingCalibration(let url):
                    CalibrationView(videoURL: url, onComplete: { scaleFactor in
                        viewModel.startProcessing(videoURL: url, scaleFactor: scaleFactor)
                    }, onCancel: { viewModel.cancelCalibration() })
                
                // --- MODIFIED ---
                // The `processing` case no longer receives a `Progress` object.
                case .processing:
                    ProcessingView { viewModel.cancelProcessing() }
                    
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

// MARK: - Trimming View
struct TrimmingView: View {
    let videoURL: URL
    let onComplete: (URL) -> Void
    let onCancel: () -> Void
    
    @State private var player: AVPlayer
    @State private var videoDuration: Double = 0.0
    @State private var startTime: Double = 0.0
    @State private var endTime: Double = 0.0
    @State private var isExporting = false

    init(videoURL: URL, onComplete: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.videoURL = videoURL
        self.onComplete = onComplete
        self.onCancel = onCancel
        _player = State(initialValue: AVPlayer(url: videoURL))
    }
    
    var body: some View {
        ZStack {
            
            // --- MODIFIED ---
            // This now shows a loading view consistent with the ProcessingView.
            if isExporting {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Trimming Video...")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(40)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                .padding()
            } else {
                VStack(spacing: 20) {
                    Text("Trim to the Smash")
                        .font(.largeTitle.bold())
                    
                    Text("Isolate the moment of impact. The final clip should be very short (~0.5 seconds, ~10 frames), and the birdie should be clearly visible in each frame.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VideoPlayer(player: player)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 8)
                        .padding(.horizontal)
                        .onAppear { player.play() }

                    VStack {
                        RangeSliderView(
                            startTime: $startTime,
                            endTime: $endTime,
                            videoDuration: videoDuration,
                            player: player
                        )
                        .frame(height: 60)
                        
                        HStack {
                            Text(String(format: "%.2fs", startTime))
                            Spacer()
                            Text("Selected Duration: \(max(0, endTime - startTime), specifier: "%.2f")s")
                            Spacer()
                            Text(String(format: "%.2fs", endTime))
                        }
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal,30)
                    
                    Spacer()
                    
                    HStack {
                        Button("Cancel", role: .cancel, action: onCancel)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        
                        Button("Confirm Trim") {
                            trimVideo()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(endTime <= startTime)
                    }
                    .padding()
                }
                .padding(.top, 40)
                .onAppear(perform: loadVideoDetails)
            }
        }
    }

    private func loadVideoDetails() {
        Task {
            let asset = AVURLAsset(url: videoURL)
            do {
                let duration = try await asset.load(.duration)
                let durationInSeconds = CMTimeGetSeconds(duration)
                self.videoDuration = durationInSeconds
                self.endTime = durationInSeconds
            } catch {
                print("Error loading video duration: \(error)")
                onCancel()
            }
        }
    }
    
    private func trimVideo() {
        player.pause()
        isExporting = true
        
        let asset = AVURLAsset(url: videoURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            isExporting = false; return
        }
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        
        let startTime = CMTime(seconds: self.startTime, preferredTimescale: 600)
        let endTime = CMTime(seconds: self.endTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed, let url = exportSession.outputURL {
                    onComplete(url)
                } else {
                    print("Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                    onCancel()
                }
                isExporting = false
            }
        }
    }
}

// ✅ REBUILT: This custom range slider is now more robust and uses absolute positions.
private struct RangeSliderView: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let videoDuration: Double
    let player: AVPlayer

    var body: some View {
        GeometryReader { geometry in
            // Guard against videoDuration being zero to prevent division errors
            if videoDuration > 0 {
                let totalWidth = geometry.size.width
                
                // Calculate the absolute X position for start and end handles
                let startX = CGFloat(startTime / videoDuration) * totalWidth
                let endX = CGFloat(endTime / videoDuration) * totalWidth

                ZStack(alignment: .leading) {
                    // Background Track
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 8)
                    
                    // Selected Range Track
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, endX - startX), height: 8)
                        .offset(x: startX)

                    // Start Handle
                    HandleView()
                        .position(x: startX, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    // Use the drag gesture's direct location
                                    let newX = value.location.x
                                    let calculatedTime = (newX / totalWidth) * videoDuration
                                    // Clamp the value to prevent errors
                                    self.startTime = max(0, min(calculatedTime, self.endTime))
                                    // Seek the player for live preview
                                    player.seek(to: CMTime(seconds: self.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                                }
                        )
                    
                    // End Handle
                    HandleView()
                        .position(x: endX, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newX = value.location.x
                                    let calculatedTime = (newX / totalWidth) * videoDuration
                                    self.endTime = min(videoDuration, max(calculatedTime, self.startTime))
                                    player.seek(to: CMTime(seconds: self.endTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                                }
                        )
                }
            } else {
                // Show a placeholder while the duration is loading
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // Helper view for the draggable circles
    private struct HandleView: View {
        var body: some View {
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .shadow(radius: 3)
                .overlay(
                    Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                )
        }
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

// --- MODIFIED ---
// This view no longer uses a percentage-based progress bar.
struct ProcessingView: View {
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            ProgressView() // Use a simple, indeterminate progress view
                .scaleEffect(1.5)
            Text("Analyzing Video...")
                .font(.title2)
                .fontWeight(.bold)
            Button("Cancel", role: .destructive, action: onCancel)
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
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
