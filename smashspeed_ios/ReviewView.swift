import SwiftUI
import AVFoundation
import Vision
import StoreKit
import UIKit

// MARK: - Main Review View
struct ReviewView: View {
    let videoURL: URL
    let initialResult: VideoAnalysisResult
    let onFinish: ([FrameAnalysis]) -> Void
    let onRecalibrate: () -> Void

    enum EditMode { case move, resize }

    @Environment(\.requestReview) var requestReview

    @State private var analysisResults: [FrameAnalysis]
    @State private var currentIndex = 0
    @State private var currentFrameImage: UIImage?
    @State private var editMode: EditMode = .move

    @State private var showInfoSheet: Bool = false
    @State private var showTuningControls = false
    @State private var showInterpolationInfo = false
    @State private var showManualInfo = false
    @State private var showSpeedInfoAlert = false
    @State private var showInterpolationFeedback = false

    @AppStorage("didShowInitialReviewGuidance") private var didShowInitialReviewGuidance: Bool = false
    @State private var showInitialGuidance: Bool = false

    @State private var undoStack: [[FrameAnalysis]] = []
    @State private var redoStack: [[FrameAnalysis]] = []

    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    @State private var viewportSize: CGSize = .zero

    private let imageGenerator: AVAssetImageGenerator

    init(videoURL: URL, initialResult: VideoAnalysisResult, onFinish: @escaping ([FrameAnalysis]) -> Void, onRecalibrate: @escaping () -> Void) {
        self.videoURL = videoURL
        self.initialResult = initialResult
        self._analysisResults = State(initialValue: initialResult.frameData)
        self.onFinish = onFinish
        self.onRecalibrate = onRecalibrate
        
        let asset = AVURLAsset(url: videoURL)
        self.imageGenerator = AVAssetImageGenerator(asset: asset)
        self.imageGenerator.appliesPreferredTrackTransform = true
        self.imageGenerator.requestedTimeToleranceBefore = .zero
        self.imageGenerator.requestedTimeToleranceAfter = .zero
    }

    private var frameIndexBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(self.currentIndex) },
            set: {
                let oldValue = self.currentIndex
                let newValue = Int($0)
                if oldValue != newValue {
                    self.currentIndex = newValue
                    triggerHapticFeedback(style: .light)
                }
            }
        )
    }

    private var currentOffset: CGSize {
        return CGSize(width: committedOffset.width + dragOffset.width, height: committedOffset.height + dragOffset.height)
    }
    private var currentScale: CGFloat {
        return scale * magnifyBy
    }

    private var isInterpolationRecommended: Bool {
        guard analysisResults.count > 2 else { return false }
        var inGap = false
        for i in 0..<analysisResults.count - 1 {
            let currentHasBox = analysisResults[i].boundingBox != nil
            let nextHasBox = analysisResults[i+1].boundingBox != nil
            if currentHasBox && !nextHasBox {
                inGap = true
            }
            if inGap && nextHasBox {
                return true
            }
        }
        return false
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
            Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)

            VStack(spacing: 0) {
                topBar
                frameDisplay
                interpolationSection

                ScrollView {
                    VStack(spacing: 25) {
                        frameNavigationControls
                        if showTuningControls {
                            manualAdjustmentControls
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)

                VStack(spacing: 12) {
                    // LOCALIZED
                    Button("review_finishButton") {
                        onFinish(analysisResults)
                        requestReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(analysisResults.isEmpty)

                    Button(action: onRecalibrate) {
                        // LOCALIZED
                        Label("review_recalibrateButton", systemImage: "ruler.fill")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 5)
                }
                .padding([.horizontal, .top])
                .background(.ultraThinMaterial)
            }

            VStack {
                Spacer()
                if showInitialGuidance {
                    InitialGuidanceView(
                        dismissAction: {
                            withAnimation(.spring()) { showInitialGuidance = false }
                        },
                        dontShowAgainAction: {
                            didShowInitialReviewGuidance = true
                            withAnimation(.spring()) { showInitialGuidance = false }
                        }
                    )
                }
            }
            .animation(.spring(), value: showInitialGuidance)
        }
        .task(id: currentIndex) {
            await MainActor.run {
                withAnimation { resetZoom() }
                loadFrame(at: currentIndex)
            }
        }
        .onAppear {
            recalculateAllSpeeds()
            if !didShowInitialReviewGuidance {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    showInitialGuidance = true
                }
            }
        }
        .onChange(of: currentIndex) { _ in
            if showInitialGuidance {
                withAnimation(.spring()) {
                    showInitialGuidance = false
                }
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            OnboardingSheetContainerView {
                // LOCALIZED
                OnboardingInstructionView(
                    slideIndex: 0,
                    currentTab: .constant(0),
                    imageNames: ["OnboardingSlide3.1","OnboardingSlide3.2"],
                    titleKey: "onboarding_slide3_title",
                    instructions: [
                        (icon: "arrow.left.and.right.circle.fill", textKey: "onboarding_slide3_instruction1"),
                        (icon: "wand.and.stars.inverse", textKey: "onboarding_slide3_instruction2"),
                        (icon: "slider.horizontal.3", textKey: "onboarding_slide3_instruction3"),
                        (icon: "arrow.uturn.backward", textKey: "onboarding_slide3_instruction4")
                    ]
                )
            }
        }
        // LOCALIZED
        .alert(Text("review_alert_interpolation_title"), isPresented: $showInterpolationInfo) {
            Button("common_ok", role: .cancel) { }
        } message: {
            Text("review_alert_interpolation_message")
        }
        // LOCALIZED
        .alert(Text("review_alert_manual_title"), isPresented: $showManualInfo) {
            Button("common_ok", role: .cancel) { }
        } message: {
            Text("review_alert_manual_message")
        }
        // LOCALIZED
        .alert(Text("review_alert_speedCalc_title"), isPresented: $showSpeedInfoAlert) {
            Button("common_ok", role: .cancel) { }
        } message: {
            Text("review_alert_speedCalc_message")
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack {
                Button(action: undo) { Image(systemName: "arrow.uturn.backward.circle") }.disabled(undoStack.isEmpty)
                Button(action: redo) { Image(systemName: "arrow.uturn.forward.circle") }.disabled(redoStack.isEmpty)
            }

            Spacer()
            // LOCALIZED
            Text(analysisResults.isEmpty ? LocalizedStringKey("review_topBar_noFrames") : LocalizedStringKey(String.localizedStringWithFormat(NSLocalizedString("review_topBar_frameCountFormat", comment: ""), currentIndex + 1, analysisResults.count)))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Spacer()

            HStack(spacing: 12) {
                Button { withAnimation { zoom(by: 1.5) } } label: { Image(systemName: "plus.magnifyingglass") }
                Button { withAnimation { zoom(by: 0.66) } } label: { Image(systemName: "minus.magnifyingglass") }
                Button { withAnimation { resetZoom() } } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
            }

            Button { showInfoSheet = true } label: { Image(systemName: "info.circle") }
        }
        .font(.title3)
        .padding(.horizontal)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    private var frameDisplay: some View {
        GeometryReader { geo in
            ZStack {
                ZStack {
                    if let image = currentFrameImage {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        Color.black
                        ProgressView().tint(.white)
                    }
                }
                .scaleEffect(currentScale)
                .offset(currentOffset)
                .gesture(panGesture().simultaneously(with: magnificationGesture()))

                if !analysisResults.isEmpty && analysisResults.indices.contains(currentIndex) {
                     OverlayView(
                         analysis: $analysisResults[currentIndex],
                         containerSize: geo.size,
                         videoSize: initialResult.videoSize,
                         currentScale: self.currentScale,
                         globalOffset: self.currentOffset
                     )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .onAppear { self.viewportSize = geo.size }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var interpolationSection: some View {
        if isInterpolationRecommended {
            VStack(spacing: 15) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        // LOCALIZED
                        Text("review_interp_gapWarning_title")
                            .fontWeight(.bold)
                        // LOCALIZED
                        Text("review_interp_gapWarning_message")
                            .foregroundColor(.secondary)
                    }
                    .font(.footnote)
                    
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(12)

                Button(action: interpolateFrames) {
                    // LOCALIZED
                    Label("review_interp_interpolateButton", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.purple)
                .scaleEffect(showInterpolationFeedback ? 1.05 : 1.0)

                Button { showInterpolationInfo = true } label: {
                    // LOCALIZED
                    Label("review_interp_whatIsButton", systemImage: "info.circle.fill")
                        .font(.caption)
                }
                .tint(.secondary)
            }
            .padding()
            .background(.thinMaterial)
            .animation(.spring(), value: isInterpolationRecommended)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var frameNavigationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // LOCALIZED
            Text("review_nav_sectionTitle")
                .sectionHeaderStyle()

            VStack(spacing: 15) {
                VStack {
                    HStack(spacing: 4) {
                        // LOCALIZED
                        Text("review_nav_speedLabel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button { showSpeedInfoAlert = true } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // LOCALIZED
                    if let speed = currentFrameData?.speedKPH {
                        Text(String.localizedStringWithFormat(NSLocalizedString("review_speedWithUnitFormat", comment: ""), speed))
                            .font(.headline).bold()
                    } else {
                        Text("common_notAvailable").font(.headline).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button(action: {
                        goToPreviousFrame()
                        triggerHapticFeedback(style: .medium)
                    }) {
                        Image(systemName: "arrow.left.circle.fill")
                    }
                    .disabled(currentIndex == 0)
                    .buttonStyle(GlowButtonStyle())

                    if !analysisResults.isEmpty {
                        Slider(value: frameIndexBinding, in: 0...Double(analysisResults.count - 1), step: 1)
                    } else {
                        Slider(value: .constant(0), in: 0...0)
                    }

                    Button(action: {
                        goToNextFrame()
                        triggerHapticFeedback(style: .medium)
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .disabled(analysisResults.isEmpty || currentIndex >= analysisResults.count - 1)
                    .buttonStyle(GlowButtonStyle())
                }
                .font(.largeTitle)
                .disabled(analysisResults.isEmpty)

                Divider()

                VStack(spacing: 8) {
                    Button { withAnimation(.spring()) { showTuningControls.toggle() } } label: {
                        // LOCALIZED
                        Label(showTuningControls ? "review_nav_hideManualControls" : "review_nav_showManualControls",
                              systemImage: showTuningControls ? "chevron.up" : "slider.horizontal.3")
                    }
                    .font(.callout)
                    .tint(.secondary)

                    if !showTuningControls {
                        // LOCALIZED
                        Text("review_nav_aiWarning")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 2)
                            .transition(.opacity)
                    }
                }
            }
            .glassPanelStyle()
        }
    }

    private var manualAdjustmentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // LOCALIZED
                Text("review_manual_sectionTitle")
                    .sectionHeaderStyle()
                Spacer()
                Button { showManualInfo = true } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 15) {
                BoxAdjustmentControls(
                    editMode: $editMode,
                    hasBox: currentFrameData?.boundingBox != nil,
                    addBoxAction: addBox,
                    removeBoxAction: removeBox,
                    adjustBoxAction: adjustBox
                )
            }
            .glassPanelStyle()
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
            )
        }
    }

    private func saveUndoState() {
        undoStack.append(analysisResults)
        redoStack.removeAll()
    }

    private func undo() {
        guard !undoStack.isEmpty else { return }
        let lastState = undoStack.removeLast()
        redoStack.append(analysisResults)
        analysisResults = lastState
        triggerHapticFeedback(style: .medium)
    }

    private func redo() {
        guard !redoStack.isEmpty else { return }
        let nextState = redoStack.removeLast()
        undoStack.append(analysisResults)
        analysisResults = nextState
        triggerHapticFeedback(style: .medium)
    }

    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                committedOffset.width += value.translation.width
                committedOffset.height += value.translation.height
            }
    }

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { value, state, _ in state = value }
            .onEnded { value in scale *= value }
    }

    private func zoom(by factor: CGFloat) { scale = max(1.0, scale * factor) }
    private func resetZoom() { scale = 1.0; committedOffset = .zero }

    private var currentFrameData: FrameAnalysis? {
        guard !analysisResults.isEmpty, analysisResults.indices.contains(currentIndex) else { return nil }
        return analysisResults[currentIndex]
    }

    private func triggerHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    private func interpolateFrames() {
        saveUndoState()
        interpolateMissingFrames()
        recalculateAllSpeeds()
        triggerHapticFeedback(style: .heavy)

        Task {
            withAnimation(.spring()) {
                showInterpolationFeedback = true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.spring()) {
                showInterpolationFeedback = false
            }
        }
    }

    private func interpolateMissingFrames() {
        var i = 0
        while i < analysisResults.count - 1 {
            if analysisResults[i].boundingBox != nil && analysisResults[i+1].boundingBox == nil {
                let startIndex = i
                var endIndex = -1
                for j in (startIndex + 2)..<analysisResults.count {
                    if analysisResults[j].boundingBox != nil {
                        endIndex = j
                        break
                    }
                }
                if endIndex != -1 {
                    if let startBox = analysisResults[startIndex].boundingBox,
                       let endBox = analysisResults[endIndex].boundingBox {
                        let gapLength = endIndex - startIndex
                        for k in (startIndex + 1)..<endIndex {
                            let stepWithinGap = k - startIndex
                            let t = CGFloat(stepWithinGap) / CGFloat(gapLength)
                            let newX = startBox.origin.x + t * (endBox.origin.x - startBox.origin.x)
                            let newY = startBox.origin.y + t * (endBox.origin.y - startBox.origin.y)
                            let newW = startBox.size.width + t * (endBox.size.width - startBox.size.width)
                            let newH = startBox.size.height + t * (endBox.size.height - startBox.size.height)
                            let interpolatedBox = CGRect(x: newX, y: newY, width: newW, height: newH)
                            analysisResults[k].boundingBox = interpolatedBox
                        }
                    }
                    i = endIndex
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }
    }

    private func recalculateAllSpeeds() {
        // --- LOGIC CHANGE ---
        // This function now uses a two-pass approach.
        // Pass 1: Calculate the "smart" tracked point for every frame.
        // Pass 2: Calculate the speed based on the distance between these points.
        
        let freshTracker = KalmanTracker(scaleFactor: initialResult.scaleFactor)
        let videoSize = initialResult.videoSize
        
        // Pass 1: Calculate all tracked points
        for i in 0..<analysisResults.count {
            _ = freshTracker.predict(dt: 1.0)

            if let boundingBox = analysisResults[i].boundingBox {
                let pixelRect = VNImageRectForNormalizedRect(boundingBox, Int(videoSize.width), Int(videoSize.height))
                freshTracker.update(measurement: pixelRect.center)
            }

            let currentState = freshTracker.getCurrentState()
            var finalTrackedPoint = currentState.point

            if let boundingBox = analysisResults[i].boundingBox {
                let pixelRect = VNImageRectForNormalizedRect(boundingBox, Int(videoSize.width), Int(videoSize.height))
                let velocity = currentState.velocity
                let speed = currentState.speed ?? 0.0

                if speed > 0.1 {
                    let normalizedVelocity = CGPoint(x: velocity.x / speed, y: velocity.y / speed)
                    let offsetX = normalizedVelocity.x * (pixelRect.width / 2.0)
                    let offsetY = normalizedVelocity.y * (pixelRect.height / 2.0)
                    finalTrackedPoint = CGPoint(x: currentState.point.x + offsetX, y: currentState.point.y + offsetY)
                }
            }
            analysisResults[i].trackedPoint = finalTrackedPoint
        }
        
        // Pass 2: Calculate speed based on the distance between tracked points
        let frameRate = initialResult.frameRate
        for i in 0..<analysisResults.count {
            if i == 0 {
                analysisResults[i].speedKPH = 0.0 // Speed is zero for the first frame
                continue
            }
            
            guard let currentPoint = analysisResults[i].trackedPoint,
                  let previousPoint = analysisResults[i-1].trackedPoint else {
                analysisResults[i].speedKPH = 0.0
                continue
            }
            
            // Calculate distance between the two cyan dots in pixels
            let dx = currentPoint.x - previousPoint.x
            let dy = currentPoint.y - previousPoint.y
            let pixelsPerFrameVelocity = sqrt(dx*dx + dy*dy)
            
            // Convert pixels/frame to km/h
            let pixelsPerSecond = pixelsPerFrameVelocity * Double(frameRate)
            let metersPerSecond = pixelsPerSecond * initialResult.scaleFactor
            let finalSpeed = metersPerSecond * 3.6
            
            analysisResults[i].speedKPH = finalSpeed
        }
    }


    private func addBox() {
        saveUndoState()
        guard !analysisResults.isEmpty, analysisResults.indices.contains(currentIndex) else { return }

        let videoSize = initialResult.videoSize
        var newBoxCenter = CGPoint(x: 0.5, y: 0.5)

        if let predictedPixelPoint = analysisResults[currentIndex].trackedPoint {
            if videoSize.width > 0 && videoSize.height > 0 {
                newBoxCenter = CGPoint(
                    x: predictedPixelPoint.x / videoSize.width,
                    y: predictedPixelPoint.y / videoSize.height
                )
            }
        }
        
        var newBoxSize = CGSize(width: 0.1, height: 0.1)
        if currentIndex > 0, let prevBox = analysisResults[currentIndex - 1].boundingBox {
            newBoxSize = prevBox.size
        }

        let newBox = CGRect(
            x: newBoxCenter.x - (newBoxSize.width / 2),
            y: newBoxCenter.y - (newBoxSize.height / 2),
            width: newBoxSize.width,
            height: newBoxSize.height
        )
        
        analysisResults[currentIndex].boundingBox = newBox
        recalculateAllSpeeds()
        triggerHapticFeedback(style: .medium)
    }

    private func removeBox() {
        saveUndoState()
        guard !analysisResults.isEmpty, analysisResults.indices.contains(currentIndex) else { return }
        analysisResults[currentIndex].boundingBox = nil
        recalculateAllSpeeds()
        triggerHapticFeedback(style: .medium)
    }

    private func adjustBox(dx: CGFloat = 0, dy: CGFloat = 0, dw: CGFloat = 0, dh: CGFloat = 0, pressCount: Int) {
        if pressCount == 0 {
            saveUndoState()
        }

        guard !analysisResults.isEmpty, analysisResults.indices.contains(currentIndex) else { return }
        guard var box = analysisResults[currentIndex].boundingBox else { return }

        let multiplier: CGFloat
        switch pressCount {
        case 0..<5: multiplier = 1.0
        case 5..<15: multiplier = 4.0
        case 15..<30: multiplier = 10.0
        default: multiplier = 25.0
        }

        let moveSensitivity: CGFloat = 0.002 * multiplier
        let resizeSensitivity: CGFloat = 0.005 * multiplier

        let widthChange = dw * resizeSensitivity / scale
        let heightChange = dh * resizeSensitivity / scale

        let newWidth = max(0.01, box.size.width + widthChange)
        let newHeight = max(0.01, box.size.height + heightChange)

        let originXAdjustment = (box.size.width - newWidth) / 2
        let originYAdjustment = (box.size.height - newHeight) / 2

        let finalOriginX = box.origin.x + (dx * moveSensitivity / scale) + originXAdjustment
        let finalOriginY = box.origin.y + (dy * moveSensitivity / scale) + originYAdjustment

        box.origin.x = max(0, min(finalOriginX, 1.0 - newWidth))
        box.origin.y = max(0, min(finalOriginY, 1.0 - newHeight))
        box.size.width = newWidth
        box.size.height = newHeight

        analysisResults[currentIndex].boundingBox = box
        recalculateAllSpeeds()
    }

    private func goToPreviousFrame() { if currentIndex > 0 { currentIndex -= 1 } }
    private func goToNextFrame() { if currentIndex < analysisResults.count - 1 { currentIndex += 1 } }

    private func loadFrame(at index: Int) {
        guard let timestampDouble = currentFrameData?.timestamp else {
            currentFrameImage = nil
            return
        }

        let cmTimestamp = CMTime(seconds: timestampDouble, preferredTimescale: 600)

        Task {
            do {
                let cgImage = try await imageGenerator.image(at: cmTimestamp).image
                await MainActor.run { currentFrameImage = UIImage(cgImage: cgImage) }
            } catch {
                #if DEBUG
                print("Failed to load frame for timestamp \(cmTimestamp): \(error)")
                #endif
            }
        }
    }
}

private struct InitialGuidanceView: View {
    let dismissAction: () -> Void
    let dontShowAgainAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundColor(.yellow)
                // LOCALIZED
                Text("review_guidance_title")
                    .fontWeight(.bold)
                Spacer()
                Button(action: dismissAction) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray, Color(uiColor: .systemGray4))
                        .font(.title2)
                }
            }
            // LOCALIZED
            Text("review_guidance_message")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // LOCALIZED
            Button("review_guidance_dontShowAgain") {
                dontShowAgainAction()
            }
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.top, 4)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}


struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .shadow(color: configuration.isPressed ? .accentColor.opacity(0.8) : .clear, radius: 5, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.leading, 8)
    }
}
extension View {
    func sectionHeaderStyle() -> some View { self.modifier(SectionHeaderStyle()) }
}

private struct OnboardingSheetContainerView<Content: View>: View {
    @Environment(\.dismiss) var dismiss
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
                Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)
                content
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // LOCALIZED
                    Button("common_done") { dismiss() }
                }
            }
        }
    }
}

private struct OverlayView: View {
    @Binding var analysis: FrameAnalysis
    let containerSize: CGSize
    let videoSize: CGSize
    let currentScale: CGFloat
    let globalOffset: CGSize

    var body: some View {
        ZStack {
            TrackingPointView(
                analysis: analysis, videoSize: videoSize, containerSize: containerSize,
                currentScale: currentScale, globalOffset: globalOffset
            )
            StaticBoxView(
                analysis: analysis, containerSize: containerSize, videoSize: videoSize,
                currentScale: currentScale, globalOffset: globalOffset
            )
        }
    }
}

private func getScaledImageInfo(containerSize: CGSize, videoSize: CGSize) -> (origin: CGPoint, scale: CGFloat, scaledSize: CGSize) {
    let viewScale = min(containerSize.width / videoSize.width, containerSize.height / videoSize.height)
    let scaledSize = CGSize(width: videoSize.width * viewScale, height: videoSize.height * viewScale)
    let imageOrigin = CGPoint(x: (containerSize.width - scaledSize.width) / 2, y: (containerSize.height - scaledSize.height) / 2)
    return (imageOrigin, viewScale, scaledSize)
}

private struct TrackingPointView: View {
    let analysis: FrameAnalysis
    let videoSize: CGSize
    let containerSize: CGSize
    let currentScale: CGFloat
    let globalOffset: CGSize

    var body: some View {
        if let point = analysis.trackedPoint {
            let imageInfo = getScaledImageInfo(containerSize: containerSize, videoSize: videoSize)
            let dotPosition = CGPoint(
                x: imageInfo.origin.x + (point.x * imageInfo.scale),
                y: imageInfo.origin.y + (point.y * imageInfo.scale)
            )
            Circle().fill(Color.cyan).frame(width: 3, height: 3)
                .overlay(Circle().stroke(Color.black, lineWidth: 1))
                .position(dotPosition)
                .scaleEffect(currentScale)
                .offset(globalOffset)
                .allowsHitTesting(false)
        }
    }
}

private struct StaticBoxView: View {
    let analysis: FrameAnalysis
    let containerSize: CGSize
    let videoSize: CGSize
    let currentScale: CGFloat
    let globalOffset: CGSize

    var body: some View {
        if let box = analysis.boundingBox {
            let imageInfo = getScaledImageInfo(containerSize: containerSize, videoSize: videoSize)
            
            let staticPixelFrame = CGRect(
                x: imageInfo.origin.x + (box.origin.x * imageInfo.scaledSize.width),
                y: imageInfo.origin.y + (box.origin.y * imageInfo.scaledSize.height),
                width: box.size.width * imageInfo.scaledSize.width,
                height: box.size.height * imageInfo.scaledSize.height
            )
            
            Rectangle().stroke(Color.red, lineWidth: 2 / currentScale)
                .frame(width: staticPixelFrame.width, height: staticPixelFrame.height)
                .position(x: staticPixelFrame.midX, y: staticPixelFrame.midY)
                .scaleEffect(currentScale)
                .offset(globalOffset)
                .allowsHitTesting(false)
        }
    }
}

private struct BoxAdjustmentControls: View {
    @Binding var editMode: ReviewView.EditMode
    let hasBox: Bool
    let addBoxAction: () -> Void
    let removeBoxAction: () -> Void
    let adjustBoxAction: (CGFloat, CGFloat, CGFloat, CGFloat, Int) -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            if hasBox {
                Button(role: .destructive, action: removeBoxAction) {
                    // LOCALIZED
                    Label("review_box_removeButton", systemImage: "xmark.square")
                        .frame(maxWidth: .infinity)
                }
                .tint(.orange)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Divider()
                
                // LOCALIZED
                Picker(LocalizedStringKey("Edit Mode"), selection: $editMode) {
                    Text("review_box_nudgePicker").tag(ReviewView.EditMode.move)
                    Text("review_box_resizePicker").tag(ReviewView.EditMode.resize)
                }.pickerStyle(.segmented)
                
                if editMode == .move {
                    ReviewDirectionalPad { dx, dy, pressCount in adjustBoxAction(dx, dy, 0, 0, pressCount) }
                } else {
                    ReviewResizeControls { dw, dh, pressCount in adjustBoxAction(0, 0, dw, dh, pressCount) }
                }
            } else {
                Button(action: addBoxAction) {
                    // LOCALIZED
                    Label("review_box_addButton", systemImage: "plus.square")
                        .frame(maxWidth: .infinity)
                }
                .tint(.blue)
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }
}

private struct ReviewDirectionalPad: View {
    let action: (CGFloat, CGFloat, Int) -> Void
    var body: some View {
        HStack(spacing: 20) {
            Spacer()
            RepeatingFineTuneButton(icon: "arrow.left") { pressCount in action(-1, 0, pressCount) }
            VStack(spacing: 10) {
                RepeatingFineTuneButton(icon: "arrow.up") { pressCount in action(0, -1, pressCount) }
                RepeatingFineTuneButton(icon: "arrow.down") { pressCount in action(0, 1, pressCount) }
            }
            RepeatingFineTuneButton(icon: "arrow.right") { pressCount in action(1, 0, pressCount) }
            Spacer()
        }
    }
}

private struct ReviewResizeControls: View {
    let action: (CGFloat, CGFloat, Int) -> Void
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // LOCALIZED
                Text("common_width").frame(width: 60)
                RepeatingFineTuneButton(icon: "minus") { pressCount in action(-1, 0, pressCount) }
                RepeatingFineTuneButton(icon: "plus") { pressCount in action(1, 0, pressCount) }
            }
            HStack {
                // LOCALIZED
                Text("common_height").frame(width: 60)
                RepeatingFineTuneButton(icon: "minus") { pressCount in action(0, -1, pressCount) }
                RepeatingFineTuneButton(icon: "plus") { pressCount in action(0, 1, pressCount) }
            }
        }
    }
}

private struct RepeatingFineTuneButton: View {
    let icon: String
    let action: (Int) -> Void
    
    @State private var timer: Timer?
    @State private var pressCount = 0
    @State private var isPressing = false
    
    var body: some View {
        Button(action: {
            if !isPressing { self.action(0) }
        }) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 50, height: 36)
                .padding(4)
                .background(isPressing ? Color.gray.opacity(0.5) : Color.gray.opacity(0.2))
                .cornerRadius(8)
                .shadow(color: isPressing ? .accentColor.opacity(0.7) : .clear, radius: 4)
        }
        .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
            self.isPressing = pressing
            if pressing {
                triggerHapticFeedback(style: .medium)
                self.startTimer()
            } else {
                self.stopTimer()
            }
        }, perform: {})
    }
    
    private func startTimer() {
        stopTimer()
        pressCount = 0
        action(pressCount)
        pressCount += 1
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.action(pressCount)
            pressCount += 1
            triggerHapticFeedback(style: .light)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        pressCount = 0
    }
    
    private func triggerHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
