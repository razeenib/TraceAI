import Foundation
import Observation
import OSLog
import StoreKit

enum PaywallPlacement {
    static let unlockLayers = "unlock_4_step_breakdown"
}

@MainActor @Observable
final class PaywallManager {
    static let shared = PaywallManager()

    private static let isProKey = "isPro"
    private static let logger = Logger(subsystem: "TraceAI", category: "Paywall")

    /// Placeholder product IDs; replace with the real App Store Connect IDs.
    let proProductIDs: Set<String> = [
        "com.traceai.pro.weekly",
        "com.traceai.pro.yearly",
        "com.traceai.pro.lifetime",
    ]

    private(set) var isPro: Bool

    private init() {
        isPro = UserDefaults.standard.bool(forKey: Self.isProKey)
    }

    private func setPro(_ value: Bool) {
        guard isPro != value else { return }
        isPro = value
        UserDefaults.standard.set(value, forKey: Self.isProKey)
    }

    func triggerPaywall(placement: String) {
        // TODO(Superwall): Superwall.shared.register(placement:)
        #if DEBUG
        Self.logger.debug("Paywall '\(placement, privacy: .public)' (DEBUG): unlocking Pro")
        setPro(true)
        #else
        Self.logger.info("Paywall '\(placement, privacy: .public)' requested; Superwall not wired yet")
        #endif
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  proProductIDs.contains(transaction.productID) else { continue }
            setPro(true)
            return
        }
    }
}
