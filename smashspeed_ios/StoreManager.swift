//
//  StoreManager.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-09-18.
//


import Foundation
import StoreKit

// Define your product IDs
let proMonthlyProductID = "smashspeed_pro_monthly" // 👈 Replace with your actual Product ID

@MainActor
class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isSubscribed: Bool = false
    
    private var transactionListener: Task<Void, Error>? = nil

    init() {
        // Start a task to listen for transaction updates
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }
    
    // Fetch products from the App Store
    func fetchProducts() async {
        do {
            let storeProducts = try await Product.products(for: [proMonthlyProductID])
            self.products = storeProducts
        } catch {
            print("Failed to fetch products: \(error)")
        }
    }
    
    // Purchase a product
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateSubscriptionStatus()
            await transaction.finish()
        case .pending:
            // The purchase is pending, e.g., needs parental approval.
            // The transaction listener will handle the final result.
            break
        case .userCancelled:
            break
        @unknown default:
            break
        }
    }
    
    // Force a sync with the App Store, useful for "Restore Purchases"
    func restorePurchases() async {
        try? await AppStore.sync()
    }

    // Update the user's subscription status
    func updateSubscriptionStatus() async {
        var validSubscription: Transaction?
        
        // Iterate through all of the user's purchased products
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                // Find the latest subscription transaction
                if transaction.revocationDate == nil && !transaction.isUpgraded {
                    validSubscription = transaction
                }
            }
        }
        
        self.isSubscribed = validSubscription != nil
    }

    // Listen for transaction updates from the App Store
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    // The transaction is valid, update the subscription status
                    await self.updateSubscriptionStatus()
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification: \(error)")
                }
            }
        }
    }

    // Helper to verify the transaction
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.unknown // Or a custom error
        case .verified(let safe):
            return safe
        }
    }
}
