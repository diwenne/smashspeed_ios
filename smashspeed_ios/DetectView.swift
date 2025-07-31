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
    @State private var showRecordingGuide = false // Added state for the new guide

    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
                Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)

                switch viewModel.appState {

                case .idle:
                    MainView(showInputSelector: $showInputSelector, showRecordingGuide: $showRecordingGuide) // Pass binding
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

                case .processing:
                    ProcessingView { viewModel.cancelProcessing() }

                case .completed(let speed, let angle):
                    ResultView(speed: speed, angle: angle, onReset: viewModel.reset)

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
        .sheet(isPresented: $showRecordingGuide) { // Added sheet for the recording guide
            RecordingGuideView()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(videoURL: $recordedVideoURL)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
    }
}

// MARK: - Recording Guide View
struct RecordingGuideView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                Circle().fill(Color.blue.opacity(0.8)).blur(radius: 120).offset(x: -120, y: -200)
                Circle().fill(Color.blue.opacity(0.5)).blur(radius: 150).offset(x: 120, y: 150)

                VStack(spacing: 20) {
                    
                    Text("For a video tutorial, visit smashspeed.ca")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 5)

                    
                    Spacer()
                    
                    Image("courtDiagram")
                        .resizable()
                        .scaledToFit()
                        .shadow(radius: 5)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 15) {
                        Text("How to Record for Best Results")
                            .font(.title3.bold())
                            .padding(.bottom, 5)

                        Label {
                            Text("**Player A (Recorder):** Stand in the side tram lines.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "video.fill")
                        }

                        Label {
                            Text("**Player B (Smasher):** Smash from the opposite half of the court.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "figure.badminton")
                        }

                        Label {
                            Text("**Camera:** Use landscape mode with 0.5x zoom to keep the shuttle in frame.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "camera.viewfinder")
                        }

                        Label {
                            Text("**Frame Rate:** 30 FPS is fine, 60 FPS is better.")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "film.stack")
                        }
                    }
                    .padding(25)
                    .background(GlassPanel())
                    .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                    .multilineTextAlignment(.leading)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Recording Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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

    @State private var frameRate: Float = 30.0
    @State private var showTooLongAlert = false

    init(videoURL: URL, onComplete: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.videoURL = videoURL
        self.onComplete = onComplete
        self.onCancel = onCancel
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        ZStack {
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

                    Text("Isolate the moment of impact. The final clip should be very short (~0.25 seconds), and the birdie should be clearly visible in each frame.")
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
                            validateAndProceed()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(endTime <= startTime)
                    }
                    .padding()
                }
                .padding(.top, 40)
                .onAppear(perform: loadVideoDetails)
                .alert("Clip Too Long", isPresented: $showTooLongAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    let maxFrames = Int(0.8 * Double(frameRate))
                    Text("Trim the clip to under 0.8s (~\(maxFrames) frames), showing only the smash. The shuttle should be visible in every frame.")
                }
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

                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return }
                self.frameRate = try await videoTrack.load(.nominalFrameRate)

            } catch {
                print("Error loading video details: \(error)")
                onCancel()
            }
        }
    }

    private func validateAndProceed() {
        let selectedDuration = endTime - startTime
        let maxDurationAllowed = 0.8

        if selectedDuration > maxDurationAllowed {
            showTooLongAlert = true
        } else {
            trimVideo()
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

private struct RangeSliderView: View {
    @Binding var startTime: Double
    @Binding var endTime: Double
    let videoDuration: Double
    let player: AVPlayer

    var body: some View {
        GeometryReader { geometry in
            if videoDuration > 0 {
                let totalWidth = geometry.size.width

                let startX = CGFloat(startTime / videoDuration) * totalWidth
                let endX = CGFloat(endTime / videoDuration) * totalWidth

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 8)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, endX - startX), height: 8)
                        .offset(x: startX)

                    HandleView()
                        .position(x: startX, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newX = value.location.x
                                    let calculatedTime = (newX / totalWidth) * videoDuration
                                    self.startTime = max(0, min(calculatedTime, self.endTime))
                                    player.seek(to: CMTime(seconds: self.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                                }
                        )

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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

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

// MARK: - Video Orientation

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
    @Binding var showRecordingGuide: Bool // Added binding
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

            // New Button for Recording Guide
            Button(action: { showRecordingGuide = true }) {
                Label("How to Record", systemImage: "questionmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 10)

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
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
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
    let angle: Double?
    let onReset: () -> Void
    @State private var shareableImage: UIImage?
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 15) {
                    Text("Maximum Speed")
                        .font(.title)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.1f", speed))
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)

                    Text("km/h")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .offset(y: -10)

                    if let angle = angle {
                        Divider().padding(.horizontal)
                        HStack {
                            Text("Smash Angle:")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.0f° downward", angle))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal)
                    } else {
                        Divider().padding(.horizontal)
                        VStack(spacing: 5) {
                            Text("Angle Not Calculated")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Smash faster than 100 km/h to unlock angle analysis.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 5)
                    }
                }
                .padding(30)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))

                if viewModel.authState != .signedIn {
                    NavigationLink(destination: AccountView()) { Text("Want to save your result? Sign In") }.padding(.top, 10)
                }

                Spacer()

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
                .padding(22)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

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
