import Combine
import Foundation
import Observation
import OSLog
import SuperwallKit

enum PaywallPlacement {
    static let unlockLayers = "unlock_4_step_breakdown"
}

@MainActor @Observable
final class PaywallManager {
    static let shared = PaywallManager()

    /// Superwall public API key ("pk_…", dashboard → Settings → Keys). Public keys are meant to
    /// ship inside the app. While empty, Superwall stays off and DEBUG builds unlock Pro on tap.
    static let superwallAPIKey = ""
    static var isSuperwallEnabled: Bool { !superwallAPIKey.isEmpty }

    private static let isProKey = "isPro"
    private static let logger = Logger(subsystem: "TraceAI", category: "Paywall")

    private(set) var isPro: Bool

    /// DEBUG-only unlock used while no API key is set; kept in memory, never persisted.
    @ObservationIgnored private var debugUnlocked = false
    @ObservationIgnored private var statusObserver: AnyCancellable?

    private init() {
        isPro = UserDefaults.standard.bool(forKey: Self.isProKey)
    }

    /// Mirrors Superwall's subscription status into `isPro`. Call once, after `Superwall.configure`.
    func observeSubscriptionStatus() {
        guard Self.isSuperwallEnabled, statusObserver == nil else { return }
        statusObserver = Superwall.shared.$subscriptionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.apply(status) }
            }
    }

    /// `.unknown` means Superwall hasn't resolved entitlements yet, so the cached value stays.
    private func apply(_ status: SubscriptionStatus) {
        if case .unknown = status { return }
        setEntitlement(status.isActive)
    }

    /// Persists the real entitlement; `isPro` also honors the DEBUG unlock.
    private func setEntitlement(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.isProKey)
        let newValue = value || debugUnlocked
        if isPro != newValue { isPro = newValue }
    }

    func triggerPaywall(placement: String) {
        guard Self.isSuperwallEnabled else {
            #if DEBUG
            Self.logger.debug("Paywall '\(placement, privacy: .public)' (DEBUG, no API key): unlocking Pro")
            debugUnlocked = true
            isPro = true
            #else
            Self.logger.error("Paywall '\(placement, privacy: .public)' requested but no Superwall API key is set")
            #endif
            return
        }
        // Shows the campaign's paywall; a purchase flips `subscriptionStatus`, which updates `isPro`.
        Superwall.shared.register(placement: placement)
    }

    func restorePurchases() async {
        guard Self.isSuperwallEnabled else { return }
        let result = await Superwall.shared.restorePurchases()
        if case .failed(let error) = result {
            Self.logger.error("Restore failed: \(String(describing: error), privacy: .public)")
        }
        await refreshEntitlements()
    }

    /// Re-reads Superwall's status; Superwall itself tracks refunds and lapsed subscriptions.
    func refreshEntitlements() async {
        guard Self.isSuperwallEnabled else { return }
        apply(Superwall.shared.subscriptionStatus)
    }
}
