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

    /// DEBUG-only unlock; kept in memory, never persisted.
    private var debugUnlocked = false

    private init() {
        isPro = UserDefaults.standard.bool(forKey: Self.isProKey)
    }

    /// Persists the real StoreKit entitlement; `isPro` also honors the DEBUG unlock.
    private func setEntitlement(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.isProKey)
        let newValue = value || debugUnlocked
        if isPro != newValue { isPro = newValue }
    }

    func triggerPaywall(placement: String) {
        // TODO(Superwall): Superwall.shared.register(placement:)
        #if DEBUG
        Self.logger.debug("Paywall '\(placement, privacy: .public)' (DEBUG): unlocking Pro")
        debugUnlocked = true
        isPro = true
        #else
        Self.logger.info("Paywall '\(placement, privacy: .public)' requested; Superwall not wired yet")
        #endif
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Recomputes Pro from StoreKit, so refunds and lapsed subscriptions turn it off.
    func refreshEntitlements() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  proProductIDs.contains(transaction.productID) else { continue }
            found = true
            break
        }
        setEntitlement(found)
    }
}
