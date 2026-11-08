import Foundation
import Observation

enum PaywallPlacement {
    static let unlockLayers = "unlock_4_step_breakdown"
}

@MainActor @Observable
final class PaywallManager {
    static let shared = PaywallManager()

    private(set) var isPro: Bool = false

    private init() {}

    // STUB (Phase 0). Phase 1 adds StoreKit 2 entitlements and the Superwall hook.
    func triggerPaywall(placement: String) {}

    func restorePurchases() async {}

    func refreshEntitlements() async {}
}
