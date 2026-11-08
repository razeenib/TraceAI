import SwiftUI

// STUB (Phase 0). Phase 6 adds gestures, hand mask, auto-snap and TracingDock.
struct TracingView: View {
    let stencil: StencilSet

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()

    var body: some View {
        ZStack {
            CameraPreview(controller: camera)
                .ignoresSafeArea()

            Image(uiImage: stencil.full)
                .resizable()
                .scaledToFit()

            VStack {
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}
