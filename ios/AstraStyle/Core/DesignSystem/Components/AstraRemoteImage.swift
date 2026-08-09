//
//  AstraRemoteImage.swift
//  AstraStyle
//
//  The app's one remote-image view. Replaces the `AsyncImage` that was
//  inlined in Features/Home/Components/HeroOutfitCardView.swift, which was
//  the only one in the codebase — promoted here before the closet grid adds
//  a second, third and hundredth call site.
//
//  WHY NOT `AsyncImage`.
//  `AsyncImage` hands back a decoded, full-resolution `Image` and gives no
//  seam to decode at a smaller size. spec §20 requires the closet grid to
//  scroll at 60 fps and says "never render full-resolution originals in
//  grids", and `Core/Utilities/ImageDownsampling.swift` already exists to
//  satisfy exactly that — but it takes `Data`, which `AsyncImage` never
//  exposes. A 4032x3024 phone photo decodes to ~48 MB of backing store; a
//  screen of 30 of those is not a dropped frame, it is a memory warning.
//  So this type does its own fetch: ~40 lines, `URLSession.shared`, and a
//  `.task(id:)` that cancels on disappear and on URL change for free.
//
//  The cost of that choice, stated plainly: no `AsyncImagePhase` niceties,
//  no automatic scale-factor handling from the response, and this file now
//  owns retry semantics (there are none — see below).
//
//  CACHING. Two layers, and one deliberate gap.
//  * HTTP responses ride `URLCache.shared`, which `URLSession.shared` uses
//    by default. Nothing here configures it, so it is the system default.
//  * Decoded/downsampled `UIImage`s are cached in memory by
//    `AstraImageCache` below, keyed on the URL's PATH rather than its full
//    string. That is not an oversight: closet images are served as signed
//    URLs whose query string carries a token that changes every time
//    `ClosetImageURLResolving` re-signs, and keying on `absoluteString`
//    would throw the whole grid's decoded cache away once an hour.
//  * GAP: there is no on-disk cache of decoded thumbnails, so a cold launch
//    re-downloads (or re-reads from `URLCache`) and re-decodes every tile.
//    Acceptable while the closet is tens of items; revisit if §20's 60 fps
//    target starts failing on first scroll rather than on re-scroll.
//
//  NO RETRY. A failed load shows the fallback and stays there until the
//  view is rebuilt. Deliberate: a grid that retries per-tile turns one
//  flaky connection into N concurrent retry storms. The screens own the
//  "couldn't load your closet" affordance (spec §22 "no unhandled network
//  failure"); a single tile silently falling back to a hanger is not the
//  same event as the fetch failing.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// An asynchronously-loaded remote image with a fixed aspect ratio and a
/// non-alarming fallback.
///
/// Failure and "no URL at all" render identically, on purpose. A garment
/// with no photo yet and a garment whose photo failed to load are the same
/// thing from where the user is sitting — there is no picture — and a
/// broken-image glyph in a premium wardrobe app reads as the app being
/// broken. Neither state ever shows one.
public struct AstraRemoteImage: View {
    private let url: URL?
    private let aspectRatio: CGFloat
    private let thumbnail: ImageDownsampling.ThumbnailSize?
    private let cornerRadius: CGFloat
    private let showsBackground: Bool
    private let contentMode: ContentMode
    private let accessibilityDescription: String

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .loading

    /// - Parameters:
    ///   - url: The image to load. `nil` renders the fallback immediately
    ///     without touching the network.
    ///   - aspectRatio: Width over height. 4/5 for editorial cards, 1 for
    ///     grid tiles.
    ///   - thumbnail: The downsampling target. Pass the `ThumbnailSize` that
    ///     matches the surface (`.closetGridTile` at 220 px,
    ///     `.listRowThumbnail` at 56 px) so the image decodes at the size it
    ///     is drawn at. `nil` decodes at full resolution — correct only for
    ///     a large hero image, where downsampling to a tile size would be
    ///     visibly soft.
    ///   - cornerRadius: Defaults to `AstraSpacing.cardRadius`.
    ///   - showsBackground: Whether to draw the `surfaceElevated` plate
    ///     behind the image. `false` for background-removed cut-outs laid
    ///     directly on the page — a plate behind a cut-out reinstates the
    ///     rectangle the cut-out was made to remove.
    ///   - contentMode: `.fill` crops to the frame, which is right for a
    ///     square grid tile. `.fit` shows the whole garment, which is the
    ///     only correct choice for a cut-out: cropping a silhouette cuts the
    ///     shoulders off the shirt.
    ///   - accessibilityDescription: What the image shows, as a sentence.
    ///     Applied whatever the load state, so VoiceOver describes the
    ///     garment rather than announcing a placeholder.
    public init(
        url: URL?,
        aspectRatio: CGFloat,
        thumbnail: ImageDownsampling.ThumbnailSize? = nil,
        cornerRadius: CGFloat = AstraSpacing.cardRadius,
        showsBackground: Bool = true,
        contentMode: ContentMode = .fill,
        accessibilityDescription: String
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.thumbnail = thumbnail
        self.cornerRadius = cornerRadius
        self.showsBackground = showsBackground
        self.contentMode = contentMode
        self.accessibilityDescription = accessibilityDescription
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(showsBackground ? AstraColor.surfaceElevated : Color.clear)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                content
                    .animation(
                        AstraMotion.aware(AstraMotion.standard, reduceMotion: reduceMotion),
                        value: phase.isLoaded
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // One element, not three: without this the fallback glyph is a
            // separate accessible child and VoiceOver announces "hanger".
            .accessibilityElement()
            .accessibilityLabel(Text(accessibilityDescription))
            .accessibilityAddTraits(.isImage)
            // `.task(id:)` is the whole cancellation story — SwiftUI tears
            // the task down when the view disappears and restarts it when
            // the URL changes, which is what keeps a fast scroll from
            // leaving dozens of in-flight downloads behind it.
            .task(id: url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            // Just the `surfaceElevated` fill. Deliberately NOT the hanger:
            // showing the fallback while loading means every tile flashes
            // "no photo" before its photo arrives.
            Color.clear
        case .loaded(let image):
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .transition(.opacity)
        case .unavailable:
            Image(systemName: "hanger")
                .astraIcon(.feature)
                .foregroundStyle(AstraColor.textMuted)
        }
    }

    // MARK: - Loading

    private enum Phase {
        case loading
        case loaded(UIImage)
        case unavailable

        var isLoaded: Bool {
            if case .loaded = self { return true }
            return false
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            phase = .unavailable
            return
        }
        let maxPixelSize = thumbnail?.maxPixelSize
        if let cached = AstraImageCache.shared.image(for: url, maxPixelSize: maxPixelSize) {
            phase = .loaded(cached)
            return
        }
        phase = .loading

        let fetched = await Self.fetch(url: url, maxPixelSize: maxPixelSize, scale: displayScale)

        // A cancelled load is not a failed one. Without this guard, a tile
        // scrolled off-screen mid-fetch would come back showing the "no
        // photo" fallback for an image that exists.
        guard !Task.isCancelled else { return }

        guard let fetched else {
            phase = .unavailable
            return
        }
        AstraImageCache.shared.insert(fetched, for: url, maxPixelSize: maxPixelSize)
        phase = .loaded(fetched)
    }

    /// Downloads and decodes. `nonisolated` and `static` so neither the
    /// transfer nor — more importantly — the decode runs on the main actor:
    /// `ImageDownsampling.downsample` is the expensive part of a grid tile
    /// and doing it on the main thread is precisely the dropped frame this
    /// component exists to avoid.
    private nonisolated static func fetch(url: URL, maxPixelSize: CGFloat?, scale: CGFloat) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            // A signed URL that has expired comes back as a well-formed 400
            // with a JSON body, which `UIImage(data:)` would turn into nil
            // several lines later and with no explanation. Check the status.
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let maxPixelSize else { return UIImage(data: data) }
            return ImageDownsampling.downsample(data: data, to: maxPixelSize, scale: scale)
        } catch {
            // Includes `URLError.cancelled`; the caller distinguishes that
            // case with `Task.isCancelled` rather than by inspecting errors.
            return nil
        }
    }
}

// MARK: - Decoded image cache

/// In-memory cache of decoded images, shared process-wide.
///
/// `@unchecked Sendable` is load-bearing and not a shortcut: `NSCache` is
/// documented as thread-safe (callers may add, remove and query entries
/// from any thread without locking), and the only stored property here is
/// the cache itself, assigned once at init and never reassigned. There is
/// no mutable state for the compiler to be protecting.
private final class AstraImageCache: @unchecked Sendable {
    static let shared = AstraImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // ~40 MB of decoded pixels. A `.closetGridTile` at 220 pt on a 3x
        // screen is roughly 660x660x4 ≈ 1.7 MB, so this holds on the order
        // of 20 screens' worth of tiles — enough that scrolling back up a
        // long closet is instant, small enough to be a rounding error
        // against the app's footprint. `NSCache` evicts under memory
        // pressure on its own, so this is a ceiling, not a reservation.
        cache.totalCostLimit = 40 * 1_024 * 1_024
    }

    func image(for url: URL, maxPixelSize: CGFloat?) -> UIImage? {
        cache.object(forKey: Self.key(for: url, maxPixelSize: maxPixelSize))
    }

    func insert(_ image: UIImage, for url: URL, maxPixelSize: CGFloat?) {
        let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
        cache.setObject(image, forKey: Self.key(for: url, maxPixelSize: maxPixelSize), cost: pixels * 4)
    }

    /// Keyed on path plus decode size, NOT on `absoluteString`.
    ///
    /// Supabase signed URLs carry their token in the query string and are
    /// re-signed on a timer, so the same photograph has a different
    /// `absoluteString` every hour and an `absoluteString` key would evict
    /// the entire closet's decoded tiles on each refresh. The path
    /// identifies the object; the token only authorises fetching it. The
    /// pixel size is part of the key because the same photo is legitimately
    /// cached at grid size and at row-thumbnail size at once.
    private static func key(for url: URL, maxPixelSize: CGFloat?) -> NSString {
        let host = url.host() ?? ""
        let size = maxPixelSize.map { String(describing: Int($0)) } ?? "full"
        return "\(host)\(url.path())|\(size)" as NSString
    }
}
