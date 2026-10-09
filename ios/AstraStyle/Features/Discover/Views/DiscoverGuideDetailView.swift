import SwiftUI

struct DiscoverGuideDetailView: View {
    @State private var viewModel: DiscoverGuideDetailViewModel

    init(viewModel: DiscoverGuideDetailViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .tint(AstraColor.accentChampagne)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let guide):
                article(guide)
            case .unavailable:
                unavailable
            case .failed:
                failure
            }
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .task { await viewModel.load() }
    }

    private func article(_ guide: DiscoverGuide) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                articleHeader(guide)
                ForEach(guide.sections) { section in
                    articleSection(section)
                }
                if let sources = guide.sources, !sources.isEmpty {
                    sourcesSection(sources, reviewedAt: guide.reviewedAt, guideID: guide.id)
                }
            }
            .padding(AstraSpacing.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func articleHeader(_ guide: DiscoverGuide) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(kindLabel(guide.kind))
                .astraText(.caption)
                .foregroundStyle(AstraColor.accentChampagneAccessible)
            Text(guide.title)
                .astraText(.title1)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("discover.guide.\(guide.id)")
            Text(guide.summary)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(readTime(guide.readingMinutes))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
            if let label = guide.visibleCommercialLabel {
                Text(label)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .accessibilityIdentifier("discover.guide.commercial-label")
            }
        }
    }

    private func articleSection(_ section: DiscoverGuideSection) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(section.heading)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
            Text(section.body)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourcesSection(
        _ sources: [DiscoverGuideSource],
        reviewedAt: String?,
        guideID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            Text(sourcesHeading(reviewedAt: reviewedAt))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityIdentifier("discover.guide.sources")
            ForEach(sources) { source in
                if let destination = source.destination {
                    Link(source.title, destination: destination)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                        .accessibilityIdentifier("discover.guide.source.\(guideID).\(source.id)")
                }
            }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(
            String(localized: "Guide unavailable", comment: "Discover editorial route unavailable"),
            systemImage: "book.closed",
            description: Text(String(
                localized: "This guide is not in the current editorial catalog.",
                comment: "Discover guide missing copy"
            ))
        )
        .accessibilityIdentifier("discover.guide.unavailable")
    }

    private var failure: some View {
        ContentUnavailableView {
            Label(String(localized: "Guides couldn't load", comment: "Discover editorial load error"), systemImage: "wifi.exclamationmark")
        } description: {
            Text(String(localized: "Try loading this guide again.", comment: "Discover editorial retry hint"))
        } actions: {
            Button(String(localized: "Retry", comment: "Retry loading Discover guide")) {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AstraColor.accentChampagne)
            .accessibilityIdentifier("discover.guide.retry")
        }
    }

    private func kindLabel(_ kind: DiscoverEditorialKind) -> String {
        switch kind {
        case .styleEducation:
            String(localized: "STYLE NOTES", comment: "Discover editorial guide category")
        case .seasonalGuide:
            String(localized: "SEASONAL GUIDE", comment: "Discover editorial guide category")
        case .fitGuide:
            String(localized: "FIT GUIDE", comment: "Discover editorial guide category")
        case .brandSpotlight:
            String(localized: "BRAND SPOTLIGHT", comment: "Discover editorial guide category")
        }
    }

    private func readTime(_ minutes: Int) -> String {
        String(localized: "\(minutes) min read", comment: "Discover guide estimated reading time")
    }

    private func sourcesHeading(reviewedAt: String?) -> String {
        guard let reviewedAt,
              let date = ISO8601DateFormatter().date(from: reviewedAt) else {
            return String(localized: "Sources", comment: "Discover editorial sources section")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return String(localized: "Sources · reviewed \(formatter.string(from: date))", comment: "Discover editorial source review date")
    }
}
