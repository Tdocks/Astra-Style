import SwiftUI

struct StudioSavedLooksView: View {
    @State var viewModel: StudioSavedLooksViewModel
    let name: String
    @Environment(AppRouter.self) private var router
    @State private var pendingRemoval: StudioGeneration?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text("Private visual estimates. Fit, colors and garment details may differ.")
                    .astraText(.caption).foregroundStyle(AstraColor.textSecondary)
                if viewModel.isLoading { ProgressView("Loading saved looks…") }
                if let error = viewModel.error {
                    Text(error).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                    Button("Try again") { Task { await viewModel.load() } }.buttonStyle(.astraSecondary)
                }
                if !viewModel.isLoading && viewModel.generations.isEmpty && viewModel.error == nil {
                    Text("No looks saved here yet").astraText(.title2)
                    Text("Open a completed estimate in Studio and choose Save to collection.")
                        .astraText(.body).foregroundStyle(AstraColor.textSecondary)
                }
                ForEach(viewModel.generations) { generation in
                    AstraCard {
                        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                            GeneratedImageContainer(accessibilityDescription: "Saved visual estimate in \(name)") {
                                AstraRemoteImage(url: viewModel.imageURLs[generation.id], aspectRatio: 2.0 / 3.0,
                                                 contentMode: .fit, accessibilityDescription: "Saved visual estimate")
                            }
                            Button("Open estimate") { router.push(StudioRoute.generation(generationID: generation.id)) }
                                .buttonStyle(.astraSecondary)
                                .accessibilityIdentifier("studio.savedLook.\(generation.id.uuidString)")
                            Button("Remove from collection") { pendingRemoval = generation }
                                .buttonStyle(.astraTertiary).disabled(viewModel.isRemoving || viewModel.isLoading)
                        }
                    }
                }
                if viewModel.hasMore {
                    Button(viewModel.isLoadingMore ? "Loading…" : "More saved looks") { Task { await viewModel.load(reset: false) } }
                        .buttonStyle(.astraSecondary)
                        .disabled(viewModel.isLoadingMore || viewModel.isLoading || viewModel.isRemoving)
                }
            }.padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        .alert("Remove this saved look?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove", role: .destructive) {
                guard let generation = pendingRemoval else { return }
                Task { await viewModel.remove(generation) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes it from this collection. The estimate will remain in Studio.") }
        .task { await viewModel.load() }.refreshable { await viewModel.load() }
        .accessibilityIdentifier("studio.savedLooks")
    }
}
