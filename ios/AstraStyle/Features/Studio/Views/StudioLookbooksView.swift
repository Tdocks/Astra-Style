import SwiftUI

struct StudioLookbooksView: View {
    @State var viewModel: StudioLookbooksViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var showsCreate = false
    @State private var pendingName = ""
    @State private var renaming: StudioLookbook?
    @State private var deleting: StudioLookbook?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text(viewModel.generationID == nil
                     ? "Keep your favorite estimates together. Saved looks stay private and are retained while saved."
                     : "Choose collections for this look. Saving keeps the estimate; removing it from its last collection starts a fresh expiration window.")
                    .astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                if viewModel.isLoading { ProgressView("Loading collections…") }
                if let error = viewModel.error {
                    Text(error).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                    Button("Try again") { Task { await viewModel.load() } }.buttonStyle(.astraSecondary)
                }
                if !viewModel.isLoading && viewModel.lookbooks.isEmpty && viewModel.error == nil {
                    Text("Create your first collection").astraText(.title2)
                    Text("Try Everyday, Work, or Date night.").astraText(.body).foregroundStyle(AstraColor.textSecondary)
                    Button("New collection") { pendingName = ""; showsCreate = true }.buttonStyle(.astraPrimary)
                }
                ForEach(viewModel.lookbooks) { collection in
                    AstraCard {
                        HStack(alignment: .top, spacing: AstraSpacing.sm) {
                            Button {
                                if viewModel.generationID != nil {
                                    Task { await viewModel.toggleSave(to: collection) }
                                } else {
                                    router.push(StudioRoute.savedLooks(lookbookID: collection.id, name: collection.name))
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                                    Text(collection.name).astraText(.headline).foregroundStyle(AstraColor.textPrimary)
                                    if viewModel.generationID != nil {
                                        Label(viewModel.savedIDs.contains(collection.id) ? "Saved" : "Save here",
                                              systemImage: viewModel.savedIDs.contains(collection.id) ? "checkmark.circle.fill" : "plus.circle")
                                            .astraText(.caption).foregroundStyle(AstraColor.accentChampagneAccessible)
                                    } else {
                                        Text("Open collection").astraText(.caption).foregroundStyle(AstraColor.accentChampagneAccessible)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.generationID != nil && !viewModel.canSave)
                            .accessibilityValue(viewModel.savedIDs.contains(collection.id) ? "Saved" : "Not saved")
                            .accessibilityIdentifier("studio.collection.\(collection.id.uuidString)")
                            if viewModel.generationID == nil {
                                Menu {
                                    Button("Rename") { pendingName = collection.name; renaming = collection }
                                    Button("Remove collection", role: .destructive) { deleting = collection }
                                } label: {
                                    Image(systemName: "ellipsis").astraIcon(.disclosure)
                                        .frame(minWidth: AstraSize.minTapTarget, minHeight: AstraSize.minTapTarget)
                                }
                                .accessibilityLabel("Manage \(collection.name)")
                                .disabled(viewModel.isMutating || viewModel.isLoading)
                            }
                        }
                    }
                }
                if viewModel.hasMore {
                    Button(viewModel.isLoadingMore ? "Loading…" : "More collections") {
                        Task { await viewModel.load(reset: false) }
                    }.buttonStyle(.astraSecondary)
                        .disabled(viewModel.isLoadingMore || viewModel.isMutating || viewModel.isLoading)
                }
            }.padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(viewModel.generationID == nil ? "Saved looks" : "Save look")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New collection", systemImage: "plus") { pendingName = ""; showsCreate = true }
                    .disabled(viewModel.isMutating || viewModel.isLoading)
                    .accessibilityIdentifier("studio.collection.new")
            }
            if viewModel.generationID != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .alert("New collection", isPresented: $showsCreate) {
            TextField("Collection name", text: $pendingName)
            Button("Create") { Task { _ = await viewModel.create(name: pendingName) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Use 1–80 characters. Collections are private.") }
        .alert("Rename collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Collection name", text: $pendingName)
            Button("Save") {
                guard let collection = renaming else { return }
                Task { await viewModel.rename(collection, name: pendingName) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Remove collection?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Remove collection", role: .destructive) {
                guard let collection = deleting else { return }
                Task { await viewModel.delete(collection) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its estimates will remain in Studio. Looks saved elsewhere will stay in those collections.") }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .accessibilityIdentifier("studio.collections")
    }
}
