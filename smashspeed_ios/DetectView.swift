import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import UIKit

extension SmashSpeedViewModel.AppState: Equatable {
    static func == (lhs: SmashSpeedViewModel.AppState, rhs: SmashSpeedViewModel.AppState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.preparing, .preparing): return true
        case (.trimming, .trimming): return true
        case (.review, .review): return true
        case (.awaitingCalibration, .awaitingCalibration): return true
        case (.processing, .processing): return true
        case (.completed, .completed): return true
        case (.error, .error): return true
        case (.limitReached, .limitReached): return true
        default: return false
        }
    }
}


struct DetectView: View {
    @StateObject private var viewModel = SmashSpeedViewModel()
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @EnvironmentObject var storeManager: StoreManager

    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var recordedVideoURL: URL?

    @State private var showInputSelector = false
    @State private var showRecordingGuide = false

    @State private var showOnboarding = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
                Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)
                
                currentView
            }
            .toolbar {
                 if case .idle = viewModel.appState {
                     ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                     ToolbarItem(placement: .navigationBarTrailing) {
                         Button(action: { showOnboarding = true }) {
                             Image(systemName: "info.circle").foregroundColor(.accentColor)
                         }
                     }
                 }
            }
            .onAppear {
                viewModel.updateSmashesLeftDisplay(isSubscribed: storeManager.isSubscribed)
            }
            .onChange(of: storeManager.isSubscribed) {
                viewModel.updateSmashesLeftDisplay(isSubscribed: storeManager.isSubscribed)
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
        .sheet(isPresented: $showRecordingGuide) { RecordingGuideView() }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(videoURL: $recordedVideoURL)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
        .sheet(isPresented: $showPaywall) { PaywallView(isPresented: $showPaywall) }
    }
    
    @ViewBuilder
    private var currentView: some View {
        switch viewModel.appState {
        case .idle:
            VStack(spacing: 20) {
                MainView(showInputSelector: $showInputSelector, showRecordingGuide: $showRecordingGuide)
                
                Text(viewModel.smashesLeftText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
                    .animation(.default, value: viewModel.smashesLeftText)
            }
            // --- THE FIX IS HERE: The .onChange closures are now correctly written ---
            .onChange(of: selectedItem) { newItem in handleVideoSelection(item: newItem) }
            .onChange(of: recordedVideoURL) { newURL in handleVideoSelection(url: newURL) }
        
        case .limitReached:
            LockedFeatureView(
                title: "Monthly Limit Reached",
                description: "You've reached your limit of free analyses for the month. Upgrade to Pro for unlimited smashes.",
                onUpgrade: {
                    showPaywall = true
                    viewModel.reset()
                }
            )
        
        case .preparing:
            ProcessingView(message: NSLocalizedString("processing_preparingVideo", comment: "Status message")) { viewModel.reset() }

        case .trimming(let videoURL):
            TrimmingView(videoURL: videoURL, onComplete: { trimmedURL in
                viewModel.videoTrimmed(url: trimmedURL)
            }, onCancel: {
                viewModel.reset()
            })

        case .review(let videoURL, let result):
            ReviewView(
                videoURL: videoURL,
                initialResult: result,
                onFinish: { editedFrames in
                    viewModel.finishReview(
                        andShowResultsFrom: editedFrames,
                        for: authViewModel.user?.uid,
                        videoURL: videoURL,
                        isSubscribed: storeManager.isSubscribed
                    )
                },
                onRecalibrate: {
                    viewModel.appState = .awaitingCalibration(videoURL)
                }
            )
            
        case .awaitingCalibration(let url):
            CalibrationView(videoURL: url, onComplete: { scaleFactor in
                viewModel.startProcessing(
                    videoURL: url,
                    scaleFactor: scaleFactor,
                    isSubscribed: storeManager.isSubscribed
                )
            }, onCancel: { viewModel.cancelCalibration() })

        case .processing:
            ProcessingView { viewModel.cancelProcessing() }

        case .completed(let speed, let angle):
            ResultView(speed: speed, angle: angle, onReset: viewModel.reset)

        case .error(let message):
            ErrorView(message: message, onReset: viewModel.reset)
        }
    }
    
    private func handleVideoSelection(item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        if !viewModel.canPerformSmash(isSubscribed: storeManager.isSubscribed) {
            viewModel.appState = .limitReached
            self.selectedItem = nil
            return
        }

        viewModel.appState = .preparing
        self.selectedItem = nil
        
        Task {
            do {
                guard let videoFile = try await item.loadTransferable(type: VideoFile.self) else {
                    viewModel.appState = .error(NSLocalizedString("error_couldNotLoadVideo", comment: "Error message"))
                    return
                }

                let url = videoFile.url
                if await isVideoLandscape(url: url) {
                    viewModel.videoSelected(url: url)
                } else {
                    viewModel.appState = .error(NSLocalizedString("error_selectLandscape", comment: "Error message"))
                }
            } catch {
                viewModel.appState = .error(NSLocalizedString("error_genericVideoSelection", comment: "Error message"))
            }
        }
    }
    
    private func handleVideoSelection(url: URL?) {
        guard let url = url else { return }

        if !viewModel.canPerformSmash(isSubscribed: storeManager.isSubscribed) {
            viewModel.appState = .limitReached
            self.recordedVideoURL = nil
            return
        }
        
        viewModel.appState = .preparing
        self.recordedVideoURL = nil
        
        Task {
            if await isVideoLandscape(url: url) {
                viewModel.videoSelected(url: url)
            } else {
                viewModel.appState = .error(NSLocalizedString("error_recordLandscape", comment: "Error message"))
            }
        }
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
                    
                    // LOCALIZED
                    Text("recordingGuide_visitWebsite")
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
                        // LOCALIZED
                        Text("recordingGuide_title")
                            .font(.title3.bold())
                            .padding(.bottom, 5)

                        Label {
                            // LOCALIZED
                            Text("recordingGuide_recorderTip")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "video.fill")
                        }

                        Label {
                            // LOCALIZED
                            Text("recordingGuide_smasherTip")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "figure.badminton")
                        }

                        Label {
                            // LOCALIZED
                            Text("recordingGuide_cameraTip")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "camera.viewfinder")
                        }

                        Label {
                            // LOCALIZED
                            Text("recordingGuide_frameRateTip")
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
            // LOCALIZED
            .navigationTitle(Text("navTitle_recordingGuide"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // LOCALIZED
                    Button("common_done") { dismiss() }
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
                    // LOCALIZED
                    Text("processing_trimmingVideo")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(40)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                .padding()
            } else {
                VStack(spacing: 20) {
                    // LOCALIZED
                    Text("trimView_title")
                        .font(.largeTitle.bold())

                    // LOCALIZED
                    Text("trimView_description")
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
                            // LOCALIZED
                            Text(String(format: NSLocalizedString("trimView_timeFormat", comment: ""), startTime))
                            Spacer()
                            // LOCALIZED
                            Text(String(format: NSLocalizedString("trimView_durationFormat", comment: ""), max(0, endTime - startTime)))
                            Spacer()
                            // LOCALIZED
                            Text(String(format: NSLocalizedString("trimView_timeFormat", comment: ""), endTime))
                        }
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal,30)

                    Spacer()

                    HStack {
                        // LOCALIZED
                        Button("common_cancel", role: .cancel, action: onCancel)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        
                        // LOCALIZED
                        Button("trimView_confirmButton") {
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
                // LOCALIZED
                .alert(Text("trimView_alert_tooLong_title"), isPresented: $showTooLongAlert) {
                    // LOCALIZED
                    Button("common_ok", role: .cancel) { }
                } message: {
                    let maxFrames = Int(0.8 * Double(frameRate))
                    // LOCALIZED
                    Text(String(format: NSLocalizedString("trimView_alert_tooLong_message", comment: ""), maxFrames))
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

// NOTE: RangeSliderView has no user-facing text to localize.

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
    @Binding var showRecordingGuide: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Button(action: { showInputSelector = true }) {
                let circle = Circle()
                ZStack {
                    circle
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    circle
                        .fill(.ultraThinMaterial)
                        .background(
                            circle
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.cyan.opacity(0.25),
                                            Color.blue.opacity(0.08)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .blur(radius: 8)
                        )

                    circle
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .white.opacity(0.65),
                                    .cyan.opacity(0.15)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                        .blendMode(.overlay)

                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 70, weight: .thin))
                        .foregroundColor(.white.opacity(0.95))
                        .shadow(radius: 5)
                }
                .frame(width: 160, height: 160)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
            }
            .clipShape(Circle())
            .buttonStyle(ScaleAndOpacityButtonStyle())

            // LOCALIZED
            Text("mainView_prompt")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)

            Button(action: { showRecordingGuide = true }) {
                // LOCALIZED
                Label("mainView_howToRecordButton", systemImage: "questionmark.circle")
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
            // LOCALIZED
            Text("inputSelector_title").font(.headline).padding(.top)
            Label {
                // LOCALIZED
                Text("inputSelector_landscapeOnlyWarning")
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.subheadline).foregroundColor(.secondary).padding(10).background(.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(spacing: 16) {
                Button {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showCamera = true }
                } label: {
                    // LOCALIZED
                    Label("inputSelector_recordNewButton", systemImage: "camera.fill").font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)

                PhotosPicker(selection: $selectedItem, matching: .videos, photoLibrary: .shared()) {
                    // LOCALIZED
                    Label("inputSelector_chooseLibraryButton", systemImage: "photo.on.rectangle.angled").font(.headline).fontWeight(.semibold).frame(maxWidth: .infinity)
                }.controlSize(.large).buttonStyle(.bordered).onChange(of: selectedItem) { isPresented = false }

            }.padding(30).background(GlassPanel()).clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        }.padding()
    }
}

struct ProcessingView: View {
    // LOCALIZED: Default message is now a key.
    var message: String = NSLocalizedString("processing_analyzingVideo", comment: "Default processing message")
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            // LOCALIZED: This now displays the localized message passed to it.
            Text(message)
                .font(.title2)
                .fontWeight(.bold)
            // LOCALIZED
            Button("common_cancel", role: .destructive, action: onCancel)
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
            // LOCALIZED
            Button("common_tryAgain", action: onReset).buttonStyle(.borderedProminent)
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
                    // LOCALIZED
                    Text("resultView_maxSpeedTitle")
                        .font(.title)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.1f", speed))
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)

                    // LOCALIZED
                    Text("resultView_speedUnit")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .offset(y: -10)

                    if let angle = angle {
                        Divider().padding(.horizontal)
                        HStack {
                            // LOCALIZED
                            Text("resultView_smashAngleLabel")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Spacer()
                            // LOCALIZED
                            Text(String(format: NSLocalizedString("resultView_angleFormat", comment: ""), angle))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal)
                    } else {
                        Divider().padding(.horizontal)
                        VStack(spacing: 5) {
                            // LOCALIZED
                            Text("resultView_angleNotCalculated")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            // LOCALIZED
                            Text("resultView_angleUnlockInfo")
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
                    // LOCALIZED
                    NavigationLink(destination: AccountView()) { Text("resultView_signInPrompt") }.padding(.top, 10)
                }

                Spacer()
                
                // LOCALIZED
                Button(action: onReset) { Label("resultView_analyzeAnotherButton", systemImage: "arrow.uturn.backward.circle") }
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
        let shareView = ShareableView(speed: self.speed, angle: self.angle)
        self.shareableImage = shareView.snapshot()
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
