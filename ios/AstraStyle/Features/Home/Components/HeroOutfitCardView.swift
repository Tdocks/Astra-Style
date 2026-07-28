//
//  HeroOutfitCardView.swift
//  AstraStyle
//
//  Spec §6.11 hero card: large editorial outfit image, occasion, weather
//  suitability, confidence score, "Why this works", and the four primary
//  actions (Wear This, Alternatives, Edit, Visualize).
//

import SwiftUI

struct HeroOutfitCardView: View {
    let outfit: Outfit
    let weather: WeatherSnapshot?
    let units: UnitsPreference
    let isMarkingWorn: Bool
    let onWearThis: () -> Void
    let onAlternatives: () -> Void
    let onEdit: () -> Void
    let onVisualize: () -> Void

    var body: some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                heroImage

                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    HStack {
                        Text(outfit.name)
                            .astraText(.title2)
                            .foregroundStyle(AstraColor.textPrimary)
                        Spacer()
                        if let score = outfit.compatibilityScore {
                            ConfidenceBadge(score: score)
                        }
                    }

                    if !outfit.occasionTags.isEmpty {
                        Text(outfit.occasionTags.joined(separator: " · ").capitalized)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.textMuted)
                    }

                    if let weather, let min = outfit.weatherMin, let max = outfit.weatherMax {
                        Text("Suited for \(AstraWeatherFormatting.temperatureRange(low: min, high: max, units: units)) — today's \(AstraWeatherFormatting.singleTemperature(weather.temperatureHigh, units: units))")
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.successOlive)
                    }

                    if let description = outfit.description {
                        Text("Why this works")
                            .astraText(.micro)
                            .foregroundStyle(AstraColor.textMuted)
                            .padding(.top, AstraSpacing.xs)
                        Text(description)
                            .astraText(.body)
                            .foregroundStyle(AstraColor.textSecondary)
                    }
                }

                actionRow
            }
            .padding(AstraSpacing.pagePadding)
        }
        .accessibilityElement(children: .contain)
    }

    private var heroImage: some View {
        RoundedRectangle(cornerRadius: AstraSpacing.cardRadius, style: .continuous)
            .fill(AstraColor.surfaceElevated)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay {
                if let url = outfit.heroImageURL ?? outfit.generatedPreviewURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: "hanger")
                                .astraIcon(.feature)
                                .foregroundStyle(AstraColor.textMuted)
                        }
                    }
                } else {
                    Image(systemName: "hanger")
                        .astraIcon(.feature)
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AstraSpacing.cardRadius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                // Spec §11/§13 guardrail + CLAUDE.md "every generated image carries the
                // estimate badge": `heroImageURL` is a real/curated asset and never gets the
                // badge; `generatedPreviewURL` (Style Studio output) always does.
                if outfit.heroImageURL == nil, outfit.generatedPreviewURL != nil {
                    GeneratedImageBadge()
                        .padding(AstraSpacing.sm)
                }
            }
            .accessibilityLabel(Text("Editorial preview of \(outfit.name)"))
            .accessibilityAddTraits(.isImage)
    }

    private var actionRow: some View {
        HStack(spacing: AstraSpacing.sm) {
            AstraButton(title: String(localized: "Wear This", comment: "Home hero card primary action"), isLoading: isMarkingWorn, action: onWearThis)

            Button(action: onAlternatives) {
                Label(String(localized: "Alternatives"), systemImage: "square.stack")
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("Shows other outfit options for today"))

            Menu {
                Button(String(localized: "Edit Outfit"), systemImage: "slider.horizontal.3", action: onEdit)
                Button(String(localized: "Visualize"), systemImage: "camera.viewfinder", action: onVisualize)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("More outfit actions"))
        }
    }
}

private struct ConfidenceBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .astraText(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(AstraColor.textOnAccent)
            .padding(.horizontal, AstraSpacing.sm)
            .padding(.vertical, AstraSpacing.xxs)
            .background(AstraColor.accentChampagne, in: Capsule())
            .accessibilityLabel(Text("Confidence score: \(score) out of 100"))
    }
}
