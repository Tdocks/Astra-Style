import SwiftUI

/// A real preset picker built from the same editable defaults used by
/// StudioGenerationViewModel. The visual is a control diagram, not a sample
/// result or a representation of a generated image.
struct StudioPresetGalleryView: View {
    let selectedPreset: StudioPromptPreset?
    let onSelect: (StudioPromptPreset?) -> Void

    private let columns = [GridItem(.flexible(), spacing: AstraSpacing.md), GridItem(.flexible(), spacing: AstraSpacing.md)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    Text("Choose a starting point for the scene and styling controls. Your garments and reference photo stay yours; every control can be edited after selection.")
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label {
                        Text("Schematic control preview · not a generated image")
                            .astraText(.caption)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                            .astraIcon(.inline)
                    }
                    .foregroundStyle(AstraColor.textMuted)
                    .accessibilityIdentifier("studio.presets.previewDisclosure")

                    LazyVGrid(columns: columns, alignment: .center, spacing: AstraSpacing.md) {
                        ForEach(StudioPromptPreset.allCases, id: \.rawValue) { preset in
                            presetCard(preset)
                        }
                    }
                }
                .padding(AstraSpacing.pagePadding)
            }
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationTitle("Studio presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSelect(nil) }
                        .accessibilityIdentifier("studio.presets.done")
                }
            }
        }
        .presentationBackground(AstraColor.backgroundPrimary)
        .accessibilityIdentifier("studio.presets.gallery")
    }

    private func presetCard(_ preset: StudioPromptPreset) -> some View {
        let defaults = preset.controlDefaults
        let isSelected = selectedPreset == preset

        return Button {
            onSelect(preset)
        } label: {
            AstraCard(padding: AstraSpacing.md) {
                VStack(alignment: .leading, spacing: AstraSpacing.sm) {
                    HStack(alignment: .top, spacing: AstraSpacing.xs) {
                        Text(preset.galleryTitle)
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .astraIcon(.inline)
                                .foregroundStyle(AstraColor.accentChampagneAccessible)
                                .accessibilityLabel("Selected")
                        }
                    }

                    schematicPreview(for: preset, defaults: defaults)

                    Text(defaults.summary)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Use preset")
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.galleryTitle). \(isSelected ? "Selected. " : "")\(defaults.summary)")
        .accessibilityHint("Applies these starting values. You can edit every control afterward.")
        .accessibilityIdentifier("studio.presets.\(preset.rawValue)")
    }

    private func schematicPreview(
        for preset: StudioPromptPreset,
        defaults: StudioPresetDefaults
    ) -> some View {
        VStack(spacing: AstraSpacing.sm) {
            HStack(spacing: AstraSpacing.xs) {
                Image(systemName: preset.previewSymbol)
                    .astraIcon(.feature)
                    .foregroundStyle(AstraColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text(defaults.background.galleryTitle)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text(defaults.pose.galleryTitle)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 68)
            .padding(.horizontal, AstraSpacing.sm)
            .background(AstraColor.backgroundSecondary, in: RoundedRectangle(cornerRadius: AstraRadius.small))

            HStack(spacing: AstraSpacing.xs) {
                ForEach(Array(defaults.palette.enumerated()), id: \.offset) { entry in
                    RoundedRectangle(cornerRadius: AstraRadius.small)
                        .fill(colorChip(for: entry.element))
            .frame(height: AstraSpacing.sm)
                        .overlay {
                            RoundedRectangle(cornerRadius: AstraRadius.small)
                                .strokeBorder(AstraColor.divider, lineWidth: 1)
                        }
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Palette: \(defaults.palette.joined(separator: ", "))")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Control diagram: \(defaults.background.galleryTitle), \(defaults.pose.galleryTitle), \(defaults.palette.joined(separator: ", "))")
    }

    private func colorChip(for name: String) -> Color {
        AstraGarmentColor.swatch(for: name).color ?? AstraColor.accentChampagne
    }
}

private extension StudioPromptPreset {
    var galleryTitle: String {
        switch self {
        case .smartCasual: String(localized: "Smart casual")
        case .dateNight: String(localized: "Date night")
        case .wedding: String(localized: "Wedding")
        case .vacation: String(localized: "Vacation")
        case .executive: String(localized: "Executive")
        case .oldMoneyInspired: String(localized: "Old-money inspired")
        case .minimalist: String(localized: "Minimalist")
        case .nightOut: String(localized: "Night out")
        }
    }

    var previewSymbol: String {
        switch self {
        case .smartCasual: "person.crop.square"
        case .dateNight: "moon.stars"
        case .wedding: "building.columns"
        case .vacation: "sun.max"
        case .executive: "building.2"
        case .oldMoneyInspired: "leaf"
        case .minimalist: "circle.square"
        case .nightOut: "moon.stars"
        }
    }
}

private extension StudioPresetDefaults {
    var summary: String {
        let seasonTitle = season?.galleryTitle ?? String(localized: "Current season")
        return "\(formality.galleryTitle) · \(background.galleryTitle) · \(seasonTitle) · \(palette.joined(separator: ", "))"
    }
}

private extension StudioBackground {
    var galleryTitle: String {
        switch self {
        case .studio: String(localized: "Studio")
        case .editorialOutdoor: String(localized: "Outdoors")
        case .urban: String(localized: "Urban")
        case .neutral: String(localized: "Neutral")
        }
    }
}

private extension StudioPose {
    var galleryTitle: String {
        switch self {
        case .standingFront: String(localized: "Standing front")
        case .standingThreeQuarter: String(localized: "Three-quarter")
        case .walking: String(localized: "Walking")
        case .seated: String(localized: "Seated")
        }
    }
}

private extension FormalityLevel {
    var galleryTitle: String {
        switch self {
        case .veryCasual: String(localized: "Very casual")
        case .casual: String(localized: "Casual")
        case .balanced: String(localized: "Balanced")
        case .formal: String(localized: "Formal")
        case .veryFormal: String(localized: "Very formal")
        }
    }
}

private extension Season {
    var galleryTitle: String {
        switch self {
        case .spring: String(localized: "Spring")
        case .summer: String(localized: "Summer")
        case .fall: String(localized: "Fall")
        case .winter: String(localized: "Winter")
        case .allSeason: String(localized: "All seasons")
        }
    }
}
