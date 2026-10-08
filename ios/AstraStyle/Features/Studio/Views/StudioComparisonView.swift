import SwiftUI

struct StudioComparisonView: View {
    @State var viewModel: StudioComparisonViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsSourceImages = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                Text("Visual estimates · These previews do not guarantee garment fit or exact colors.")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                switch viewModel.state {
                case .loading:
                    ProgressView("Loading your previews…").tint(AstraColor.accentChampagne)
                case .failed(let message):
                    Text(message).astraText(.body)
                    Button("Try again") { Task { await viewModel.load() } }.buttonStyle(.astraSecondary)
                case .loaded(let generations):
                    if let error = viewModel.imageError {
                        Text(error).astraText(.callout).foregroundStyle(AstraColor.textSecondary)
                        Button("Reload images") { Task { await viewModel.load() } }.buttonStyle(.astraSecondary)
                    }
                    if generations.contains(where: { !$0.referenceImagePath.isEmpty }) {
                        Toggle("Show original images", isOn: $showsSourceImages)
                            .tint(AstraColor.accentChampagne)
                    }
                    if dynamicTypeSize.isAccessibilitySize || generations.count == 1 {
                        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                            previews(generations)
                        }
                    } else {
                        HStack(alignment: .top, spacing: AstraSpacing.md) {
                            previews(generations)
                        }
                    }
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Compare looks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .accessibilityIdentifier("studio.compare")
    }

    private func previews(_ generations: [StudioGeneration]) -> some View {
        ForEach(Array(generations.enumerated()), id: \.element.id) { index, generation in
            VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                Text("Look \(index + 1)").astraText(.headline)
                Text(generation.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .astraText(.caption).foregroundStyle(AstraColor.textSecondary)
                if showsSourceImages && !generation.referenceImagePath.isEmpty {
                    Text(sourceLabel(generation)).astraText(.caption)
                    image(path: generation.referenceImagePath, label: sourceLabel(generation),
                          isGenerated: isGeneratedSource(generation))
                }
                Text("Generated visual estimate").astraText(.caption)
                if let path = generation.resultImagePath {
                    image(path: path, label: "Look \(index + 1), generated visual estimate", isGenerated: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func image(path: String, label: String, isGenerated: Bool) -> some View {
        if isGenerated {
            GeneratedImageContainer(accessibilityDescription: label) {
                remoteImage(path: path, label: label)
            }
        } else {
            remoteImage(path: path, label: label)
        }
    }

    private func remoteImage(path: String, label: String) -> some View {
        AstraRemoteImage(
            url: viewModel.imageURLs[path],
            aspectRatio: 2.0 / 3.0,
            contentMode: .fit,
            accessibilityDescription: label
        )
        .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card))
    }

    private func sourceLabel(_ generation: StudioGeneration) -> String {
        isGeneratedSource(generation) ? "Previous visual estimate" : "Original reference photo"
    }

    private func isGeneratedSource(_ generation: StudioGeneration) -> Bool {
        if case .object(let payload)? = generation.promptPayload,
           case .string(let mode)? = payload["mode"],
           mode == "inspiration" || mode == "closet_inspiration" {
            return true
        }
        return false
    }
}
