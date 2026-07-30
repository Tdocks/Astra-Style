//
//  StylePreferenceVector.swift
//  AstraStyle
//
//  The eight-dimension preference vector spec §6.9 asks the paired-image quiz
//  to infer, stored as `style_profiles.preference_vector` (jsonb).
//
//  THE HONEST VERSION OF THIS TYPE IS THE WHOLE POINT.
//
//  §6.9 asks for eight dimensions from 12–20 comparisons. Even at the top of
//  that range that is two and a half comparisons per axis, and a comparison is
//  one bit: it says which side of a line the user fell on, not how far. A type
//  that stored eight bare `Double`s would let every consumer — Style DNA
//  generation, compatibility scoring, Kyra's context packet — treat "measured
//  once, weakly" and "measured six times, consistently" as the same fact. They
//  are not the same fact, and the difference decides whether Kyra may state a
//  preference back to the user as something he told her, or must hold it as a
//  guess.
//
//  So every axis carries three things:
//
//    • `score`        — where on the axis, in -1…+1.
//    • `confidence`   — how much to trust that, derived from how many
//                       comparisons actually loaded on this axis.
//    • `observations` — the raw effective sample size, so a consumer that wants
//                       to apply its own threshold can, rather than being stuck
//                       with ours.
//
//  And ABSENCE IS MEANINGFUL. A dimension with no entry was never asked about —
//  the comparison set had no imagery probing it. A dimension present with
//  `observations == 0` was asked about and the user expressed no preference.
//  Those are different, and collapsing them into "0, neutral" would invent a
//  measurement that was never taken. That invention is the specific failure this
//  file is written to prevent: a Style DNA that looks complete and is partly
//  fabricated is worse than one that admits it only knows three things.
//

import Foundation

// MARK: - Dimensions

/// The eight axes spec §6.9 enumerates, in the order it enumerates them.
///
/// Raw values are the jsonb keys. There is no Postgres enum type behind this —
/// the vector is a jsonb document, so the value set is not enforced by the
/// database. Registered as such in `scripts/check_schema_drift.py` rather than
/// left unclassified, because an enum that checker cannot see is an enum that
/// can drift.
///
/// The sign convention is documented per case and is NOT arbitrary: once a score
/// is written to a user's row, flipping a convention silently inverts every
/// stored profile. If one ever has to change it needs a `version` bump on the
/// vector and a backfill, not an edit here.
public enum StyleDimension: String, Codable, CaseIterable, Sendable, Identifiable {
    /// −1 restrained, near-neutral palette · +1 saturated colour welcomed.
    case colourTolerance = "colour_tolerance"
    /// −1 relaxed · +1 tailored.
    case formality
    /// −1 close to the body · +1 loose and voluminous.
    case silhouette
    /// −1 flat, smooth cloth · +1 pronounced texture (knit, tweed, cord).
    case texture
    /// −1 no visible branding · +1 branding welcome.
    case logoTolerance = "logo_tolerance"
    /// −1 classic and long-lived · +1 current and trend-forward.
    case trendTolerance = "trend_tolerance"
    /// −1 minimal accessories · +1 accessories as a deliberate layer.
    case accessoryPreference = "accessory_preference"
    /// −1 tonal, low contrast · +1 high contrast between pieces.
    case contrastPreference = "contrast_preference"

    public var id: String { rawValue }

    /// What this axis is called when it appears in a sentence shown to a user.
    ///
    /// Deliberately plain nouns, lowercase, mid-sentence. "colour" not
    /// "chromatic tolerance": the one place these surface is a line telling a
    /// man what the comparisons picked up on, and a taxonomy word there reads as
    /// the app talking about itself rather than to him.
    public var displayName: String {
        switch self {
        case .colourTolerance: String(localized: "colour", comment: "Style dimension, mid-sentence")
        case .formality: String(localized: "formality", comment: "Style dimension, mid-sentence")
        case .silhouette: String(localized: "cut", comment: "Style dimension, mid-sentence")
        case .texture: String(localized: "texture", comment: "Style dimension, mid-sentence")
        case .logoTolerance: String(localized: "branding", comment: "Style dimension, mid-sentence")
        case .trendTolerance: String(localized: "how current you like things",
                                     comment: "Style dimension, mid-sentence")
        case .accessoryPreference: String(localized: "accessories", comment: "Style dimension, mid-sentence")
        case .contrastPreference: String(localized: "contrast", comment: "Style dimension, mid-sentence")
        }
    }
}

// MARK: - Confidence

/// How much weight a consumer should put on one axis of the vector.
///
/// Four bands rather than a raw number at the call site, because the decision
/// downstream is categorical: state it back to the user as a fact, use it as a
/// tiebreak, or ignore it. `StylePreferenceInference` documents exactly which
/// observation counts produce which band, and the raw count is kept on the
/// reading for anyone who disagrees with those thresholds.
public enum PreferenceConfidence: String, Codable, CaseIterable, Sendable, Comparable {
    /// Asked, but nothing usable came back — every comparison on this axis was
    /// answered "no preference", or none was asked at all.
    case insufficient
    /// One comparison's worth. A direction, not a magnitude. Do not tell the
    /// user this is what he likes; it is a starting guess.
    case low
    /// Two or three comparisons that broadly agree.
    case moderate
    /// Four or more, largely agreeing. This is the band §6.9 was written
    /// assuming, and at 12–20 total comparisons across 8 axes only two or three
    /// axes can realistically reach it.
    case high

    var rank: Int {
        switch self {
        case .insufficient: 0
        case .low: 1
        case .moderate: 2
        case .high: 3
        }
    }

    public static func < (lhs: PreferenceConfidence, rhs: PreferenceConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Whether this axis may be stated back to the user as something Kyra knows,
    /// rather than something she is guessing at.
    ///
    /// The bar is `.moderate`, and it lives here rather than at each call site
    /// so raising it later is one edit instead of a search.
    public var isStatable: Bool { self >= .moderate }
}

// MARK: - One axis

/// A single axis of the vector: where the user sits, and how sure we are.
public struct StyleDimensionReading: Codable, Hashable, Sendable {

    /// −1…+1, per `StyleDimension`'s documented convention. `nil` when the axis
    /// was probed but produced no usable signal (every comparison on it was
    /// answered "no preference"), which is a real outcome and not an error.
    public var score: Double?

    public var confidence: PreferenceConfidence

    /// Effective sample size: the sum of the absolute loadings of every
    /// comparison the user actually answered on this axis. Fractional because a
    /// pair may probe an axis as a secondary signal at partial weight.
    ///
    /// Persisted rather than recomputed on read, because the comparison set is
    /// content and content changes. A vector written against a 3-pair catalog
    /// has to stay interpretable after the catalog grows to sixteen.
    public var observations: Double

    /// How consistent the answers on this axis were, 0…1. 1 means every
    /// comparison pointed the same way; 0 means they cancelled out exactly.
    /// `nil` when there is nothing to be consistent about.
    public var agreement: Double?

    public init(
        score: Double?,
        confidence: PreferenceConfidence,
        observations: Double,
        agreement: Double? = nil
    ) {
        self.score = score
        self.confidence = confidence
        self.observations = observations
        self.agreement = agreement
    }

    enum CodingKeys: String, CodingKey {
        case score
        case confidence
        case observations
        case agreement
    }
}

// MARK: - The vector

public struct StylePreferenceVector: Codable, Hashable, Sendable {

    /// Bumped when the sign conventions or the confidence bands change in a way
    /// that makes an already-stored vector mean something different.
    ///
    /// Stored rather than assumed. A vector is written once at onboarding and
    /// read for the life of the account; without a version, the first change to
    /// this file silently reinterprets every row already in the table.
    public static let currentVersion = 1

    public var version: Int

    /// How many comparisons the user answered, including any he answered "no
    /// preference" to. Distinct from the sum of `observations` across axes,
    /// which is loading-weighted.
    public var comparisonsAnswered: Int

    /// How many comparisons the catalog was able to offer him.
    /// `comparisonsAnswered < comparisonsOffered` means he left the step early,
    /// which is allowed — §6.9's step is skippable.
    ///
    /// Kept alongside the answer count because the two together are the only way
    /// to read a stored vector correctly later. "Three answers" means something
    /// very different when three were offered than when sixteen were.
    public var comparisonsOffered: Int

    /// Only the axes the comparison set could actually probe. An axis with no
    /// entry was never asked about; see this file's header.
    public var dimensions: [StyleDimension: StyleDimensionReading]

    public init(
        version: Int = StylePreferenceVector.currentVersion,
        comparisonsAnswered: Int = 0,
        comparisonsOffered: Int = 0,
        dimensions: [StyleDimension: StyleDimensionReading] = [:]
    ) {
        self.version = version
        self.comparisonsAnswered = comparisonsAnswered
        self.comparisonsOffered = comparisonsOffered
        self.dimensions = dimensions
    }

    /// The vector of a user who skipped §6.9 entirely.
    ///
    /// A real, valid value rather than `nil`, so every consumer takes the same
    /// code path whether the quiz ran or not. "He skipped it" is expressed by an
    /// empty `dimensions` and a zero count — which is exactly what a consumer
    /// needs to know — and not by an optional half the call sites will forget to
    /// unwrap.
    public static let skipped = StylePreferenceVector()

    /// Axes with a usable score, in `StyleDimension.allCases` order.
    ///
    /// Ordered rather than dictionary-ordered because this drives user-facing
    /// copy, and a sentence whose clauses reorder between launches looks like a
    /// bug even when every word in it is correct.
    public var measuredDimensions: [StyleDimension] {
        StyleDimension.allCases.filter { dimensions[$0]?.score != nil }
    }

    /// Axes we would be willing to state back to the user as a known
    /// preference. See `PreferenceConfidence.isStatable`.
    public var statableDimensions: [StyleDimension] {
        StyleDimension.allCases.filter {
            guard let reading = dimensions[$0], reading.score != nil else { return false }
            return reading.confidence.isStatable
        }
    }

    public func score(for dimension: StyleDimension) -> Double? {
        dimensions[dimension]?.score
    }

    public func confidence(for dimension: StyleDimension) -> PreferenceConfidence {
        dimensions[dimension]?.confidence ?? .insufficient
    }

    /// `true` when nothing at all was learned — skipped, or every comparison
    /// answered "no preference".
    public var isEmpty: Bool { measuredDimensions.isEmpty }
}

// MARK: - Codable

// Hand-written, and in an extension so that `scripts/check_column_drift.py` —
// which scans `Domain/Models` for a struct body containing a `CodingKeys` block
// — reads `StyleDimensionReading`'s keys and not a set of keys that look like
// they should be columns on `style_profiles`. They are not: this whole type is
// ONE column.
//
// Hand-written because `[StyleDimension: StyleDimensionReading]` does not
// round-trip through Swift's synthesised Codable as a JSON object. A dictionary
// whose key type is not literally `String` or `Int` encodes as a FLAT
// ALTERNATING ARRAY — [key, value, key, value, …] — and `StyleDimension` is a
// String-backed enum, not `String`, so the synthesised encoder takes that path.
// The result is valid JSON that Postgres stores in a jsonb column without
// complaint and that a Swift decoder reads back perfectly, while being
// unreadable by the Edge Function, unqueryable by
// `preference_vector -> 'dimensions' ->> 'formality'`, and wrong in a way only a
// human eyeballing the stored row would ever catch.
extension StylePreferenceVector {

    enum CodingKeys: String, CodingKey {
        case version
        case comparisonsAnswered = "comparisons_answered"
        case comparisonsOffered = "comparisons_offered"
        case dimensions
    }

    /// Dynamic key so the `dimensions` object is keyed by the axis raw values
    /// rather than by a fixed enum of Swift-side names.
    private struct DimensionKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        init(_ dimension: StyleDimension) { stringValue = dimension.rawValue }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        comparisonsAnswered = try container.decodeIfPresent(Int.self, forKey: .comparisonsAnswered) ?? 0
        comparisonsOffered = try container.decodeIfPresent(Int.self, forKey: .comparisonsOffered) ?? 0

        var decoded: [StyleDimension: StyleDimensionReading] = [:]
        if container.contains(.dimensions) {
            let nested = try container.nestedContainer(keyedBy: DimensionKey.self, forKey: .dimensions)
            for key in nested.allKeys {
                // An unrecognised axis is skipped rather than thrown on. If the
                // server ever writes a ninth dimension, an older client must
                // still be able to read the user's own profile — refusing to
                // decode it would break the app for everyone who had not
                // updated.
                guard let dimension = StyleDimension(rawValue: key.stringValue) else { continue }
                decoded[dimension] = try nested.decode(StyleDimensionReading.self, forKey: key)
            }
        }
        dimensions = decoded
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(comparisonsAnswered, forKey: .comparisonsAnswered)
        try container.encode(comparisonsOffered, forKey: .comparisonsOffered)

        var nested = container.nestedContainer(keyedBy: DimensionKey.self, forKey: .dimensions)
        // Emitted in `allCases` order rather than dictionary order, so the same
        // input always produces byte-identical jsonb. That makes a row diff in a
        // support session readable instead of a reshuffle.
        for dimension in StyleDimension.allCases {
            guard let reading = dimensions[dimension] else { continue }
            try nested.encode(reading, forKey: DimensionKey(dimension))
        }
    }
}
