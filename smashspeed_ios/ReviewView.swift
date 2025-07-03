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
    
    private var currentOffset: CGSize {
        return CGSize(width: committedOffset.width + dragOffset.width, height: committedOffset.height + dragOffset.height)
    }
    private var currentScale: CGFloat {
        return scale * magnifyBy
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Frame \(currentIndex + 1) of \(analysisResults.count)")
                .font(.headline).padding(.vertical, 10)
                .frame(maxWidth: .infinity).background(.thinMaterial)

            GeometryReader { geo in
                ZStack {
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
                    
                    OverlayView(
                        analysis: $analysisResults[currentIndex],
                        containerSize: geo.size,
                        videoSize: initialResult.videoSize,
                        currentScale: currentScale,
                        globalOffset: currentOffset,
                        onEditEnded: recalculateAllSpeeds
                    )
                    
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

            VStack(spacing: 12) {
                if let speed = currentFrameData?.speedKPH {
                    Text(String(format: "%.1f km/h", speed)).font(.title3).bold()
                } else { Text("No Speed Detected").font(.title3).foregroundColor(.secondary) }
                
                BoxAdjustmentControls(
                    editMode: $editMode,
                    hasBox: currentFrameData?.boundingBox != nil,
                    addBoxAction: addBox,
                    removeBoxAction: removeBox,
                    adjustBoxAction: adjustBox
                )
                
                HStack {
                    Button(action: goToPreviousFrame) { Image(systemName: "arrow.left.circle.fill") }.disabled(currentIndex == 0)
                    Spacer()
                    Button("Finish") { onFinish(analysisResults) }.buttonStyle(.borderedProminent).controlSize(.regular)
                    Spacer()
                    Button(action: goToNextFrame) { Image(systemName: "arrow.right.circle.fill") }.disabled(currentIndex >= analysisResults.count - 1)
                }
                .font(.largeTitle).buttonStyle(.plain)
            }
            .padding().padding(.bottom).background(.thinMaterial)
        }
        .task(id: currentIndex) {
            await MainActor.run {
                withAnimation { resetZoom() }
                loadFrame(at: currentIndex)
            }
        }
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
    
    private func addBox() {
        guard analysisResults.indices.contains(currentIndex) else { return }
        let imageInfo = getScaledImageInfo(containerSize: viewportSize, videoSize: initialResult.videoSize)
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        
        let containerCoord = CGPoint(
            x: (viewportCenter.x - committedOffset.width) / scale,
            y: (viewportCenter.y - committedOffset.height) / scale
        )
        let normalizedCenter = CGPoint(
            x: (containerCoord.x - imageInfo.origin.x) / (initialResult.videoSize.width * imageInfo.scale),
            y: (containerCoord.y - imageInfo.origin.y) / (initialResult.videoSize.height * imageInfo.scale)
        )

        let boxSize = CGSize(width: 0.1, height: 0.1)
        analysisResults[currentIndex].boundingBox = CGRect(
            x: normalizedCenter.x - (boxSize.width / 2),
            y: normalizedCenter.y - (boxSize.height / 2),
            width: boxSize.width, height: boxSize.height
        )
        recalculateAllSpeeds()
    }
    
    private func removeBox() {
        analysisResults[currentIndex].boundingBox = nil
        recalculateAllSpeeds()
    }
    
    private func adjustBox(dx: CGFloat = 0, dy: CGFloat = 0, dw: CGFloat = 0, dh: CGFloat = 0) {
        guard var box = analysisResults[currentIndex].boundingBox else { return }
        let moveSensitivity: CGFloat = 0.002
        let resizeSensitivity: CGFloat = 0.005
        box.origin.x += dx * moveSensitivity / scale
        box.origin.y += dy * moveSensitivity / scale
        box.size.width += dw * resizeSensitivity / scale
        box.size.height += dh * resizeSensitivity / scale
        box.origin.x = max(0, min(box.origin.x, 1.0 - box.size.width))
        box.origin.y = max(0, min(box.origin.y, 1.0 - box.size.height))
        box.size.width = max(0.01, box.size.width)
        box.size.height = max(0.01, box.size.height)
        analysisResults[currentIndex].boundingBox = box
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
    let onEditEnded: () -> Void

    var body: some View {
        ZStack {
            // --- PASS THE VALUES DOWN TO THE TRACKING POINT VIEW ---
            TrackingPointView(
                analysis: analysis,
                videoSize: videoSize,
                containerSize: containerSize,
                currentScale: currentScale,
                globalOffset: globalOffset
            )
            
            DraggableAndResizableBoxView(
                analysis: $analysis, containerSize: containerSize,
                videoSize: videoSize, currentScale: currentScale,
                globalOffset: globalOffset,
                onEditEnded: onEditEnded
            )
        }
    }
}

private func getScaledImageInfo(containerSize: CGSize, videoSize: CGSize) -> (origin: CGPoint, scale: CGFloat) {
    let viewScale = min(containerSize.width / videoSize.width, containerSize.height / videoSize.height)
    let scaledImageSize = CGSize(width: videoSize.width * viewScale, height: videoSize.height * viewScale)
    let imageOrigin = CGPoint(
        x: (containerSize.width - scaledImageSize.width) / 2,
        y: (containerSize.height - scaledImageSize.height) / 2
    )
    return (imageOrigin, viewScale)
}

private struct TrackingPointView: View {
    let analysis: FrameAnalysis
    let videoSize: CGSize
    let containerSize: CGSize
    // --- RECEIVE THE PAN/ZOOM STATE ---
    let currentScale: CGFloat
    let globalOffset: CGSize

    var body: some View {
        if let point = analysis.trackedPoint {
            let imageInfo = getScaledImageInfo(containerSize: containerSize, videoSize: videoSize)
            
            // This position is correct relative to the un-scaled, un-panned image
            let dotPosition = CGPoint(
                x: imageInfo.origin.x + (point.x * imageInfo.scale),
                y: imageInfo.origin.y + (point.y * imageInfo.scale)
            )
            
            Circle().fill(Color.cyan).frame(width: 3, height: 3)
                .overlay(Circle().stroke(Color.black, lineWidth: 1))
                .position(dotPosition)
                // --- APPLY THE PAN/ZOOM TO THE DOT ---
                .scaleEffect(currentScale)
                .offset(globalOffset)
                .allowsHitTesting(false)
        }
    }
}

private struct DraggableAndResizableBoxView: View {
    @Binding var analysis: FrameAnalysis
    let containerSize: CGSize
    let videoSize: CGSize
    let currentScale: CGFloat
    let globalOffset: CGSize
    let onEditEnded: () -> Void
    
    @GestureState private var liveDragOffset: CGSize = .zero
    @GestureState private var liveResizeOffset: CGSize = .zero

    var body: some View {
        if let box = analysis.boundingBox {
            let imageInfo = getScaledImageInfo(containerSize: containerSize, videoSize: videoSize)
            
            let staticPixelFrame = CGRect(
                x: imageInfo.origin.x + (box.origin.x * videoSize.width * imageInfo.scale),
                y: imageInfo.origin.y + (box.origin.y * videoSize.height * imageInfo.scale),
                width: box.size.width * videoSize.width * imageInfo.scale,
                height: box.size.height * videoSize.height * imageInfo.scale
            )
            
            let liveFrame = CGRect(
                x: staticPixelFrame.origin.x + liveDragOffset.width,
                y: staticPixelFrame.origin.y + liveDragOffset.height,
                width: staticPixelFrame.width + liveResizeOffset.width,
                height: staticPixelFrame.height + liveResizeOffset.height
            )

            ZStack {
                Rectangle().stroke(Color.red, lineWidth: 2 / currentScale)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(initialNormalizedBox: box, imageInfo: imageInfo))

                ResizeHandle(scale: currentScale)
                    .position(x: liveFrame.width, y: liveFrame.height)
                    .gesture(resizeGesture(initialNormalizedBox: box, imageInfo: imageInfo))
            }
            .frame(width: liveFrame.width, height: liveFrame.height)
            .position(x: liveFrame.midX, y: liveFrame.midY)
            .scaleEffect(currentScale)
            .offset(globalOffset)
        }
    }
    
    private struct ResizeHandle: View {
        let scale: CGFloat
        var body: some View {
            Rectangle().fill(Color.white.opacity(0.01)).frame(width: 25, height: 25)
                .overlay(
                    Circle().fill(Color.white).frame(width: 3, height: 3)
                        .overlay(Circle().stroke(Color.red, lineWidth: 2 / scale))
                ).scaleEffect(1 / scale)
        }
    }
    
    private func moveGesture(initialNormalizedBox: CGRect, imageInfo: (origin: CGPoint, scale: CGFloat)) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($liveDragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                var updatedBox = initialNormalizedBox
                
                let deltaX = value.translation.width / (videoSize.width * imageInfo.scale * currentScale)
                let deltaY = value.translation.height / (videoSize.height * imageInfo.scale * currentScale)
                
                updatedBox.origin.x = max(0, min(initialNormalizedBox.origin.x + deltaX, 1.0 - updatedBox.width))
                updatedBox.origin.y = max(0, min(initialNormalizedBox.origin.y + deltaY, 1.0 - updatedBox.height))
                
                analysis.boundingBox = updatedBox
                onEditEnded()
            }
    }
    
    private func resizeGesture(initialNormalizedBox: CGRect, imageInfo: (origin: CGPoint, scale: CGFloat)) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($liveResizeOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                var updatedBox = initialNormalizedBox
                
                let normDeltaX = value.translation.width / (videoSize.width * imageInfo.scale * currentScale)
                let normDeltaY = value.translation.height / (videoSize.height * imageInfo.scale * currentScale)
                
                let newWidth = max(0.01, updatedBox.width + normDeltaX)
                let newHeight = max(0.01, updatedBox.height + normDeltaY)
                
                updatedBox.size.width = min(newWidth, 1.0 - updatedBox.origin.x)
                updatedBox.size.height = min(newHeight, 1.0 - updatedBox.origin.y)
                
                analysis.boundingBox = updatedBox
                onEditEnded()
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
                    Text("Move").tag(ReviewView.EditMode.move)
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
            }.buttonStyle(.bordered).controlSize(.regular)
        }
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
