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

    @State private var showInfoSheet: Bool = false

    var body: some View {
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

            VStack(spacing: 0) {
                // MODIFIED: The top bar now uses an overlay to guarantee a centered title.
                HStack {
                    Button("Cancel", action: onCancel).padding()
                    Spacer()
                    Button {
                        showInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle").font(.title3)
                    }
                    .padding()
                }
                .frame(height: 44) // A standard height for the bar
                .overlay(
                    Text("Calibration").font(.headline) // This text is perfectly centered.
                )
                .background(.ultraThinMaterial)

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
                                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))

                                    CalibrationHandleView(position: $point1, liveOffset: $liveOffset1, viewSize: viewSize)
                                    CalibrationHandleView(position: $point2, liveOffset: $liveOffset2, viewSize: viewSize)
                                }
                            )
                            .background(
                                GeometryReader { geo in
                                    Color.clear.onAppear {
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
                
                VStack(spacing: 16) {
                    
                    HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                                .padding(.top, 2)
                            Text("Place one point on the front service line and the other on the doubles long service (flick) line.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "cursorarrow.motionlines")
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .padding(.top, 2)
                        Text("Tip: Drag from the area around a point to avoid covering it with your finger.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        Divider()
                    
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
        .sheet(isPresented: $showInfoSheet) {
            OnboardingSheetContainerView {
                OnboardingInstructionView(
                    slideIndex: 0,
                    currentTab: .constant(0),
                    imageNames: ["OnboardingSlide2.1","OnboardingSlide2.2","OnboardingSlide2.3"],
                    title: "2. Mark a Known Distance",
                    instructions: [
                        (icon: "scope", text: "Mark the front service line and doubles service line — 3.87 m apart."),
                        (icon: "person.fill", text: "Place the line directly under the player."),
                        (icon: "ruler.fill", text: "Keep 3.87 m unless using different lines — changing it may reduce accuracy.")
                    ]
                )
            }
        }
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
                #if DEBUG
                print("Failed to load first frame: \(error)")
                #endif
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
                
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .blur(radius: 150)
                    .offset(x: -150, y: -200)

                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .blur(radius: 180)
                    .offset(x: 150, y: 150)
                
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


private struct CalibrationHandleView: View {
    @Binding var position: CGPoint
    @Binding var liveOffset: CGSize
    let viewSize: CGSize
    
    @State private var isDragging: Bool = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 80, height: 80)
                .opacity(isDragging ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: isDragging)
            
            ZStack {
                Path { path in
                    let width: CGFloat = 24
                    let height: CGFloat = 32
                    path.move(to: CGPoint(x: width / 2, y: height))
                    path.addCurve(to: CGPoint(x: 0, y: height / 2.5),
                                  control1: CGPoint(x: width / 2, y: height * 0.8),
                                  control2: CGPoint(x: 0, y: height * 0.65))
                    path.addArc(center: CGPoint(x: width / 2, y: height / 2.5),
                                radius: width / 2,
                                startAngle: .degrees(180),
                                endAngle: .degrees(0),
                                clockwise: false)
                    path.addCurve(to: CGPoint(x: width / 2, y: height),
                                  control1: CGPoint(x: width, y: height * 0.65),
                                  control2: CGPoint(x: width / 2, y: height * 0.8))
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.red.opacity(0.8), Color.red]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 24, height: 32)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .offset(y: -4)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .offset(y: 16)
            }
            .offset(y: -16)
            .shadow(color: .black.opacity(0.3), radius: 5, y: 4)
        }
        .contentShape(Rectangle().inset(by: -40))
        .position(
            x: position.x + liveOffset.width,
            y: position.y + liveOffset.height
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    self.isDragging = true
                    self.liveOffset = value.translation
                }
                .onEnded { value in
                    let newX = position.x + value.translation.width
                    let newY = position.y + value.translation.height
                    
                    position.x = min(max(0, newX), viewSize.width)
                    position.y = min(max(0, newY), viewSize.height)
                    
                    self.liveOffset = .zero
                    self.isDragging = false
                }
        )
    }
}
