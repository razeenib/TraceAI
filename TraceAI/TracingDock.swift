import SwiftUI

struct TracingDock: View {
    @Bindable var camera: CameraController
    @Binding var opacity: Double
    @Binding var step: Int

    private static let stageNames = ["Shapes", "Outlines", "Details", "Shading"]

    private var isPro: Bool { PaywallManager.shared.isPro }

    var body: some View {
        VStack(spacing: 14) {
            opacityRow
            stepPicker
            HStack(spacing: 8) {
                pill("Auto-Snap Paper", systemImage: "viewfinder", isOn: $camera.isPaperTrackEnabled)
                pill("Hand Mask", systemImage: "hand.raised.fill", isOn: $camera.isHandOcclusionEnabled)
                Spacer(minLength: 0)
                torchButton
            }
            lockButton
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var opacityRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: $opacity, in: 0.1...1.0)
                .accessibilityLabel("Stencil Opacity")
            Text("\(Int((opacity * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var stepPicker: some View {
        VStack(spacing: 6) {
            Picker("Step", selection: $step) {
                ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!isPro)
            .overlay {
                if !isPro {
                    Button {
                        PaywallManager.shared.triggerPaywall(placement: PaywallPlacement.unlockLayers)
                    } label: {
                        Label("Unlock 4-Step AI Breakdown", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text(isPro ? "Step \(step): \(Self.stageNames[min(max(step, 1), 4) - 1])" : "Full stencil")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func pill(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .toggleStyle(.button)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    private var torchButton: some View {
        Button {
            camera.setTorch(!camera.isTorchOn)
        } label: {
            Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(camera.isTorchOn ? Color.yellow : nil)
        .accessibilityLabel(camera.isTorchOn ? "Turn Flashlight Off" : "Turn Flashlight On")
    }

    private var lockButton: some View {
        Button {
            camera.setFocusExposureLocked(!camera.isLocked)
        } label: {
            Label(
                camera.isLocked ? "Unlock Canvas & Focus" : "Lock Canvas & Focus",
                systemImage: camera.isLocked ? "lock.fill" : "lock.open.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(camera.isLocked ? Color.orange : Color.accentColor)
        .disabled(camera.status != .running)
        .sensoryFeedback(.impact(weight: .heavy), trigger: camera.isLocked)
    }
}
