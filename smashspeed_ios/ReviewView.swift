//
//  ReviewView.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import SwiftUI
import AVFoundation
import Vision

struct ReviewView: View {
    let videoURL: URL
    @State private var analysisResults: [FrameAnalysis]
    let onFinish: ([FrameAnalysis]) -> Void
    
    @State private var currentIndex = 0
    @State private var currentFrameImage: UIImage?
    
    private let imageGenerator: AVAssetImageGenerator
    
    init(videoURL: URL, analysisResults: [FrameAnalysis], onFinish: @escaping ([FrameAnalysis]) -> Void) {
        self.videoURL = videoURL
        self._analysisResults = State(initialValue: analysisResults)
        self.onFinish = onFinish
        
        let asset = AVURLAsset(url: videoURL)
        self.imageGenerator = AVAssetImageGenerator(asset: asset)
        self.imageGenerator.appliesPreferredTrackTransform = true
        self.imageGenerator.requestedTimeToleranceBefore = .zero
        self.imageGenerator.requestedTimeToleranceAfter = .zero
    }

    var body: some View {
        VStack {
            Text("Frame \(currentIndex + 1) of \(analysisResults.count)")
                .font(.headline)
                .padding(.top)
            
            ZStack {
                if let image = currentFrameImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .overlay(
                            GeometryReader { geo in
                                DraggableAndResizableBoxView(
                                    analysis: $analysisResults[currentIndex],
                                    containerSize: geo.size
                                )
                            }
                        )
                } else {
                    Color.black; ProgressView().tint(.white)
                }
            }

            if let speed = currentFrameData?.speedKPH {
                Text(String(format: "%.1f km/h", speed)).font(.largeTitle).bold()
            } else {
                Text("No Speed Detected").font(.largeTitle).foregroundColor(.secondary)
            }
            if let timestamp = currentFrameData?.timestamp {
                Text("Timestamp: \(timestamp.seconds, specifier: "%.3f")s").font(.caption)
            }
            
            HStack(spacing: 20) {
                if currentFrameData?.boundingBox == nil {
                    Button(action: addBox) { Label("Add Box", systemImage: "plus.square") }
                } else {
                    Button(role: .destructive, action: removeBox) { Label("Remove Box", systemImage: "trash") }
                }
            }.padding(.top, 5)
            
            HStack(spacing: 20) {
                Button(action: goToPreviousFrame) { Label("Previous", systemImage: "arrow.left") }.disabled(currentIndex == 0)
                Button(action: goToNextFrame) { Label("Next", systemImage: "arrow.right") }.disabled(currentIndex >= analysisResults.count - 1)
            }.padding()
            
            Button("Finish & See Max Speed") { onFinish(analysisResults) }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
        }
        .task(id: currentIndex) {
            await loadFrame(at: currentIndex)
        }
    }
    
    private var currentFrameData: FrameAnalysis? {
        guard analysisResults.indices.contains(currentIndex) else { return nil }
        return analysisResults[currentIndex]
    }
    
    private func addBox() {
        guard analysisResults.indices.contains(currentIndex) else { return }
        analysisResults[currentIndex].boundingBox = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
    }
    
    private func removeBox() {
        analysisResults[currentIndex].boundingBox = nil
    }
    
    private func goToPreviousFrame() { if currentIndex > 0 { currentIndex -= 1 } }
    private func goToNextFrame() { if currentIndex < analysisResults.count - 1 { currentIndex += 1 } }
    
    private func loadFrame(at index: Int) async {
        guard let timestamp = currentFrameData?.timestamp else { return }
        do {
            let cgImage = try await imageGenerator.image(at: timestamp).image
            currentFrameImage = UIImage(cgImage: cgImage)
        } catch {
            print("Failed to load frame for timestamp \(timestamp): \(error)")
        }
    }
}

// MARK: - DraggableAndResizableBoxView
struct DraggableAndResizableBoxView: View {
    @Binding var analysis: FrameAnalysis
    let containerSize: CGSize

    var body: some View {
        // We only show the view if a bounding box exists
        if let box = analysis.boundingBox {
            // Convert normalized box to pixel dimensions for drawing
            let pixelFrame = CGRect(
                x: box.origin.x * containerSize.width,
                y: box.origin.y * containerSize.height,
                width: box.size.width * containerSize.width,
                height: box.size.height * containerSize.height
            )

            // A ZStack to layer the box, its move gesture, and resize handles
            ZStack(alignment: .topLeading) {
                // The main rectangle for the bounding box
                Rectangle()
                    .stroke(Color.red, lineWidth: 2)
                    .contentShape(Rectangle()) // Make the whole area tappable for moving
                    .gesture(moveGesture(initialFrame: pixelFrame))

                // Top-Left resize handle
                ResizeHandle()
                    .position(x: 0, y: 0) // Position at the top-left of the frame
                    .gesture(resizeGesture(initialFrame: pixelFrame, corner: .topLeft))
                
                // Bottom-Right resize handle
                ResizeHandle()
                    .position(x: pixelFrame.width, y: pixelFrame.height) // Position at the bottom-right
                    .gesture(resizeGesture(initialFrame: pixelFrame, corner: .bottomRight))
            }
            .frame(width: pixelFrame.width, height: pixelFrame.height)
            .position(x: pixelFrame.midX, y: pixelFrame.midY) // Position the ZStack itself
        }
    }

    // A helper view for the circular resize handles
    struct ResizeHandle: View {
        var body: some View {
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.red, lineWidth: 2))
        }
    }

    // Enum to identify which corner is being dragged
    enum Corner {
        case topLeft, bottomRight
    }
    
    // A gesture for moving the entire box
    private func moveGesture(initialFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let newOriginX = (initialFrame.origin.x + value.translation.width) / containerSize.width
                let newOriginY = (initialFrame.origin.y + value.translation.height) / containerSize.height
                
                var updatedBox = analysis.boundingBox ?? .zero
                updatedBox.origin.x = max(0, min(newOriginX, 1.0 - updatedBox.width))
                updatedBox.origin.y = max(0, min(newOriginY, 1.0 - updatedBox.height))
                
                analysis.boundingBox = updatedBox
            }
    }
    
    // A gesture for resizing the box from a corner
    private func resizeGesture(initialFrame: CGRect, corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                var updatedBox = analysis.boundingBox ?? .zero
                let dragTranslation = value.translation
                
                // Normalize the drag translation
                let normDeltaX = dragTranslation.width / containerSize.width
                let normDeltaY = dragTranslation.height / containerSize.height

                switch corner {
                case .topLeft:
                    // Adjust origin and size, ensuring size doesn't become negative
                    let newOriginX = updatedBox.origin.x + normDeltaX
                    let newOriginY = updatedBox.origin.y + normDeltaY
                    let newWidth = updatedBox.width - normDeltaX
                    let newHeight = updatedBox.height - normDeltaY

                    if newWidth > 0 && newHeight > 0 {
                        updatedBox.origin.x = newOriginX
                        updatedBox.origin.y = newOriginY
                        updatedBox.size.width = newWidth
                        updatedBox.size.height = newHeight
                    }

                case .bottomRight:
                    // Adjust size, ensuring it doesn't become negative
                    let newWidth = updatedBox.width + normDeltaX
                    let newHeight = updatedBox.height + normDeltaY

                    if newWidth > 0 && newHeight > 0 {
                        updatedBox.size.width = newWidth
                        updatedBox.size.height = newHeight
                    }
                }
                
                // Clamp the final rect to the 0.0-1.0 bounds
                updatedBox.origin.x = max(0, updatedBox.origin.x)
                updatedBox.origin.y = max(0, updatedBox.origin.y)
                updatedBox.size.width = min(updatedBox.size.width, 1.0 - updatedBox.origin.x)
                updatedBox.size.height = min(updatedBox.size.height, 1.0 - updatedBox.origin.y)
                
                analysis.boundingBox = updatedBox
            }
    }
}
