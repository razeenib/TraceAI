import PhotosUI
import SwiftUI

// TODO: Replace these placeholder URLs before App Store submission.
private enum LegalURL {
    static let privacyPolicy = URL(string: "https://example.com/privacy")!
    static let termsOfUse = URL(string: "https://example.com/terms")!
}

struct HomeView: View {
    @State private var session: TraceSession?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var paywall: PaywallManager { .shared }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                importCard
                if !paywall.isPro { unlockCard }
                samplesSection
                footer
            }
            .padding()
        }
        .navigationTitle("TraceAI")
        .toolbar { menu }
        .overlay { if isProcessing { processingOverlay } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await importPhoto(item) }
        }
        .alert("Couldn't Create Stencil", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await paywall.refreshEntitlements() }
        .fullScreenCover(item: $session) { session in
            TracingView(stencil: session.stencil)
        }
    }

    // MARK: Sections

    private var importCard: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            CardRow(
                systemImage: "photo.badge.plus",
                title: "Import Photo",
                subtitle: "Turn any photo into a stencil to trace."
            )
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var unlockCard: some View {
        Button {
            paywall.triggerPaywall(placement: PaywallPlacement.unlockLayers)
        } label: {
            CardRow(
                systemImage: "square.3.layers.3d",
                title: "Unlock 4-Step AI Breakdown",
                subtitle: "Trace in layers: shapes, outlines, details, shading."
            )
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Samples").font(.title3.weight(.semibold))
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(SampleSketch.allCases) { sample in
                    Button {
                        session = TraceSession(stencil: sample.makeStencilSet())
                    } label: {
                        SampleCard(sample: sample)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        Label("Photos and camera are processed on your device.", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Restore Purchases", systemImage: "arrow.clockwise") {
                    Task { await paywall.restorePurchases() }
                }
                Link(destination: LegalURL.privacyPolicy) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: LegalURL.termsOfUse) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(isProcessing)
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            ProgressView("Creating stencil…")
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: Import

    private func importPhoto(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { throw StencilError.invalidImage }
            let stencil = try await StencilProcessor.makeStencil(from: image)
            session = TraceSession(stencil: stencil)
        } catch StencilError.invalidImage {
            errorMessage = "That photo couldn't be read. Please try a different one."
        } catch {
            errorMessage = "Something went wrong while creating the stencil. Please try again."
        }
    }
}

// MARK: - Subviews

private struct CardRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .contentShape(Rectangle())
    }
}

private struct SampleCard: View {
    let sample: SampleSketch
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFit().padding(8)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
            Text(sample.title).font(.subheadline.weight(.medium))
        }
        .contentShape(Rectangle())
        .task { thumbnail = sample.makeStencilSet(size: CGSize(width: 256, height: 256)).full }
    }
}
