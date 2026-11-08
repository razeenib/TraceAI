import SwiftUI

// STUB (Phase 0). Phase 5 adds PhotosPicker import, sample cards, unlock card and menu.
struct HomeView: View {
    @State private var session: TraceSession?

    var body: some View {
        List(SampleSketch.allCases) { sample in
            Button(sample.title) {
                session = TraceSession(stencil: sample.makeStencilSet())
            }
        }
        .navigationTitle("TraceAI")
        .fullScreenCover(item: $session) { session in
            TracingView(stencil: session.stencil)
        }
    }
}
