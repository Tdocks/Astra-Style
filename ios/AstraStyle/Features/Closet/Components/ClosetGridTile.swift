//
//  ClosetGridTile.swift
//  AstraStyle
//
//  One garment in the closet's editorial grid (spec §6.14 "Views:
//  Editorial grid"). Photograph, name, and the one line of context that
//  identifies a piece across a wardrobe of near-identical navy knitwear:
//  brand, or failing that the subcategory.
//
//  The image goes through `AstraRemoteImage` with
//  `ThumbnailSize.closetGridTile`, which decodes at 220 px rather than at
//  the camera's full resolution — spec §20 requires this grid to scroll at
//  60 fps and says in as many words never to render full-resolution
//  originals in a grid.
//
//  The tile does not fetch anything. It reports that it is on screen
//  (`onAppear`), and the view model turns a whole screenful of those
//  reports into one signing request — see `ClosetViewModel`'s header.
//

import SwiftUI

/// Geometry shared by every closet grid, so the tiles, the skeleton that
/// stands in for them, and the two screens that lay them out cannot drift
/// apart.
enum ClosetGridMetrics {
    /// Width over height. 4:5 is the editorial portrait crop used across
    /// the app's garment imagery, not a square — a square makes a jacket
    /// and a watch look like the same kind of object.
    static let tileAspectRatio: CGFloat = 4.0 / 5.0

    /// Two columns at ordinary text sizes; one at accessibility sizes.
    ///
    /// A fixed minimum tile width would be a hardcoded layout constant,
    /// and worse, at AX5 it would keep two columns of tiles whose captions
    /// have nowhere left to wrap. Dropping to a single column is what
    /// keeps a garment's name readable at the sizes where readability is
    /// the entire point (spec §19).
    static func columnCount(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    static func columns(for dynamicTypeSize: DynamicTypeSize) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: AstraSpacing.md),
            count: columnCount(for: dynamicTypeSize)
        )
    }
}

struct ClosetGridTile: View {
    let item: ClosetItem
    let imageURL: URL?
    /// Called each time the tile comes on screen. The view model turns a
    /// whole screenful of these into one signing request.
    let onVisible: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                AstraRemoteImage(
                    url: imageURL,
                    aspectRatio: ClosetGridMetrics.tileAspectRatio,
                    thumbnail: .closetGridTile,
                    accessibilityDescription: imageDescription
                )

                Text(item.name)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The whole tile is the target, so it is comfortably past
            // 44 pt already; the floor is here for the degenerate case of
            // a one-line name with no photograph.
            .frame(minHeight: AstraSize.minTapTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One element per garment. Without this VoiceOver reads the photo,
        // the name and the brand as three separate stops, and a closet of
        // forty pieces becomes a hundred and twenty swipes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(String(localized: "Opens this piece", comment: "VoiceOver hint on a closet grid tile")))
        .accessibilityAddTraits(.isButton)
        // Stable id for UI tests (P3-TEST-02) that assert a newly saved
        // garment appears in the grid — VoiceOver still uses the composed
        // label above; this identifier is for automation only.
        .accessibilityIdentifier("closet.grid.item.\(item.id.uuidString.lowercased())")
        .onAppear(perform: onVisible)
    }

    /// Brand if it is on file, otherwise the subcategory — whichever
    /// actually tells the pieces apart. Neither is invented when absent:
    /// the line simply is not drawn.
    private var subtitle: String? {
        if let brand = item.brand, !brand.isEmpty { return brand }
        if let subcategory = item.subcategory, !subcategory.isEmpty { return subcategory }
        return nil
    }

    /// What the photograph shows, as a sentence, for VoiceOver users and
    /// for the image's own description while it is still loading.
    private var imageDescription: String {
        if let subtitle {
            return String(localized: "\(item.name), \(subtitle)", comment: "VoiceOver description of a closet garment photo: name, then brand or type")
        }
        return item.name
    }

    private var accessibilityLabel: String {
        var parts = [item.name]
        if let subtitle { parts.append(subtitle) }
        if let color = item.primaryColor, !color.isEmpty { parts.append(color) }
        if item.laundryState != .clean { parts.append(item.laundryState.displayName) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Grid tile") {
    ClosetGridTile(
        item: ClosetItem(
            id: UUID(),
            userID: UUID(),
            name: "Navy Merino Crewneck",
            brand: "Sunspel",
            category: .top,
            subcategory: "Sweater",
            primaryColor: "navy"
        ),
        imageURL: nil,
        onVisible: {},
        onTap: {}
    )
    .padding(AstraSpacing.pagePadding)
    .background(AstraColor.backgroundPrimary)
    .preferredColorScheme(.dark)
}
