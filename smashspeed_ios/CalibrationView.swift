//
//  CalibrationView.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import SwiftUI
import AVFoundation

struct CalibrationView: View {
    let videoURL: URL
    let onComplete: (Double) -> Void
    let onCancel: () -> Void
    
    // Enum to identify which handle is active
    enum ActiveHandle {
        case point1, point2
    }
    
    @State private var firstFrame: UIImage?
    @State private var referenceLength: String = "3.87"
    @State private var point1: CGPoint = .zero
    @State private var point2: CGPoint = .zero
    
    // The size of the Image view on screen, in POINTS
    @State private var viewSize: CGSize = .zero
    // The size of the original video, in PIXELS
    @State private var videoPixelSize: CGSize = .zero
    
    // State to track which handle is currently selected for fine-tuning
    @State private var activeHandle: ActiveHandle = .point1

    var body: some View {
        VStack(spacing: 0) {
            // Top Cancel Button
            HStack {
                Button("Cancel", action: onCancel)
                    .padding()
                Spacer()
                Text("Calibration")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: {})
                    .padding().opacity(0) // Hidden button for symmetrical spacing
            }
            .background(Color(uiColor: .systemGroupedBackground))

            // The video frame
            ZStack {
                if let image = firstFrame {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .overlay(
                            ZStack {
                                Path { path in
                                    path.move(to: point1)
                                    path.addLine(to: point2)
                                }
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [5]))

                                CalibrationHandleView(position: $point1, viewSize: viewSize, isActive: activeHandle == .point1)
                                CalibrationHandleView(position: $point2, viewSize: viewSize, isActive: activeHandle == .point2)
                            }
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    // Set the initial state based on the view's geometry
                                    self.viewSize = geo.size
                                    self.point1 = CGPoint(x: geo.size.width * 0.4, y: geo.size.height * 0.4)
                                    self.point2 = CGPoint(x: geo.size.width * 0.6, y: geo.size.height * 0.6)
                                }
                            }
                        )
                } else {
                    ProgressView()
                }
            }
            .frame(maxHeight: .infinity)
            
            // Fine-tuning control panel
            VStack(spacing: 12) {
                Picker("Selected Handle", selection: $activeHandle) {
                    Text("Point 1").tag(ActiveHandle.point1)
                    Text("Point 2").tag(ActiveHandle.point2)
                }
                .pickerStyle(.segmented)
                
                HStack(spacing: 20) {
                    Spacer()
                    CalibrationFineTuneButton(icon: "arrow.left") { adjustActiveHandle(dx: -1, dy: 0) }
                    VStack(spacing: 10) {
                        CalibrationFineTuneButton(icon: "arrow.up") { adjustActiveHandle(dx: 0, dy: -1) }
                        CalibrationFineTuneButton(icon: "arrow.down") { adjustActiveHandle(dx: 0, dy: 1) }
                    }
                    CalibrationFineTuneButton(icon: "arrow.right") { adjustActiveHandle(dx: 1, dy: 0) }
                    Spacer()
                }
                
                HStack {
                    Text("Length (m):")
                    TextField("3.87", text: $referenceLength)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 10)
                
                Button("Start Analysis", action: calculateAndProceed)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(firstFrame == nil)
            }
            .padding().padding(.bottom).background(Color(uiColor: .systemGroupedBackground))
        }
        .onAppear(perform: loadFirstFrame)
    }
    
    private func adjustActiveHandle(dx: CGFloat, dy: CGFloat) {
        let sensitivity: CGFloat = 0.5
        var pointToAdjust: Binding<CGPoint>
        
        switch activeHandle {
        case .point1: pointToAdjust = $point1
        case .point2: pointToAdjust = $point2
        }
        
        let newX = pointToAdjust.wrappedValue.x + (dx * sensitivity)
        let newY = pointToAdjust.wrappedValue.y + (dy * sensitivity)
        
        pointToAdjust.wrappedValue.x = min(max(0, newX), viewSize.width)
        pointToAdjust.wrappedValue.y = min(max(0, newY), viewSize.height)
    }
    
    private func loadFirstFrame() {
        Task {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            
            // Also load the video track to get its true pixel dimensions
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                print("Failed to load video track.")
                onCancel()
                return
            }
            let size = try await videoTrack.load(.naturalSize)
            
            do {
                let cgImage = try await generator.image(at: .zero).image
                // Update state on the main thread
                await MainActor.run {
                    self.firstFrame = UIImage(cgImage: cgImage)
                    self.videoPixelSize = size
                }
            } catch {
                print("Failed to load first frame: \(error)")
                onCancel()
            }
        }
    }
    
    private func calculateAndProceed() {
        guard let realLength = Double(referenceLength), realLength > 0 else { return }
        guard videoPixelSize != .zero, viewSize != .zero else {
            print("Error: View size or video pixel size is not available.")
            return
        }

        // 1. Calculate the distance between handles in POINTS (the on-screen coordinate system)
        let pointDistance = sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))

        // 2. Determine the scaling ratio that .scaledToFit() applied to the image.
        // This gives us the relationship between the on-screen points and the video's original pixels.
        let scaleRatio = min(viewSize.width / videoPixelSize.width, viewSize.height / videoPixelSize.height)
        
        // 3. Convert the on-screen POINT distance to the equivalent PIXEL distance on the original video frame.
        let pixelDistance = pointDistance / scaleRatio

        print("On-screen distance: \(pointDistance) pts")
        print("Video pixel size: \(videoPixelSize)")
        print("On-screen view size: \(viewSize)")
        print("UI Scale Ratio (pts/px): \(scaleRatio)")
        print("Calculated pixel distance: \(pixelDistance) px")

        guard pixelDistance > 0 else { return }
        
        print("px difference: \(pixelDistance)")
        
        // 4. Calculate the final scaleFactor (meters per PIXEL)
        let scaleFactor = realLength / pixelDistance
        print("Final Scale factor (m/px): \(scaleFactor)")
        onComplete(scaleFactor)
    }
}


// MARK: - Helper Views for CalibrationView

private struct CalibrationHandleView: View {
    @Binding var position: CGPoint
    let viewSize: CGSize
    let isActive: Bool
    
    var body: some View {
        // A larger, invisible tappable area
        Rectangle()
            .fill(Color.white.opacity(0.01))
            .frame(width: 44, height: 44)
            .overlay(
                // The small, visible circle drawn on top
                Circle()
                    .fill(isActive ? Color.blue : Color.red)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(radius: 3)
            )
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newX = value.location.x
                        let newY = value.location.y
                        // Clamp the position to be within the view's bounds
                        self.position.x = min(max(0, newX), viewSize.width)
                        self.position.y = min(max(0, newY), viewSize.height)
                    }
            )
    }
}

private struct CalibrationFineTuneButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

