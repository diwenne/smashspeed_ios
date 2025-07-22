import SwiftUI
import AVFoundation
import Vision

// MARK: - Main Review View
struct ReviewView: View {
    let videoURL: URL
    let initialResult: VideoAnalysisResult
    let onFinish: ([FrameAnalysis]) -> Void
    
    enum EditMode { case move, resize }
    
    @State private var analysisResults: [FrameAnalysis]
    @State private var currentIndex = 0
    @State private var currentFrameImage: UIImage?
    @State private var editMode: EditMode = .move
    
    @State private var showInfoSheet: Bool = false
    @State private var showTuningControls = false
    
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
                    Image(systemName: "info.circle").font(.title3).padding().opacity(0)
                    Spacer()
                    Text("Frame \(currentIndex + 1) of \(analysisResults.count)")
                        .font(.headline)
                    Spacer()
                    Button { showInfoSheet = true } label: { Image(systemName: "info.circle").font(.title3) }.padding()
                }
                .frame(maxWidth: .infinity).background(.ultraThinMaterial)

                GeometryReader { geo in
                    ZStack {
                        // Image container
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
                        
                        // Overlay for bounding box
                        OverlayView(
                            analysis: $analysisResults[currentIndex],
                            containerSize: geo.size,
                            videoSize: initialResult.videoSize,
                            currentScale: self.currentScale,
                            globalOffset: self.currentOffset
                        )
                        
                        // Zoom controls
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
                                    Slider(value: frameIndexBinding, in: 0...Double(analysisResults.count - 1), step: 1)
                                    Button(action: goToNextFrame) { Image(systemName: "arrow.right.circle.fill") }.disabled(currentIndex >= analysisResults.count - 1)
                                }
                                .font(.largeTitle)
                                .buttonStyle(.plain)
                                
                                Divider()
                                
                                // ✅ MODIFIED: Grouped the button and the new note together.
                                VStack(spacing: 8) {
                                    Button {
                                        withAnimation(.spring()) {
                                            showTuningControls.toggle()
                                        }
                                    } label: {
                                        Label(showTuningControls ? "Hide Box Controls" : "Manually Adjust Box",
                                              systemImage: showTuningControls ? "chevron.up" : "slider.horizontal.3")
                                    }
                                    .font(.callout)
                                    .tint(.secondary)
                                    
                                    // Note is only visible when controls are hidden
                                    if !showTuningControls {
                                        Text("Note: The AI detection is usually very accurate. Manual tuning is rarely needed.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal)
                                            .transition(.opacity)
                                    }
                                }
                            }
                            .glassPanelStyle()
                        }
                        
                        // --- Section 2: Bounding Box Adjustment (Conditional) ---
                        if showTuningControls {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("BOUNDING BOX ADJUSTMENT")
                                    .sectionHeaderStyle()
                                
                                VStack(spacing: 15) {
                                    Text("Use these controls if the red box is not accurately tracking the shuttlecock.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Divider()
                                    
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
                        
                        // --- Finalize Button ---
                        Button("Finish & Save Analysis") { onFinish(analysisResults) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
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
            updateAndRecalculate()
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
                        (icon: "checkmark.circle.fill", text: "Most videos don’t need manual correction—just review and continue.")
                    ]
                )
            }
        }
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
        guard analysisResults.indices.contains(currentIndex) else { return nil }
        return analysisResults[currentIndex]
    }
    
    private func recalculateAllSpeeds() {
        let freshTracker = ShuttlecockTracker(scaleFactor: initialResult.scaleFactor)
        for i in 0..<analysisResults.count {
            let result = freshTracker.track(
                box: analysisResults[i].boundingBox, timestamp: analysisResults[i].timestamp,
                frameSize: initialResult.videoSize, fps: initialResult.frameRate
            )
            analysisResults[i].speedKPH = result.speedKPH
            analysisResults[i].trackedPoint = result.point
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
                } else { i += 1 }
            } else { i += 1 }
        }
    }
    
    private func updateAndRecalculate() {
        interpolateMissingFrames()
        recalculateAllSpeeds()
    }
    
    // MARK: - Bounding Box Manipulation
    private func addBox() {
        guard analysisResults.indices.contains(currentIndex) else { return }
        let boxSize = CGSize(width: 0.1, height: 0.1)
        analysisResults[currentIndex].boundingBox = CGRect(x: 0.45, y: 0.45, width: boxSize.width, height: boxSize.height)
        updateAndRecalculate()
    }
    
    private func removeBox() {
        analysisResults[currentIndex].boundingBox = nil
        updateAndRecalculate()
    }
    
    private func adjustBox(dx: CGFloat = 0, dy: CGFloat = 0, dw: CGFloat = 0, dh: CGFloat = 0, pressCount: Int) {
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
        updateAndRecalculate()
    }
    
    private func goToPreviousFrame() { if currentIndex > 0 { currentIndex -= 1 } }
    private func goToNextFrame() { if currentIndex < analysisResults.count - 1 { currentIndex += 1 } }
    
    private func loadFrame(at index: Int) {
        guard let timestamp = currentFrameData?.timestamp else { return }
        Task {
            do {
                let cgImage = try await imageGenerator.image(at: timestamp).image
                await MainActor.run { currentFrameImage = UIImage(cgImage: cgImage) }
            } catch {
                #if DEBUG
                print("Failed to load frame for timestamp \(timestamp): \(error)")
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
        VStack(spacing: 8) {
            if hasBox {
                Picker("Edit Mode", selection: $editMode) {
                    Text("Nudge").tag(ReviewView.EditMode.move)
                    Text("Resize").tag(ReviewView.EditMode.resize)
                }.pickerStyle(.segmented)
                
                if editMode == .move {
                    ReviewDirectionalPad { dx, dy, pressCount in adjustBoxAction(dx, dy, 0, 0, pressCount) }
                } else {
                    ReviewResizeControls { dw, dh, pressCount in adjustBoxAction(0, 0, dw, dh, pressCount) }
                }
            }
            
            HStack {
                Spacer()
                if !hasBox {
                    Button(action: addBoxAction) { Label("Add Box", systemImage: "plus.square") }.tint(.blue)
                } else {
                    Button(role: .destructive, action: removeBoxAction) { Label("Remove Box", systemImage: "trash") }.tint(.red)
                }
                Spacer()
            }.buttonStyle(.bordered).controlSize(.small)
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
