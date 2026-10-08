import SwiftUI

struct InspirationView: View {
    @State var viewModel: InspirationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(AppRouter.self) private var router
    @State private var work: Task<Void, Never>?
    @State private var showsPaywall = false
    @State private var showsPieces = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    Text(viewModel.closetOnly ? "A look from your closet" : "See today's inspiration")
                        .astraText(.title2)
                    Text(viewModel.contextSummary)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                    Text("Visual estimate · Colors and fit may differ. Images are saved in Style Studio.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                    if let url = viewModel.imageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFit()
                            case .failure:
                                VStack(spacing: AstraSpacing.sm) {
                                    Text("The image couldn't load.").astraText(.body)
                                    Button("Reload image") { run { await viewModel.retry() } }
                                        .buttonStyle(.astraSecondary)
                                        .disabled(viewModel.isGenerating)
                                }
                            default: ProgressView()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card))
                        .accessibilityLabel("Generated outfit inspiration, a visual estimate")
                        .accessibilityIdentifier("home.inspiration.image")
                    }
                    if !viewModel.renderedItems.isEmpty {
                        Text("Image based on: " + viewModel.renderedItems.map(\.name).joined(separator: ", "))
                            .astraText(.caption)
                    }
                    if viewModel.isPreparing || viewModel.isGenerating {
                        ProgressView(viewModel.isPreparing ? "Gathering your style and plans…" : "Creating your look… This can take a minute.")
                            .tint(AstraColor.accentChampagne)
                    }
                    if let error = viewModel.error {
                        Text(error).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                        if let job = viewModel.job,
                           job.status != .failed || job.isRetryableWithoutCharge {
                            Button("Check again") { run { await viewModel.retry() } }
                                .buttonStyle(.astraSecondary)
                                .disabled(viewModel.isGenerating)
                        }
                    }
                    if viewModel.closetOnly { garmentSelection }
                    TextField("More casual, dressier, date night…", text: $viewModel.adjustment, axis: .vertical)
                        .astraText(.body)
                        .padding(AstraSpacing.md)
                        .background(AstraColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: AstraRadius.card))
                        .accessibilityIdentifier("home.inspiration.adjustment")
                    Button(viewModel.imageURL == nil ? "Generate my look" : (viewModel.adjustment.isEmpty ? "Try another look" : "Apply my changes")) {
                        run { await viewModel.generate() }
                    }
                    .buttonStyle(.astraPrimary)
                    .disabled(!viewModel.canGenerate)
                    .accessibilityIdentifier("home.inspiration.generate")
                    if viewModel.imageURL != nil {
                        ViewThatFits {
                            HStack { quickEdits }
                            VStack { quickEdits }
                        }
                    }
                    Text("Includes one free image estimate. Rerolls and edits use your image allowance; additional generations require Premium.")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                    Button("Talk through this with Kyra") {
                        let prompt = viewModel.chatPrompt
                        dismiss()
                        router.startAskKyra(initialPrompt: prompt, autoSend: true)
                    }
                    .buttonStyle(.astraSecondary)
                }
                .padding(AstraSpacing.pagePadding)
            }
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(viewModel.closetOnly ? "My closet look" : "Inspiration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { await viewModel.prepare() }
            .onDisappear { work?.cancel() }
            .onChange(of: viewModel.pendingPaywall) { _, context in showsPaywall = context != nil }
            .sheet(isPresented: $showsPaywall, onDismiss: { viewModel.clearPaywall() }) {
                PaywallView(viewModel: PaywallViewModel(
                    context: .studioQuota,
                    purchasing: LiveStoreKitPurchasing(appAccountTokenProvider: { await container.sessionStore.currentUserID() }),
                    subscriptionRepository: container.subscriptionRepository
                ))
            }
        }
    }

    private var quickEdits: some View {
        ForEach(["More casual", "Dressier", "Date night"], id: \.self) { adjustment in
            Button(adjustment) { run { await viewModel.generate(adjustment: adjustment) } }
                .buttonStyle(.astraSecondary)
                .disabled(!viewModel.canGenerate)
        }
    }

    private var garmentSelection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text("Pieces to use (choose up to 12)").astraText(.headline)
            Text("Swap a piece here before applying changes. Only the selected items will be rendered.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            if viewModel.items.isEmpty {
                Text("Add wearable pieces to your closet first.").astraText(.body)
            }
            Text(viewModel.items.filter { viewModel.selectedItemIDs.contains($0.id) }.map(\.name).joined(separator: ", "))
                .astraText(.callout)
            DisclosureGroup("Choose or swap pieces", isExpanded: $showsPieces) {
            ForEach(viewModel.items) { item in
                Toggle(item.name, isOn: Binding(
                    get: { viewModel.selectedItemIDs.contains(item.id) },
                    set: { selected in
                        if selected { viewModel.selectedItemIDs.insert(item.id) }
                        else { viewModel.selectedItemIDs.remove(item.id) }
                    }
                ))
                .tint(AstraColor.accentChampagne)
                .disabled(viewModel.isGenerating || (!viewModel.selectedItemIDs.contains(item.id) && viewModel.selectedItemIDs.count >= 12))
            }
            }
        }
    }

    private func run(_ operation: @escaping @MainActor () async -> Void) {
        work?.cancel()
        work = Task { await operation() }
    }
}
