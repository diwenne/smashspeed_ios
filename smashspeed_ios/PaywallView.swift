import SwiftUI
import StoreKit

// --- UNIFIED BUTTON STYLE ---
// We now only need one style to make the buttons look identical.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.bold())
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .foregroundColor(.accentColor)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}


struct PaywallView: View {
    @EnvironmentObject var storeManager: StoreManager
    @Binding var isPresented: Bool
    
    @State private var isPurchasing = false
    @State private var purchasingProduct: Product?
    
    private var sortedProducts: [Product] {
        storeManager.products.sorted { $0.price > $1.price }
    }
    
    // MARK: - Main Body
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
            Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)
            
            VStack(spacing: 20) {
                headerAndFeaturesView
                Spacer()
                purchaseButtonsView
            }
            .padding(30)
            
            closeButton
        }
    }
    
    // MARK: - Helper Views
    private var headerAndFeaturesView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Upgrade to Pro")
                    .font(.largeTitle.bold())
                    .padding(.top, 40)
                
                Text("Unlock all features and smash your limits!")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 15) {
                    FeatureRow(icon: "camera.metering.unknown", title: "Unlimited Smashes", subtitle: "Analyze as many videos as you want.")
                    FeatureRow(icon: "ruler.fill", title: "Precise Smash Angle", subtitle: "Unlock angle calculation for tactical insights.")
                    FeatureRow(icon: "chart.bar.xaxis", title: "Full History", subtitle: "Track your progress over time.")
                    FeatureRow(icon: "sparkles", title: "Priority Access", subtitle: "Get new features and AI models first.")
                }
                .padding(30)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
            }
        }
    }
    
    private var purchaseButtonsView: some View {
        VStack(spacing: 12) {
            if storeManager.products.isEmpty {
                ProgressView()
            } else {
                ForEach(sortedProducts) { product in
                    // --- STYLE SIMPLIFIED ---
                    // Both buttons now use the exact same style.
                    Button(action: { purchase(product: product) }) {
                        purchaseButtonLabel(for: product)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
            }
            
            Button("Restore Purchases") {
                Task { await storeManager.restorePurchases() }
            }
            .font(.footnote)
            .padding(.top, 5)
        }
    }

    @ViewBuilder
    private func purchaseButtonLabel(for product: Product) -> some View {
        if purchasingProduct?.id == product.id {
            ProgressView().tint(.accentColor)
        } else {
            // --- TEXT SIMPLIFIED ---
            // The crossed-off price is removed for a cleaner look.
            let isYearly = product.subscription?.subscriptionPeriod.unit == .year
            Text(isYearly ? "Yearly - \(product.displayPrice)" : "Monthly - \(product.displayPrice)")
                .fontWeight(.bold)
        }
    }
    
    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Functions
    func purchase(product: Product) {
        Task {
            isPurchasing = true
            purchasingProduct = product
            do {
                try await storeManager.purchase(product)
            } catch {
                print("Purchase failed: \(error)")
            }
            isPurchasing = false
            purchasingProduct = nil
            isPresented = false
        }
    }
}

// MARK: - Helper Structs
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
                .buttonStyle(OutlineButtonStyle())
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
    }
}
