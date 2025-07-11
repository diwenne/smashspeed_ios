//
//  ReviewView.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

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
    
    // State for Pan and Zoom of the entire image
    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    
    @State private var viewportSize: CGSize = .zero
    
    // State for the coordinate text fields
    @State private var xText: String = ""
    @State private var yText: String = ""
    @State private var wText: String = ""
    @State private var hText: String = ""
    
    @FocusState private var isInputActive: Bool
    
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
    
    private var currentOffset: CGSize {
        return CGSize(width: committedOffset.width + dragOffset.width, height: committedOffset.height + dragOffset.height)
    }
    private var currentScale: CGFloat {
        return scale * magnifyBy
    }

    var body: some View {
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

            VStack(spacing: 0) {
                // --- Top Frame Display ---
                Text("Frame \(currentIndex + 1) of \(analysisResults.count)")
                    .font(.headline).padding(.vertical, 10)
                    .frame(maxWidth: .infinity).background(.ultraThinMaterial)

                GeometryReader { geo in
                    ZStack {
                        // Image container with pan/zoom gestures
                        ZStack {
                            if let image = currentFrameImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Color.black
                                ProgressView().tint(.white)
                            }
                        }
                        .scaleEffect(currentScale)
                        .offset(currentOffset)
                        .gesture(panGesture().simultaneously(with: magnificationGesture()))
                        
                        // The overlay now uses a static, non-draggable box.
                        OverlayView(
                            analysis: $analysisResults[currentIndex],
                            containerSize: geo.size,
                            videoSize: initialResult.videoSize,
                            currentScale: self.currentScale,
                            globalOffset: self.currentOffset
                        )
                        
                        // UI Controls for zoom
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button { withAnimation { zoom(by: 1.5) } } label: { Image(systemName: "plus.magnifyingglass") }
                                Button { withAnimation { zoom(by: 0.66) } } label: { Image(systemName: "minus.magnifyingglass") }
                                Button { withAnimation { resetZoom() } } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                            }
                            .font(.title2).padding().background(.black.opacity(0.5))
                            .foregroundColor(.white).cornerRadius(15).padding()
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .onAppear { self.viewportSize = geo.size }
                }
                .frame(maxHeight: .infinity)

                // --- Bottom control panel on a GlassPanel ---
                ScrollView {
                    VStack(spacing: 20) {
                        // Frame Navigation
                        HStack {
                            Button(action: goToPreviousFrame) { Image(systemName: "arrow.left.circle.fill") }.disabled(currentIndex == 0)
                            Spacer()
                            VStack {
                                Text("Speed at this frame:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let speed = currentFrameData?.speedKPH {
                                    Text(String(format: "%.1f km/h", speed)).font(.headline).bold()
                                } else { Text("N/A").font(.headline).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button(action: goToNextFrame) { Image(systemName: "arrow.right.circle.fill") }.disabled(currentIndex >= analysisResults.count - 1)
                        }
                        .font(.largeTitle)
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                        
                        Divider()

                        // Bounding Box Controls
                        BoxAdjustmentControls(
                            editMode: $editMode,
                            hasBox: currentFrameData?.boundingBox != nil,
                            addBoxAction: addBox,
                            removeBoxAction: removeBox,
                            adjustBoxAction: adjustBox
                        )
                        
                        Divider()
                        
                        // Manual Coordinates
                        CoordinateInputView(
                            xText: $xText, yText: $yText,
                            wText: $wText, hText: $hText,
                            isFocused: $isInputActive,
                            onCommit: updateBoxFromTextFields
                        )
                        
                        // Finalize Button
                        Button("Finish & Save Analysis") { onFinish(analysisResults) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(30)
                    .background(GlassPanel())
                    .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                    .padding()
                }
                .frame(maxHeight: isInputActive ? 450 : 350) // Adjust height based on keyboard
                .animation(.spring(), value: isInputActive)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        updateBoxFromTextFields()
                        isInputActive = false
                    }
                }
            }
        }
        .task(id: currentIndex) {
            await MainActor.run {
                updateTextFieldsFromBox()
                withAnimation { resetZoom() }
                loadFrame(at: currentIndex)
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
    
    private func updateAndRecalculate() {
        updateTextFieldsFromBox()
        recalculateAllSpeeds()
    }
    
    // MARK: - Bounding Box Manipulation
    private func addBox() {
        guard analysisResults.indices.contains(currentIndex) else { return }
        let boxSize = CGSize(width: 0.1, height: 0.1)
        analysisResults[currentIndex].boundingBox = CGRect(
            x: 0.45, y: 0.45, width: boxSize.width, height: boxSize.height
        )
        updateAndRecalculate()
    }
    
    private func removeBox() {
        analysisResults[currentIndex].boundingBox = nil
        updateAndRecalculate()
    }
    
    private func adjustBox(dx: CGFloat = 0, dy: CGFloat = 0, dw: CGFloat = 0, dh: CGFloat = 0) {
        guard var box = analysisResults[currentIndex].boundingBox else { return }
        let moveSensitivity: CGFloat = 0.002
        let resizeSensitivity: CGFloat = 0.005
        box.origin.x = max(0, min(box.origin.x + (dx * moveSensitivity / scale), 1.0 - box.size.width))
        box.origin.y = max(0, min(box.origin.y + (dy * moveSensitivity / scale), 1.0 - box.size.height))
        box.size.width = max(0.01, box.size.width + (dw * resizeSensitivity / scale))
        box.size.height = max(0.01, box.size.height + (dh * resizeSensitivity / scale))
        analysisResults[currentIndex].boundingBox = box
        updateAndRecalculate()
    }
    
    private func updateTextFieldsFromBox() {
        if let box = currentFrameData?.boundingBox {
            xText = String(format: "%.3f", box.origin.x)
            yText = String(format: "%.3f", box.origin.y)
            wText = String(format: "%.3f", box.size.width)
            hText = String(format: "%.3f", box.size.height)
        } else {
            xText = ""; yText = ""; wText = ""; hText = ""
        }
    }
    
    private func updateBoxFromTextFields() {
        guard let x = Double(xText), let y = Double(yText), let w = Double(wText), let h = Double(hText) else { return }
        analysisResults[currentIndex].boundingBox = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
        recalculateAllSpeeds()
    }
    
    private func goToPreviousFrame() { if currentIndex > 0 { currentIndex -= 1 } }
    private func goToNextFrame() { if currentIndex < analysisResults.count - 1 { currentIndex += 1 } }
    
    private func loadFrame(at index: Int) {
        guard let timestamp = currentFrameData?.timestamp else { return }
        Task {
            do {
                let cgImage = try await imageGenerator.image(at: timestamp).image
                await MainActor.run { currentFrameImage = UIImage(cgImage: cgImage) }
            } catch { print("Failed to load frame for timestamp \(timestamp): \(error)") }
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
    let adjustBoxAction: (CGFloat, CGFloat, CGFloat, CGFloat) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            if hasBox {
                Picker("Edit Mode", selection: $editMode) {
                    Text("Nudge").tag(ReviewView.EditMode.move)
                    Text("Resize").tag(ReviewView.EditMode.resize)
                }.pickerStyle(.segmented)
                
                if editMode == .move {
                    ReviewDirectionalPad { dx, dy in adjustBoxAction(dx, dy, 0, 0) }
                } else {
                    ReviewResizeControls { dw, dh in adjustBoxAction(0, 0, dw, dh) }
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

private struct CoordinateInputView: View {
    @Binding var xText: String
    @Binding var yText: String
    @Binding var wText: String
    @Binding var hText: String
    var isFocused: FocusState<Bool>.Binding // Receive the focus state
    let onCommit: () -> Void
    
    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("x").frame(width: 20); TextField("x", text: $xText).focused(isFocused)
                Text("y").frame(width: 20); TextField("y", text: $yText).focused(isFocused)
            }
            GridRow {
                Text("w").frame(width: 20); TextField("w", text: $wText).focused(isFocused)
                Text("h").frame(width: 20); TextField("h", text: $hText).focused(isFocused)
            }
        }
        .textFieldStyle(.roundedBorder)
        .keyboardType(.decimalPad)
        .onSubmit(onCommit)
    }
}

private struct ReviewDirectionalPad: View {
    let action: (CGFloat, CGFloat) -> Void
    var body: some View {
        HStack(spacing: 20) {
            Spacer()
            RepeatingFineTuneButton(icon: "arrow.left") { action(-1, 0) }
            VStack(spacing: 10) {
                RepeatingFineTuneButton(icon: "arrow.up") { action(0, -1) }
                RepeatingFineTuneButton(icon: "arrow.down") { action(0, 1) }
            }
            RepeatingFineTuneButton(icon: "arrow.right") { action(1, 0) }
            Spacer()
        }
    }
}

private struct ReviewResizeControls: View {
    let action: (CGFloat, CGFloat) -> Void
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Width").frame(width: 60)
                RepeatingFineTuneButton(icon: "minus") { action(-1, 0) }
                RepeatingFineTuneButton(icon: "plus") { action(1, 0) }
            }
            HStack {
                Text("Height").frame(width: 60)
                RepeatingFineTuneButton(icon: "minus") { action(0, -1) }
                RepeatingFineTuneButton(icon: "plus") { action(0, 1) }
            }
        }
    }
}

private struct RepeatingFineTuneButton: View {
    let icon: String
    let action: () -> Void
    @State private var timer: Timer?
    @State private var isPressing = false
    var body: some View {
        Button(action: {
            if !isPressing { self.action() }
        }) {
            Image(systemName: icon).font(.title3).frame(width: 50, height: 36).padding(4)
                .background(isPressing ? Color.gray.opacity(0.5) : Color.gray.opacity(0.2))
                .cornerRadius(8)
        }
        .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
            self.isPressing = pressing
            if pressing { self.startTimer() } else { self.stopTimer() }
        }, perform: {})
    }
    private func startTimer() {
        stopTimer()
        action()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in self.action() }
    }
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
