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
    @State private var imageSize: CGSize = .zero

    var body: some View {
        ZStack {
            // Layer 1: A light system background that fills the whole screen
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            // Layer 2: The video frame, scaled to fit perfectly
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

                            HandleView(position: $point1, imageSize: imageSize)
                            HandleView(position: $point2, imageSize: imageSize)
                        }
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear.onAppear {
                                self.imageSize = geo.size
                                self.point1 = CGPoint(x: geo.size.width * 0.4, y: geo.size.height * 0.4)
                                self.point2 = CGPoint(x: geo.size.width * 0.6, y: geo.size.height * 0.6)
                            }
                        }
                    )
            } else {
                // Show a spinner while the frame is loading
                ProgressView()
            }

            // Layer 3: The UI controls, placed on top of everything else
            VStack {
                // Top Cancel Button
                HStack {
                    Button("Cancel", action: onCancel)
                        .padding()
                        // Use a modern "material" background for a frosted glass look
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding()

                Spacer() // Pushes the bottom controls down

                // Bottom Control Panel
                VStack(spacing: 16) {
                    Text("Drag the handles to measure an object of known length.")
                        .font(.subheadline)
                        // .primary color automatically adapts to light/dark mode
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text("Real-world length (meters):")
                            .foregroundColor(.primary)
                        TextField("1.55", text: $referenceLength)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    Button(action: calculateAndProceed) {
                        Text("Start Analysis")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(firstFrame == nil || Double(referenceLength) == nil)
                }
                .padding()
                // Use the same modern material background for the panel
                .background(.regularMaterial)
                .cornerRadius(20)
                .padding(.horizontal)
            }
        }
        .onAppear(perform: loadFirstFrame)
    }
    
    private func loadFirstFrame() {
        Task {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            do {
                let cgImage = try await generator.image(at: .zero).image
                self.firstFrame = UIImage(cgImage: cgImage)
            } catch {
                print("Failed to load first frame: \(error)")
                onCancel()
            }
        }
    }
    
    private func calculateAndProceed() {
        guard let realLength = Double(referenceLength), realLength > 0 else { return }
        let pixelDistance = sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))
        guard pixelDistance > 0 else { return }
        let scaleFactor = realLength / pixelDistance
        onComplete(scaleFactor)
    }
}


struct HandleView: View {
    @Binding var position: CGPoint
    let imageSize: CGSize
    
    var body: some View {
        Circle()
            .fill(Color.red).frame(width: 24, height: 24)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(radius: 3)
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newX = min(max(0, value.location.x), imageSize.width)
                        let newY = min(max(0, value.location.y), imageSize.height)
                        self.position = CGPoint(x: newX, y: newY)
                    }
            )
    }
}

#Preview {
    let previewURL = URL(string: "file:///preview.mov")!
    return CalibrationView(videoURL: previewURL, onComplete: { _ in }, onCancel: { })
}
