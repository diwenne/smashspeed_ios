import SwiftUI
import UIKit

// MARK: - Sharing Components

struct SharePreviewView: View {
    @Environment(\.dismiss) var dismiss
    let image: UIImage
    @State private var showShareSheet = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // LOCALIZED
                Text("share_preview_title").font(.headline)
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.2), radius: 8)
                Spacer()
                Button { showShareSheet = true } label: {
                    // LOCALIZED
                    Label("share_preview_shareButton", systemImage: "square.and.arrow.up").fontWeight(.bold).frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)
            }
            .padding()
            .toolbar {
                // LOCALIZED
                ToolbarItem(placement: .cancellationAction) { Button("common_cancel") { dismiss() } }
            }
            .sheet(isPresented: $showShareSheet) { ShareSheet(activityItems: [image]) }
        }
    }
}

struct ShareableView: View {
    let speed: Double
    let angle: Double?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Circle().fill(Color.blue.opacity(0.8))
                .blur(radius: 120)
                .offset(x: -120, y: -200)
            Circle().fill(Color.blue.opacity(0.5))
                .blur(radius: 150)
                .offset(x: 120, y: 150)

            VStack(spacing: 16) {
                AppLogoView()
                    .scaleEffect(0.95)
                    .padding(.top, 20)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f", speed))
                        .font(.system(size: 80, weight: .heavy, design: .rounded))
                        .foregroundColor(.accentColor)
                    Text("common_kmh")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    if let angle = angle {
                        VStack {
                            Divider().padding(.vertical, 4)
                            HStack {
                                Text("resultView_smashAngleLabel")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                
                                // ** THIS IS THE CORRECTED CODE **
                                (
                                    Text(angle, format: .number.precision(.fractionLength(0))) +
                                    Text("° ") +
                                    Text("common_angle_downward") // Now uses the merged key
                                )
                                .font(.headline.bold())
                                .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal, 15)
                        .padding(.top, 5)
                    }
                }
                .padding(22)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                VStack(spacing: 1) {
                    Text("share_image_generatedBy")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary.opacity(0.8))
                    Text("share_image_socialHandle")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: 320)
            .padding(.vertical, 40)
        }
        .frame(width: 414, height: 736)
    }
}

// MARK: - Reusable Helper Views & Extensions

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: activityItems, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension UIImage: Identifiable {
    public var id: String { return UUID().uuidString }
}

extension View {
    @MainActor func snapshot() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}
