import SwiftUI
import AVFoundation
import Vision
import StoreKit
import UIKit // Added for UIImpactFeedbackGenerator

// MARK: - Main Review View
struct ReviewView: View {
    let videoURL: URL
    let initialResult: VideoAnalysisResult
    let onFinish: ([FrameAnalysis]) -> Void
    
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
    @State private var showInterpolationFeedback = false
    
    // State for the undo/redo history stacks.
    @State private var undoStack: [[FrameAnalysis]] = []
    @State private var redoStack: [[FrameAnalysis]] = []
    
    // State for Pan and Zoom
    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    
    @State private var viewportSize: CGSize = .zero
    
    private let imageGenerator: AVAssetImageGenerator
    
    init(videoURL: URL, initialResult: VideoAnalysisResult, onFinish: @escaping ([FrameAnalysis]) -> Void) {
        self.videoURL = videoURL
        self.initialResult = initialResult
        self._analysisResults = State(initialValue: initialResult.frameData)
        self.onFinish = onFinish
        
        let asset = AVURLAsset(url: videoURL)
        self.imageGenerator = AVAssetImageGenerator(asset: asset)
        self.imageGenerator.appliesPreferredTrackTransform = true
        self.imageGenerator.requestedTimeToleranceBefore = .zero
        self.imageGenerator.requestedTimeToleranceAfter = .zero
    }
    
    private var frameIndexBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(self.currentIndex) },
            set: { self.currentIndex = Int($0) }
        )
    }
    
    private var currentOffset: CGSize {
        return CGSize(width: committedOffset.width + dragOffset.width, height: committedOffset.height + dragOffset.height)
    }
    private var currentScale: CGFloat {
        return scale * magnifyBy
    }

    var body: some View {
        ZStack {
            // Background aurora
            Color(.systemBackground).ignoresSafeArea()
            Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
            Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)

            VStack(spacing: 0) {
                // --- Top Frame Display ---
                HStack {
                    // Undo/Redo buttons in the top bar.
                    HStack {
                        Button(action: undo) {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .disabled(undoStack.isEmpty)
                        
                        Button(action: redo) {
                            Image(systemName: "arrow.uturn.forward.circle")
                        }
                        .disabled(redoStack.isEmpty)
                    }
                    .font(.title3)
                    .padding(.leading)
                    
                    Spacer()
                    
                    if !analysisResults.isEmpty {
                        Text("Frame \(currentIndex + 1) of \(analysisResults.count)")
                            .font(.headline)
                    } else {
                        Text("No Frames")
                            .font(.headline)
                    }
                    Spacer()
                    Button { showInfoSheet = true } label: { Image(systemName: "info.circle").font(.title3) }.padding()
                }
                .frame(maxWidth: .infinity).background(.ultraThinMaterial)

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
                        
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button { withAnimation { zoom(by: 1.5) } } label: { Image(systemName: "plus.magnifyingglass") }
                                Button { withAnimation { zoom(by: 0.66) } } label: { Image(systemName: "minus.magnifyingglass") }
                                Button { withAnimation { resetZoom() } } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                            }
                            .font(.title2).padding().background(.black.opacity(0.5)).foregroundColor(.white).cornerRadius(15).padding()
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .onAppear { self.viewportSize = geo.size }
                }
                .frame(maxHeight: .infinity)

                // --- Bottom control panel ---
                ScrollView {
                    VStack(spacing: 25) {
                        // --- Section 1: Frame Navigation ---
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FRAME NAVIGATION")
                                .sectionHeaderStyle()
                            
                            VStack(spacing: 15) {
                                VStack {
                                    Text("Speed at this frame:").font(.caption).foregroundStyle(.secondary)
                                    if let speed = currentFrameData?.speedKPH {
                                        Text(String(format: "%.1f km/h", speed)).font(.headline).bold()
                                    } else {
                                        Text("N/A").font(.headline).foregroundStyle(.secondary)
                                    }
                                }
                                
                                HStack {
                                    Button(action: goToPreviousFrame) { Image(systemName: "arrow.left.circle.fill") }.disabled(currentIndex == 0)
                                    if !analysisResults.isEmpty {
                                        Slider(value: frameIndexBinding, in: 0...Double(analysisResults.count - 1), step: 1)
                                    } else {
                                        Slider(value: .constant(0), in: 0...0)
                                    }
                                    Button(action: goToNextFrame) { Image(systemName: "arrow.right.circle.fill") }.disabled(analysisResults.isEmpty || currentIndex >= analysisResults.count - 1)
                                }
                                .font(.largeTitle)
                                .buttonStyle(.plain)
                                .disabled(analysisResults.isEmpty)
                                
                                Divider()
                                
                                VStack(spacing: 8) {
                                    Button {
                                        withAnimation(.spring()) {
                                            showTuningControls.toggle()
                                        }
                                    } label: {
                                        Label(showTuningControls ? "Hide Manual Controls" : "Show Manual Controls",
                                              systemImage: showTuningControls ? "chevron.up" : "slider.horizontal.3")
                                    }
                                    .font(.callout)
                                    .tint(.secondary)
                                    
                                    if !showTuningControls {
                                        Text("The AI detection is very accurate—these controls are not usually needed.")
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
                        
                        // --- Section 2: Bounding Box Adjustment (Conditional) ---
                        if showTuningControls {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("MANUAL ADJUSTMENT")
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
                        
                        // --- Section 3: Interpolation (Always Visible) ---
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("AUTOMATIC ADJUSTMENT")
                                    .sectionHeaderStyle()
                                Spacer()
                                Button { showInterpolationInfo = true } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            VStack(spacing: 15) {
                                
                                Text("It's recommended to run this at least once to fill in any missing frames.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                Button(action: interpolateFrames) {
                                    Label("Interpolate Gap", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .tint(.purple)
                                .scaleEffect(showInterpolationFeedback ? 1.05 : 1.0)
                                .opacity(showInterpolationFeedback ? 0.6 : 1.0)
                            }
                            .glassPanelStyle()
                        }
                        
                        // --- Finalize Button ---
                        Button("Finish & Save Analysis") {
                            onFinish(analysisResults)
                            requestReview()
                        }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .disabled(analysisResults.isEmpty)
                        
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)
            }
        }
        .task(id: currentIndex) {
            await MainActor.run {
                withAnimation { resetZoom() }
                loadFrame(at: currentIndex)
            }
        }
        .onAppear {
            recalculateAllSpeeds()
        }
        .sheet(isPresented: $showInfoSheet) {
            OnboardingSheetContainerView {
                OnboardingInstructionView(
                    slideIndex: 0,
                    currentTab: .constant(0),
                    imageNames: ["OnboardingSlide3.1","OnboardingSlide3.2"],
                    title: "3. Review Detection",
                    instructions: [
                        (icon: "arrow.left.and.right.circle.fill", text: "Use the slider or arrow keys to move through each frame and view the shuttle speed."),
                        (icon: "rectangle.dashed", text: "If the shuttle is detected incorrectly, adjust the red box to tightly fit around it."),
                        (icon: "slider.horizontal.3", text: "Use the controls below to manually move, resize, or fine-tune the box."),
                        (icon: "xmark.square.fill", text: "If a frame has a bad detection, you can remove its box before interpolating."),
                        (icon: "arrow.up.left.and.arrow.down.right", text: "Use the Interpolate tool to automatically fill in gaps between good detections.")
                    ]
                )
            }
        }
        .alert("What is Interpolation?", isPresented: $showInterpolationInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Interpolation automatically fills in missing bounding boxes. If you have a frame with a box, then a gap of frames with no box, followed by another frame with a box, this tool will draw a straight line to fill in the gap.")
        }
        .alert("Manual Adjustment", isPresented: $showManualInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Use these controls to fix errors made by the AI. You can add a box if the AI missed the shuttle, remove a box if the detection is wrong, or nudge/resize an existing box for better accuracy.")
        }
    }
    
    // MARK: - Undo/Redo Logic
    
    private func saveUndoState() {
        undoStack.append(analysisResults)
        redoStack.removeAll() // Clear redo stack on new action
    }
    
    private func undo() {
        guard !undoStack.isEmpty else { return }
        let lastState = undoStack.removeLast()
        redoStack.append(analysisResults)
        analysisResults = lastState
        triggerHapticFeedback()
    }
    
    private func redo() {
        guard !redoStack.isEmpty else { return }
        let nextState = redoStack.removeLast()
        undoStack.append(analysisResults)
        analysisResults = nextState
        triggerHapticFeedback()
    }
    
    // MARK: - Gesture and Zoom Logic
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

    // MARK: - Data and Frame Logic
    private var currentFrameData: FrameAnalysis? {
        guard !analysisResults.isEmpty, analysisResults.indices.contains(currentIndex) else { return nil }
        return analysisResults[currentIndex]
    }
    
    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func interpolateFrames() {
        saveUndoState()
        interpolateMissingFrames()
        recalculateAllSpeeds()
        triggerHapticFeedback()
        
        Task {
            withAnimation(.spring()) {
                showInterpolationFeedback = true
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
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
        let freshTracker = KalmanTracker(scaleFactor: initialResult.scaleFactor)
        
        let frameRate = initialResult.frameRate
        let videoSize = initialResult.videoSize
        
        for i in 0..<analysisResults.count {
            
            _ = freshTracker.predict(dt: 1.0)
            
            if let boundingBox = analysisResults[i].boundingBox {
                let pixelRect = VNImageRectForNormalizedRect(boundingBox, Int(videoSize.width), Int(videoSize.height))
                freshTracker.update(measurement: pixelRect.center)
            }
            
            let currentState = freshTracker.getCurrentState()
            let pixelsPerFrameVelocity = currentState.speedKPH ?? 0.0
            
            let pixelsPerSecond = pixelsPerFrameVelocity * Double(frameRate)
            let metersPerSecond = pixelsPerSecond * initialResult.scaleFactor
            let finalSpeed = metersPerSecond * 3.6
            
            analysisResults[i].speedKPH = finalSpeed
            analysisResults[i].trackedPoint = currentState.point
        }
    }
    
    // MARK: - Bounding Box Manipulation
    
    // --- ❗️ MODIFIED FUNCTION ---
    private func addBox() {
        saveUndoState()
        guard !analysisResults.isEmpty, analysisResults.indices.contains(currentIndex) else { return }

        let videoSize = initialResult.videoSize
        var newBoxCenter = CGPoint(x: 0.5, y: 0.5) // Default to screen center

        // Use the tracker's last known point for this frame as the center.
        // This point is already present even if the box was removed.
        if let predictedPixelPoint = analysisResults[currentIndex].trackedPoint {
            if videoSize.width > 0 && videoSize.height > 0 {
                newBoxCenter = CGPoint(
                    x: predictedPixelPoint.x / videoSize.width,
                    y: predictedPixelPoint.y / videoSize.height
                )
            }
        }
        
        // Use the previous frame's box size, or a default.
        var newBoxSize = CGSize(width: 0.1, height: 0.1) // Default size
        if currentIndex > 0, let prevBox = analysisResults[currentIndex - 1].boundingBox {
            newBoxSize = prevBox.size
        }

        // Create the new box, centered on the predicted point.
        let newBox = CGRect(
            x: newBoxCenter.x - (newBoxSize.width / 2),
            y: newBoxCenter.y - (newBoxSize.height / 2),
            width: newBoxSize.width,
            height: newBoxSize.height
        )
        
        analysisResults[currentIndex].boundingBox = newBox
        recalculateAllSpeeds()
        triggerHapticFeedback()
    }

    private func removeBox() {
        saveUndoState()
        guard !analysisResults.isEmpty, analysisResults.indices.contains(currentIndex) else { return }
        analysisResults[currentIndex].boundingBox = nil
        recalculateAllSpeeds()
        triggerHapticFeedback()
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
        
        box.origin.x = max(0, min(box.origin.x + (dx * moveSensitivity / scale), 1.0 - box.size.width))
        box.origin.y = max(0, min(box.origin.y + (dy * moveSensitivity / scale), 1.0 - box.size.height))
        box.size.width = max(0.01, box.size.width + (dw * resizeSensitivity / scale))
        box.size.height = max(0.01, box.size.height + (dh * resizeSensitivity / scale))
        
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

// MARK: - Reusable View Styles
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

// MARK: - Onboarding Sheet Container
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
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Helper Views for ReviewView
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
                    Label("Remove Box", systemImage: "xmark.square")
                        .frame(maxWidth: .infinity)
                }
                .tint(.orange)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Divider()
                
                Picker("Edit Mode", selection: $editMode) {
                    Text("Nudge").tag(ReviewView.EditMode.move)
                    Text("Resize").tag(ReviewView.EditMode.resize)
                }.pickerStyle(.segmented)
                
                if editMode == .move {
                    ReviewDirectionalPad { dx, dy, pressCount in adjustBoxAction(dx, dy, 0, 0, pressCount) }
                } else {
                    ReviewResizeControls { dw, dh, pressCount in adjustBoxAction(0, 0, dw, dh, pressCount) }
                }
            } else {
                Button(action: addBoxAction) {
                    Label("Add Box", systemImage: "plus.square")
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
                Text("Width").frame(width: 60)
                RepeatingFineTuneButton(icon: "minus") { pressCount in action(-1, 0, pressCount) }
                RepeatingFineTuneButton(icon: "plus") { pressCount in action(1, 0, pressCount) }
            }
            HStack {
                Text("Height").frame(width: 60)
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
            Image(systemName: icon).font(.title3).frame(width: 50, height: 36).padding(4)
                .background(isPressing ? Color.gray.opacity(0.5) : Color.gray.opacity(0.2))
                .cornerRadius(8)
        }
        .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
            self.isPressing = pressing
            if pressing {
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
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        pressCount = 0
    }
}
