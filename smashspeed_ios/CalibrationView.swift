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
    
    @State private var firstFrame: UIImage?
    @State private var referenceLength: String = "3.87"
    @State private var point1: CGPoint = .zero
    @State private var point2: CGPoint = .zero
    
    @State private var viewSize: CGSize = .zero
    @State private var videoPixelSize: CGSize = .zero
    
    @State private var liveOffset1: CGSize = .zero
    @State private var liveOffset2: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Button("Cancel", action: onCancel).padding()
                Spacer()
                Text("Calibration").font(.headline)
                Spacer()
                Button("Cancel", action: {}).padding().opacity(0)
            }
            .background(Color(.systemGroupedBackground))

            // The video frame
            ZStack {
                if let image = firstFrame {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .overlay(
                            ZStack {
                                Path { path in
                                    path.move(to: CGPoint(x: point1.x + liveOffset1.width, y: point1.y + liveOffset1.height))
                                    path.addLine(to: CGPoint(x: point2.x + liveOffset2.width, y: point2.y + liveOffset2.height))
                                }
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [5]))

                                // The handles no longer need an "isActive" state
                                CalibrationHandleView(position: $point1, liveOffset: $liveOffset1, viewSize: viewSize)
                                CalibrationHandleView(position: $point2, liveOffset: $liveOffset2, viewSize: viewSize)
                            }
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
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
            
            // Control Panel
            VStack(spacing: 16) {
                // --- The Picker has been removed ---
                
                Section {
                    HStack {
                        Label("Reference Length", systemImage: "ruler")
                        Spacer()
                        TextField("3.87", text: $referenceLength)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("meters")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.background)
                    .cornerRadius(12)
                } header: {
                    Text("Known Distance")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top])
                } footer: {
                    Text("Enter the real-world distance between the two red points. ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                
                Button("Start Analysis", action: calculateAndProceed)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .disabled(firstFrame == nil)
            }
            .padding(.vertical).background(Color(uiColor: .systemGroupedBackground))
        }
        .onAppear(perform: loadFirstFrame)
    }
    
    private func loadFirstFrame() {
        Task {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            
            guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
                onCancel()
                return
            }
            let size = try await videoTrack.load(.naturalSize)
            
            do {
                let cgImage = try await generator.image(at: .zero).image
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
        guard videoPixelSize != .zero, viewSize != .zero else { return }

        let pointDistance = sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))
        let scaleRatio = min(viewSize.width / videoPixelSize.width, viewSize.height / videoPixelSize.height)
        guard scaleRatio > 0 else { return }
        let pixelDistance = pointDistance / scaleRatio

        guard pixelDistance > 0 else { return }
        
        let scaleFactor = realLength / pixelDistance
        onComplete(scaleFactor)
    }
}


// MARK: - Helper Views for CalibrationView

private struct CalibrationHandleView: View {
    @Binding var position: CGPoint
    @Binding var liveOffset: CGSize
    let viewSize: CGSize
    
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(radius: 3)
            // It creates an invisible tappable shape that is 30 points
            // larger (15 on each side) than the visible circle.
            .contentShape(Rectangle().inset(by: -32))
            .position(
                x: position.x + liveOffset.width,
                y: position.y + liveOffset.height
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        self.liveOffset = value.translation
                    }
                    .onEnded { value in
                        let newX = position.x + value.translation.width
                        let newY = position.y + value.translation.height
                        
                        position.x = min(max(0, newX), viewSize.width)
                        position.y = min(max(0, newY), viewSize.height)
                        
                        self.liveOffset = .zero
                    }
            )
    }
}
