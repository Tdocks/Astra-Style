//
//  DesignSystemGallery.swift
//  AstraStyle
//
//  A single preview surface rendering every design system token and component, so the whole
//  system can be eyeballed in one place across color scheme and Dynamic Type size. Preview-only;
//  not shown to end users.
//

import SwiftUI

/// Renders every `AstraColor`, `AstraTypography` style, and design system component in one
/// scrollable page. See the `#Preview` blocks at the bottom of this file for the color-scheme
/// and Dynamic Type size combinations exercised.
struct DesignSystemGallery: View {
    @State private var selectedChip = "Smart Casual"
    private let chipOptions = ["Smart Casual", "Executive", "Weekend", "Travel"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xxl) {
                colorSection
                typographySection
                spacingSection
                buttonSection
                cardSection
                chipSection
                // Split into its own view rather than two more `private var`
                // sections here: the input components are the only ones in the
                // gallery that need their own editable state, and four more
                // `@State` properties on `DesignSystemGallery` push it past
                // SwiftLint's `type_body_length`. Keeping their state next to
                // them is also just where it belongs.
                DesignSystemInputGallery()
                scoreMeterSection
                sectionHeaderSection
                generatedImageBadgeSection
            }
            .padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary)
    }

    // MARK: Colors

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(title: "Color", eyebrow: "Tokens")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: AstraSpacing.sm)], spacing: AstraSpacing.sm) {
                swatch("backgroundPrimary", AstraColor.backgroundPrimary)
                swatch("backgroundSecondary", AstraColor.backgroundSecondary)
                swatch("surfaceElevated", AstraColor.surfaceElevated)
                swatch("surfaceMarble*", AstraColor.surfaceMarble)
                swatch("textPrimary", AstraColor.textPrimary)
                swatch("textSecondary", AstraColor.textSecondary)
                swatch("textMuted", AstraColor.textMuted)
                swatch("accentChampagne", AstraColor.accentChampagne)
                swatch("accentChampagneAccessible", AstraColor.accentChampagneAccessible)
                swatch("accentChampagnePressed", AstraColor.accentChampagnePressed)
                swatch("divider", AstraColor.divider)
                swatch("successOlive", AstraColor.successOlive)
                swatch("warningAmber", AstraColor.warningAmber)
                swatch("destructive", AstraColor.destructive)
            }
            Text("* surfaceMarble currently degrades to backgroundPrimary until the marble asset ships.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                .fill(color)
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: AstraRadius.button, style: .continuous)
                        .strokeBorder(AstraColor.divider, lineWidth: 1)
                )
            Text(name)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: Typography

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Typography", eyebrow: "Tokens")
            ForEach(AstraTypography.allCases, id: \.self) { style in
                Text(sample(for: style))
                    .astraText(style)
                    .foregroundStyle(AstraColor.textPrimary)
            }
        }
    }

    private func sample(for style: AstraTypography) -> String {
        switch style {
        case .displayXL: "Good morning, Theo."
        case .displayL: "Your Style Journey"
        case .title1: "Kyra's Daily Brief"
        case .title2: "Alternative Looks"
        case .headline: "Wear This"
        case .body: "It fits the weather and moves cleanly from work to dinner."
        case .callout: "Compatibility 92 · Excellent"
        case .caption: "Last worn 6 days ago"
        case .micro: "Visual Estimate"
        }
    }

    // MARK: Spacing

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Spacing", eyebrow: "Tokens")
            spacingRow("xxs (4)", AstraSpacing.xxs)
            spacingRow("xs (8)", AstraSpacing.xs)
            spacingRow("sm (12)", AstraSpacing.sm)
            spacingRow("md (16)", AstraSpacing.md)
            spacingRow("lg / pagePadding (20)", AstraSpacing.lg)
            spacingRow("xl (24)", AstraSpacing.xl)
            spacingRow("xxl (32)", AstraSpacing.xxl)
            spacingRow("xxxl (40)", AstraSpacing.xxxl)
        }
    }

    private func spacingRow(_ label: String, _ value: CGFloat) -> some View {
        HStack(spacing: AstraSpacing.sm) {
            Rectangle()
                .fill(AstraColor.accentChampagne)
                .frame(width: value, height: 8)
            Text(label)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
        }
    }

    // MARK: Buttons

    private var buttonSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Buttons", eyebrow: "Components")
            Button("Wear This") {}
                .buttonStyle(.astraPrimary)
            Button("Alternatives") {}
                .buttonStyle(.astraSecondary)
            Button("Edit") {}
                .buttonStyle(.astraTertiary)
            Button("Wear This (disabled)") {}
                .buttonStyle(.astraPrimary)
                .disabled(true)
        }
    }

    // MARK: Card

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Card", eyebrow: "Components")
            AstraCard {
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    Text("Smart Casual")
                        .astraText(.headline)
                        .foregroundStyle(AstraColor.textPrimary)
                    Text("Olive knit polo, stone trousers, white sneakers.")
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                }
            }
        }
    }

    // MARK: Chips

    private var chipSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Chips", eyebrow: "Components")
            HStack(spacing: AstraSpacing.xs) {
                ForEach(chipOptions, id: \.self) { option in
                    AstraChip(option, isSelected: option == selectedChip) {
                        selectedChip = option
                    }
                }
            }
        }
    }

    // MARK: Score meter

    private var scoreMeterSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(title: "Score Meter", eyebrow: "Components")
            AstraScoreMeter(score: 92, title: "Compatibility", style: .compact)
            AstraScoreMeter(score: 61, title: "Wardrobe Score", style: .compact)
            AstraScoreMeter(score: 34, title: "Redundancy Risk", style: .compact)
            HStack(spacing: AstraSpacing.xl) {
                AstraScoreMeter(score: 87, title: "Wardrobe Score", style: .hero)
                AstraScoreMeter(score: 45, title: "Confidence", style: .hero)
            }
        }
    }

    // MARK: Section header

    private var sectionHeaderSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Section Header", eyebrow: "Components")
            AstraCard {
                AstraSectionHeader(
                    title: "Alternative Looks",
                    eyebrow: "KYRA'S PICKS",
                    actionTitle: "See all",
                    action: {}
                )
            }
        }
    }

    // MARK: Generated image badge

    private var generatedImageBadgeSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Generated Image Badge", eyebrow: "Components")
            GeneratedImageContainer(accessibilityDescription: "Styling estimate: olive knit polo, stone trousers, white sneakers.") {
                RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                    .fill(AstraColor.backgroundSecondary)
                    .frame(height: 220)
            }
        }
    }
}

/// The input components, with the editable state they need.
///
/// Their own view rather than two more sections on `DesignSystemGallery`:
/// these are the only components in the gallery that need editable state,
/// four more `@State` properties would push that type past SwiftLint's
/// `type_body_length`, and the state belongs next to the fields it drives.
private struct DesignSystemInputGallery: View {
    @State private var fieldText = "Navy Merino Sweater"
    @State private var fieldNotes = ""
    @State private var fieldError = ""
    @State private var pricePaid: Decimal? = 129

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxl) {
            textFieldSection
            remoteImageSection
        }
    }

    // MARK: Text fields

    private var textFieldSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(title: "Text Fields", eyebrow: "Components")
            AstraTextField(
                "Name",
                text: $fieldText,
                placeholder: "e.g. Navy Merino Sweater",
                isRequired: true
            )
            AstraTextField(
                "Notes",
                text: $fieldNotes,
                placeholder: "Anything worth remembering about this piece",
                footnote: "Only you see this.",
                axis: .vertical
            )
            // The error state is rendered with an empty binding on purpose:
            // "required and empty" is the combination the add/edit form will
            // actually show, and it is the one where the label, the marker
            // and the error all have to coexist without colliding at AX5.
            AstraTextField(
                "Brand",
                text: $fieldError,
                placeholder: "e.g. Sunspel",
                footnote: "Helps Kyra recognise the cut.",
                errorText: "Add a brand, or leave the field empty.",
                isRequired: true
            )
            AstraDecimalField(
                "Price paid",
                value: $pricePaid,
                placeholder: "0",
                footnote: "Used for cost per wear. Never for a verdict.",
                currencyCode: "GBP"
            )
        }
    }

    // MARK: Remote image

    private var remoteImageSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(title: "Remote Image", eyebrow: "Components")
            // Both tiles resolve to nothing — there is no bundled garment
            // photography in the repo. That makes this preview a check of
            // the state that matters most: the no-photo fallback must read
            // as "no photo", never as a broken image, and must look
            // identical whether the URL was absent or the load failed.
            HStack(spacing: AstraSpacing.sm) {
                AstraRemoteImage(
                    url: nil,
                    aspectRatio: 4.0 / 5.0,
                    accessibilityDescription: "Editorial preview, no photo yet"
                )
                AstraRemoteImage(
                    url: URL(string: "https://images.astrastyle.invalid/missing.jpg"),
                    aspectRatio: 4.0 / 5.0,
                    thumbnail: .closetGridTile,
                    accessibilityDescription: "Editorial preview, photo unavailable"
                )
            }
        }
    }
}

// MARK: - Previews

#Preview("Dark · Default") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}

#Preview("Light · Default") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark · Accessibility XL") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Light · Large") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
        .dynamicTypeSize(.xxxLarge)
}
