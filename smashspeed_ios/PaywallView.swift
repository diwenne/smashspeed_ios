import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var storeManager: StoreManager
    @Binding var isPresented: Bool
    
    @State private var isPurchasing = false
    @State private var errorTitle = ""
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
            Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)
            
            VStack(spacing: 20) {
                Spacer()
                Text("Upgrade to Pro")
                    .font(.largeTitle.bold())
                
                Text("Unlock all features and smash your limits!")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 15) {
                    FeatureRow(icon: "camera.metering.unknown", title: "Unlimited Smashes", subtitle: "Analyze as many videos as you want, every month.")
                    FeatureRow(icon: "chart.bar.xaxis", title: "Full History", subtitle: "Access your complete analysis history and track your progress.")
                    FeatureRow(icon: "arrow.up.right.video.fill", title: "More Features Soon", subtitle: "Get access to all new features as they are released.")
                }
                .padding(30)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))

                if storeManager.products.isEmpty {
                    ProgressView()
                        .padding()
                }

                ForEach(storeManager.products) { product in
                    Button(action: { purchase(product: product) }) {
                        if isPurchasing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            // --- MODIFIED LINE ---
                            // This provides a clearer call to action and removes the dash.
                            Text("Subscribe for \(product.displayPrice)")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isPurchasing)
                }
                
                Button("Restore Purchases") {
                    Task { await storeManager.restorePurchases() }
                }
                .font(.footnote)
                .padding(.top, 5)
                
                Spacer()
            }
            .padding(30)
            .overlay(
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            )
        }
        .alert(errorTitle, isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    func purchase(product: Product) {
        Task {
            isPurchasing = true
            do {
                try await storeManager.purchase(product)
                isPresented = false
            } catch {
                errorTitle = "Purchase Failed"
                errorMessage = "There was an error processing your purchase. Please try again."
                showError = true
            }
            isPurchasing = false
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundColor(.secondary)
            }
        }
    }
}


struct LockedFeatureView: View {
    let title: String
    let description: String
    let onUpgrade: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text(title)
                .font(.title.bold())
            
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Upgrade to Pro", action: onUpgrade)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
    }
}
