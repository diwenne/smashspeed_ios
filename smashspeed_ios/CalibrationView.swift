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

    // 1. New state to control the info sheet's visibility
    @State private var showInfoSheet: Bool = false

    var body: some View {
        ZStack {
            // A monochromatic blue aurora background to match other views.
            Color(.systemBackground).ignoresSafeArea()
            
            Circle()
                .fill(Color.blue.opacity(0.8))
                .blur(radius: 150)
                .offset(x: -150, y: -200)

            Circle()
                .fill(Color.blue.opacity(0.5))
                .blur(radius: 180)
                .offset(x: 150, y: 150)

            // Main layout container
            VStack(spacing: 0) {
                // Top Bar with a subtle glass effect
                HStack {
                    Button("Cancel", action: onCancel).padding()
                    Spacer()
                    Text("Calibration").font(.headline)
                    Spacer()
                    // 2. Replaced the old spacing button with a new info button
                    Button {
                        showInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3) // A slightly larger, more tappable size
                    }
                    .padding()
                }
                .background(.ultraThinMaterial)

                // The video frame where calibration happens
                ZStack {
                    if let image = firstFrame {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .overlay(
                                ZStack {
                                    // The dashed line connecting the two handles
                                    Path { path in
                                        path.move(to: CGPoint(x: point1.x + liveOffset1.width, y: point1.y + liveOffset1.height))
                                        path.addLine(to: CGPoint(x: point2.x + liveOffset2.width, y: point2.y + liveOffset2.height))
                                    }
                                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))

                                    // The two draggable calibration handles
                                    CalibrationHandleView(position: $point1, liveOffset: $liveOffset1, viewSize: viewSize)
                                    CalibrationHandleView(position: $point2, liveOffset: $liveOffset2, viewSize: viewSize)
                                }
                            )
                            .background(
                                GeometryReader { geo in
                                    Color.clear.onAppear {
                                        // Initialize the positions of the handles when the view appears
                                        self.viewSize = geo.size
                                        self.point1 = CGPoint(x: geo.size.width * 0.3, y: geo.size.height * 0.8)
                                        self.point2 = CGPoint(x: geo.size.width * 0.7, y: geo.size.height * 0.8)
                                    }
                                }
                            )
                    } else {
                        ProgressView().scaleEffect(1.5)
                    }
                }
                .frame(maxHeight: .infinity)
                
                // Control Panel on a single, clean GlassPanel
                VStack(spacing: 16) {
                    VStack {
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
                        Divider()
                        Text("Enter the real-world distance between the two points.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Button("Start Analysis", action: calculateAndProceed)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(firstFrame == nil)
                }
                .padding(30)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                .padding()
            }
        }
        .onAppear(perform: loadFirstFrame)
        // 3. Add the .sheet modifier to present the onboarding slide
        .sheet(isPresented: $showInfoSheet) {
            OnboardingSheetContainerView {
                // 4. This is the specific onboarding slide you wanted to show
                OnboardingInstructionView(
                    imageNames: ["OnboardingSlide2.1","OnboardingSlide2.2","OnboardingSlide2.3"],
                    title: "2. Mark a Known Distance",
                    instructions: [
                        (icon: "scope", text: "Place one point on the front service line and one on the doubles flick line — 3.87 m apart."),
                        (icon: "person.fill", text: "Points must be aligned with the player’s position — along the same depth from the camera."),
                        (icon: "ruler.fill", text: "The default length is 3.87 m. Only change it if you used a different line — this may reduce accuracy.")
                    ]
                )
            }
        }
    }
    
    /// Asynchronously loads the first frame of the selected video to be used as a still image.
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
                #if DEBUG
                print("Failed to load first frame: \(error)")
                #endif
                onCancel()
            }
        }
    }
    
    /// Calculates the scale factor and proceeds to the next view.
    private func calculateAndProceed() {
        guard let realLength = Double(referenceLength), realLength > 0 else { return }
        guard videoPixelSize != .zero, viewSize != .zero else { return }

        // Calculate the distance between the two points in the view's coordinate space
        let pointDistance = sqrt(pow(point2.x - point1.x, 2) + pow(point2.y - point1.y, 2))
        
        // Determine how much the video was scaled to fit the screen
        let scaleRatio = min(viewSize.width / videoPixelSize.width, viewSize.height / videoPixelSize.height)
        guard scaleRatio > 0 else { return }
        
        // Convert the on-screen distance to the video's actual pixel distance
        let pixelDistance = pointDistance / scaleRatio
        guard pixelDistance > 0 else { return }
        
        // The final scale factor is the ratio of real-world length to pixel distance
        let scaleFactor = realLength / pixelDistance
        onComplete(scaleFactor)
    }
}

// MARK: - Onboarding Sheet Container
// A generic container to display any onboarding content in a sheet with a dismiss button.
private struct OnboardingSheetContainerView<Content: View>: View {
    @Environment(\.dismiss) var dismiss
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // Use a NavigationStack to get a toolbar for the dismiss button
        NavigationStack {
            // The background styling from the main OnboardingView
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .blur(radius: 150)
                    .offset(x: -150, y: -200)

                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .blur(radius: 180)
                    .offset(x: 150, y: 150)
                
                // Your provided content
                content
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


// MARK: - Helper Views for CalibrationView

/// A draggable handle view shaped like a pin for precise placement.
private struct CalibrationHandleView: View {
    @Binding var position: CGPoint
    @Binding var liveOffset: CGSize
    let viewSize: CGSize
    
    var body: some View {
        // A custom pin-style handle, which is larger and more precise than a circle.
        // The logical position of this view is the very bottom tip of the pin.
        ZStack {
            // The main pin body, drawn as a custom teardrop shape.
            Path { path in
                let width: CGFloat = 24
                let height: CGFloat = 32
                // Start at the bottom tip
                path.move(to: CGPoint(x: width / 2, y: height))
                // Add curves to create the rounded sides
                path.addCurve(to: CGPoint(x: 0, y: height / 2.5),
                              control1: CGPoint(x: width / 2, y: height * 0.8),
                              control2: CGPoint(x: 0, y: height * 0.65))
                // Add the top arc
                path.addArc(center: CGPoint(x: width / 2, y: height / 2.5),
                            radius: width / 2,
                            startAngle: .degrees(180),
                            endAngle: .degrees(0),
                            clockwise: false)
                // Add the other side's curve back to the tip
                path.addCurve(to: CGPoint(x: width / 2, y: height),
                              control1: CGPoint(x: width, y: height * 0.65),
                              control2: CGPoint(x: width / 2, y: height * 0.8))
            }
            .fill(
                // MODIFIED: Changed to a more intuitive red color for marking points.
                LinearGradient(
                    gradient: Gradient(colors: [Color.red.opacity(0.8), Color.red]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 24, height: 32)
            
            // An inner white dot for contrast, acting as the "head" of the pin.
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                // Position the dot within the upper part of the teardrop.
                .offset(y: -4)
            
            // ADDED: A small white circle at the very bottom to make the tip obvious.
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                // Position the circle at the bottom of the ZStack's frame.
                .offset(y: 16)
        }
        // The entire ZStack is offset upwards. This makes the bottom tip of the pin
        // align with the view's logical center, ensuring precise placement.
        .offset(y: -16)
        .shadow(color: .black.opacity(0.3), radius: 5, y: 4) // A more realistic shadow for depth
        .contentShape(Rectangle().inset(by: -40)) // Keep a large, invisible tappable area
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
                    
                    // Clamp the position to the bounds of the view
                    position.x = min(max(0, newX), viewSize.width)
                    position.y = min(max(0, newY), viewSize.height)
                    
                    self.liveOffset = .zero
                }
        )
    }
}
