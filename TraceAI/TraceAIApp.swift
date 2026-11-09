import SuperwallKit
import SwiftUI

@main
struct TraceAIApp: App {
    init() {
        // Paywalls stay off until the public API key is set in PaywallManager.superwallAPIKey.
        if PaywallManager.isSuperwallEnabled {
            Superwall.configure(apiKey: PaywallManager.superwallAPIKey)
            PaywallManager.shared.observeSubscriptionStatus()
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
        }
    }
}

/// One tracing screen presentation.
struct TraceSession: Identifiable {
    let id = UUID()
    let stencil: StencilSet
}
