import SwiftUI

@main
struct TraceAIApp: App {
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
