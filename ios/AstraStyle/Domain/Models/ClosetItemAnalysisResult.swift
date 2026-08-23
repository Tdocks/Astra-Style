//
//  ClosetItemAnalysisResult.swift
//  AstraStyle
//
//  The contract between the scan pipeline's server leg (spec §12
//  "Server-side"; endpoints `closet/analyze-item` and
//  `closet/batch-analyze`, spec §14) and the review screen (spec §6.16).
//  Everything the analysis infers about a garment crosses this boundary,
//  and nothing else does.
//
//  This file is deliberately the first thing built in the scanner phase:
//  the Edge Function, the batch flow, the review screen and the client
//  repository all encode assumptions about this shape, so getting it wrong
//  costs four rewrites instead of one.
//
//  ---------------------------------------------------------------------
//  DECISION 1 — Which fields this carries.
//  ---------------------------------------------------------------------
//  A field earns a place here only if BOTH hold: the analysis can actually
//  infer it, AND `ClosetItem`/`ClosetItemImage` can store it. A suggestion
//  the user can see, edit and confirm — but that then evaporates because no
//  column accepts it — is a worse bug than a missing suggestion, because it
//  looks like it worked.
//
//  Applying that rule against `docs/08-provider-abstraction.md` §2's
//  `GarmentAnalysisResult` and spec §5.3 step 5:
//
//  ADDED (storable, and named by the spec or the provider contract):
//    - `fit`          — spec §5.3 step 5 lists fit among what server analysis
//                       suggests, and `closet_items.fit` exists. `docs/08`
//                       §2's TypeScript interface omits it; per CLAUDE.md's
//                       document hierarchy the master spec wins, so the
//                       Edge Function's response schema needs it added.
//    - `size`         — `closet_items.size`, inferable from the care-label
//                       OCR the device pass already extracts (`docs/08` §2's
//                       `deviceHints.detectedText`).
//    - `seasonality`  — `closet_items.seasonality`, inferable from material
//                       and weight.
//    - `formalityScore`        — `docs/08` §2's resolved 0–100 value.
//    - `warmthScore`           — `closet_items.warmth_score`.
//    - `waterResistanceScore`  — `closet_items.water_resistance_score`.
//
//  DELIBERATELY EXCLUDED, despite `docs/08` §2 naming them:
//    - `colorLch` / `secondaryColorsLch`. `closet_items.primary_color` and
//      `secondary_colors` are text. LCh triples have nowhere to land, so
//      carrying them here would create exactly the evaporating-field bug the
//      rule above exists to prevent. The Edge Function must resolve LCh to a
//      colour name server-side — it already has to, to fill the column at all.
//    - `patternScale`. No column; `closet_items.pattern` is a single text value.
//    - `formalityAnchorLow`/`formalityAnchorHigh`/`formalityBlendFraction`.
//      These are the provider's *derivation* of `formalityScore`
//      (05-wardrobe-graph.md §3), auditable server-side. Only the resolved
//      score is storable, and only the resolved score is a thing the review
//      screen could meaningfully let a user correct.
//
//  `normalizedImagePath` maps to `closet_item_images.background_removed_path`
//  and `ocrText` to that table's `analysis_metadata` jsonb — both storable,
//  both kept.
//
//  ---------------------------------------------------------------------
//  DECISION 2 — Confidence on list-valued fields is PER ELEMENT.
//  ---------------------------------------------------------------------
//  `secondaryColors`, `material` and `seasonality` are `[FieldSuggestion<_>]`,
//  not a bare array with one confidence for the whole list. A fabric read as
//  "80% wool, 20% nylon" is frequently confident about the dominant fiber and
//  guessing at the trace one; a single list-level score has to choose between
//  overstating the guess and understating the certainty, and either choice
//  loses information the user needs in order to know which chip to correct.
//  Per-element confidence lets the review screen mark the nylon and leave the
//  wool alone, which is what §6.16's "low-confidence fields are visibly
//  marked" actually asks for at chip granularity.
//
//  ---------------------------------------------------------------------
//  DECISION 3 — `fieldsBelowConfidenceThreshold` is stored AND computed;
//  the marking predicate is their UNION.
//  ---------------------------------------------------------------------
//  Stored alone, the list can silently disagree with the confidences sitting
//  next to it (a server that forgets to populate it — or an older deploy, or
//  the mock — un-marks a field the numbers say is a guess). Computed alone,
//  the client can only see the number, and `docs/08` §2.2's degraded path
//  explicitly has the server mark fields low-confidence for reasons the
//  client cannot reconstruct (exhausted retries, promoted device hints,
//  calibration).
//
//  So both, unioned — see `lowConfidenceFields`. The union is monotone: it
//  can only ever ADD a mark, never remove one, which makes it impossible for
//  a server-side omission to produce an unmarked low-confidence field. That
//  is the direction the review screen's acceptance criterion cares about.
//
//  ---------------------------------------------------------------------
//  DECISION 4 — Batch results are keyed by a client-minted request id.
//  ---------------------------------------------------------------------
//  See `ClosetItemAnalysisRequest` / `ClosetItemAnalysisBatch` below.
//
//  ---------------------------------------------------------------------
//  DECISION 5 — The threshold does not live on `FieldSuggestion`.
//  ---------------------------------------------------------------------
//  See `AnalysisConfidence` below.
//

import Foundation

/// Pipeline-wide confidence policy for the scan analysis.
///
/// The threshold used to live as a static on `FieldSuggestion`, which put a
/// pipeline-level policy number on a generic value wrapper — every
/// `FieldSuggestion<T>` for every T carried its own copy of one product
/// decision, and there was no place to state the decision's source. Hoisting
/// it here gives it exactly one home, one citation, and one thing to change.
///
/// Note this is NOT the same number as the 0.55 in `docs/09-model-routing.md`
/// §2.1, and the two must not be conflated. That one is a *server-side*
/// trigger for re-running the analysis on a stronger model, applies only to
/// the fields §2.7 enumerates, and that document is explicit that it "must be
/// a config value, not a hardcoded constant". This one is the *client-side*
/// display fallback for "mark this field as a guess" when the server did not
/// say so itself (Decision 3 above) — a rendering default, not a routing
/// decision, and safe to hold in code.
public enum AnalysisConfidence {
    /// Below this, the review screen must visibly mark the field (spec §12
    /// "Low-confidence fields should be visibly marked").
    ///
    /// No document fixes a number for the client-side marking threshold;
    /// 0.6 is carried forward from the Phase-1 sketch of this type. It sits
    /// deliberately *above* the server's 0.55 escalation trigger so that a
    /// field which was borderline-but-not-worth-a-retry still reaches the
    /// user marked rather than silently presented as settled.
    public static let lowConfidenceThreshold: Double = 0.6
}

/// A single suggested field value plus a 0–1 confidence score.
public struct FieldSuggestion<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value
    public var confidence: Double

    public init(value: Value, confidence: Double) {
        self.value = value
        self.confidence = confidence
    }

    /// Whether this individual suggestion falls below the client-side
    /// display threshold. This is only half of the marking decision — the
    /// server's own flags are the other half; use
    /// `ClosetItemAnalysisResult.isLowConfidence(_:)` to get both.
    public var isLowConfidence: Bool {
        isLowConfidence(below: AnalysisConfidence.lowConfidenceThreshold)
    }

    /// Threshold-injectable form, so a caller working from a server-supplied
    /// or remotely-configured threshold is not forced through the default.
    public func isLowConfidence(below threshold: Double) -> Bool {
        confidence < threshold
    }
}

/// The addressable fields of an analysis result — the vocabulary shared by
/// the server's `fields_below_confidence_threshold` list, the review
/// screen's per-field marking, and `docs/09-model-routing.md` §2.7's
/// escalation-worthy field set.
///
/// Raw values are the same snake_case names as this result's `CodingKeys`,
/// so the server's flag list and its payload keys cannot drift apart —
/// a flag naming a key that does not exist in the payload beside it is
/// otherwise unnoticeable until someone reads the JSON by hand.
public enum AnalysisField: String, Codable, CaseIterable, Sendable {
    case name
    case brand
    case category
    case subcategory
    case primaryColor = "primary_color"
    case secondaryColors = "secondary_colors"
    case pattern
    case material
    case size
    case fit
    case condition
    case seasonality
    case formalityScore = "formality_score"
    case warmthScore = "warmth_score"
    case waterResistanceScore = "water_resistance_score"

    /// Whether a below-threshold reading of this field triggers a
    /// server-side re-analysis on the escalation tier
    /// (`docs/09-model-routing.md` §2.7 names exactly these four). The
    /// client does not act on this — it is here so the review screen and
    /// the Edge Function cannot hold two different opinions about which
    /// fields are worth a retry, which is the kind of divergence nobody
    /// notices until the escalation rate is measured and disagrees with
    /// the plan.
    public var qualifiesForConfidenceEscalation: Bool {
        switch self {
        case .category, .subcategory, .material, .condition: true
        default: false
        }
    }
}

/// A single garment's inferred attributes, each with a confidence score, for
/// the user to review and correct (spec §12 "User verification": all inferred
/// fields remain editable, low-confidence fields visibly marked).
///
/// Field names deliberately mirror `ClosetItem`'s exactly — `name`, not
/// `suggestedName`. The old `suggested*` prefix restated what the enclosing
/// type already says, and the cost of restating it was that the one-to-one
/// correspondence with the item field each suggestion populates had to be
/// spotted by eye rather than read off. `analysis.fit` fills `item.fit`; that
/// should be obvious at the call site, because the mapping code in the review
/// screen is exactly where a mis-assignment would be silent.
public struct ClosetItemAnalysisResult: Codable, Hashable, Sendable {
    public var name: FieldSuggestion<String>?
    public var brand: FieldSuggestion<String>?

    /// The only non-optional suggestion: `closet_items.category` is `not
    /// null`, so an item cannot be created without one. `docs/08` §2.2's
    /// degraded path guarantees the server can always fill it — it promotes
    /// the device pass's `approximateCategory` rather than returning nothing.
    public var category: FieldSuggestion<ClothingCategory>

    public var subcategory: FieldSuggestion<String>?
    public var primaryColor: FieldSuggestion<String>?
    public var secondaryColors: [FieldSuggestion<String>]
    public var pattern: FieldSuggestion<GarmentPattern>?
    public var material: [FieldSuggestion<String>]
    public var size: FieldSuggestion<String>?
    public var fit: FieldSuggestion<ItemFit>?
    public var condition: FieldSuggestion<ItemCondition>?
    public var seasonality: [FieldSuggestion<Season>]

    /// 0–100, matching the `check (… between 0 and 100)` constraints on the
    /// three score columns. Not clamped here on purpose: an out-of-range
    /// value is a server bug that should surface as a failed insert with a
    /// legible constraint name, not be silently rounded into range by the
    /// client and stored as a plausible-looking wrong number.
    public var formalityScore: FieldSuggestion<Int>?
    public var warmthScore: FieldSuggestion<Int>?
    public var waterResistanceScore: FieldSuggestion<Int>?

    /// Storage path of the background-removed asset (spec §12 server-side
    /// step 7) — becomes `closet_item_images.background_removed_path`.
    public var normalizedImagePath: String?

    /// Raw care-label text, echoed back from the device pass's OCR so the
    /// review screen can show what the brand/size guesses were derived from.
    /// Persists into `closet_item_images.analysis_metadata`.
    public var ocrText: String?

    /// Fields the SERVER declared low-confidence. Not the whole answer —
    /// see `lowConfidenceFields` for the union with the client-side
    /// threshold comparison, and Decision 3 in this file's header for why
    /// both exist.
    public var fieldsBelowConfidenceThreshold: Set<AnalysisField>

    public init(
        name: FieldSuggestion<String>? = nil,
        brand: FieldSuggestion<String>? = nil,
        category: FieldSuggestion<ClothingCategory>,
        subcategory: FieldSuggestion<String>? = nil,
        primaryColor: FieldSuggestion<String>? = nil,
        secondaryColors: [FieldSuggestion<String>] = [],
        pattern: FieldSuggestion<GarmentPattern>? = nil,
        material: [FieldSuggestion<String>] = [],
        size: FieldSuggestion<String>? = nil,
        fit: FieldSuggestion<ItemFit>? = nil,
        condition: FieldSuggestion<ItemCondition>? = nil,
        seasonality: [FieldSuggestion<Season>] = [],
        formalityScore: FieldSuggestion<Int>? = nil,
        warmthScore: FieldSuggestion<Int>? = nil,
        waterResistanceScore: FieldSuggestion<Int>? = nil,
        normalizedImagePath: String? = nil,
        ocrText: String? = nil,
        fieldsBelowConfidenceThreshold: Set<AnalysisField> = []
    ) {
        self.name = name
        self.brand = brand
        self.category = category
        self.subcategory = subcategory
        self.primaryColor = primaryColor
        self.secondaryColors = secondaryColors
        self.pattern = pattern
        self.material = material
        self.size = size
        self.fit = fit
        self.condition = condition
        self.seasonality = seasonality
        self.formalityScore = formalityScore
        self.warmthScore = warmthScore
        self.waterResistanceScore = waterResistanceScore
        self.normalizedImagePath = normalizedImagePath
        self.ocrText = ocrText
        self.fieldsBelowConfidenceThreshold = fieldsBelowConfidenceThreshold
    }

    /// Anonymous scan: bytes stayed on device, so vision never ran.
    public static func guestLocalPlaceholder() -> ClosetItemAnalysisResult {
        ClosetItemAnalysisResult(
            category: FieldSuggestion(value: .top, confidence: 0.2),
            fieldsBelowConfidenceThreshold: [.category]
        )
    }

    enum CodingKeys: String, CodingKey {
        case name
        case brand
        case category
        case subcategory
        case primaryColor = "primary_color"
        case secondaryColors = "secondary_colors"
        case pattern
        case material
        case size
        case fit
        case condition
        case seasonality
        case formalityScore = "formality_score"
        case warmthScore = "warmth_score"
        case waterResistanceScore = "water_resistance_score"
        case normalizedImagePath = "normalized_image_path"
        case ocrText = "ocr_text"
        case fieldsBelowConfidenceThreshold = "fields_below_confidence_threshold"
    }
}

// MARK: - Codable

extension ClosetItemAnalysisResult {
    /// Hand-written rather than synthesised for two reasons the synthesised
    /// version cannot give: the three list fields and the flag set must
    /// decode to empty when the key is absent (an omitted `material` means
    /// "nothing inferred", not "malformed payload" — and `docs/08` §2.2's
    /// degraded response omits most keys by design), and unknown entries in
    /// the flag list must be dropped rather than throw.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // An unrecognised field name means the server marks something this
        // client build cannot render. Dropping it is strictly better than
        // failing the whole decode: the user still gets every field this
        // build knows about, and the one it doesn't know about is one it
        // could not have drawn a marker next to anyway.
        let rawFlags = try container.decodeIfPresent([String].self, forKey: .fieldsBelowConfidenceThreshold) ?? []

        self.init(
            name: try container.decodeIfPresent(FieldSuggestion<String>.self, forKey: .name),
            brand: try container.decodeIfPresent(FieldSuggestion<String>.self, forKey: .brand),
            category: try container.decode(FieldSuggestion<ClothingCategory>.self, forKey: .category),
            subcategory: try container.decodeIfPresent(FieldSuggestion<String>.self, forKey: .subcategory),
            primaryColor: try container.decodeIfPresent(FieldSuggestion<String>.self, forKey: .primaryColor),
            secondaryColors: try container.decodeIfPresent([FieldSuggestion<String>].self, forKey: .secondaryColors) ?? [],
            pattern: try container.decodeIfPresent(FieldSuggestion<GarmentPattern>.self, forKey: .pattern),
            material: try container.decodeIfPresent([FieldSuggestion<String>].self, forKey: .material) ?? [],
            size: try container.decodeIfPresent(FieldSuggestion<String>.self, forKey: .size),
            fit: try container.decodeIfPresent(FieldSuggestion<ItemFit>.self, forKey: .fit),
            condition: try container.decodeIfPresent(FieldSuggestion<ItemCondition>.self, forKey: .condition),
            seasonality: try container.decodeIfPresent([FieldSuggestion<Season>].self, forKey: .seasonality) ?? [],
            formalityScore: try container.decodeIfPresent(FieldSuggestion<Int>.self, forKey: .formalityScore),
            warmthScore: try container.decodeIfPresent(FieldSuggestion<Int>.self, forKey: .warmthScore),
            waterResistanceScore: try container.decodeIfPresent(FieldSuggestion<Int>.self, forKey: .waterResistanceScore),
            normalizedImagePath: try container.decodeIfPresent(String.self, forKey: .normalizedImagePath),
            ocrText: try container.decodeIfPresent(String.self, forKey: .ocrText),
            fieldsBelowConfidenceThreshold: Set(rawFlags.compactMap(AnalysisField.init(rawValue:)))
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(subcategory, forKey: .subcategory)
        try container.encodeIfPresent(primaryColor, forKey: .primaryColor)
        try container.encode(secondaryColors, forKey: .secondaryColors)
        try container.encodeIfPresent(pattern, forKey: .pattern)
        try container.encode(material, forKey: .material)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(fit, forKey: .fit)
        try container.encodeIfPresent(condition, forKey: .condition)
        try container.encode(seasonality, forKey: .seasonality)
        try container.encodeIfPresent(formalityScore, forKey: .formalityScore)
        try container.encodeIfPresent(warmthScore, forKey: .warmthScore)
        try container.encodeIfPresent(waterResistanceScore, forKey: .waterResistanceScore)
        try container.encodeIfPresent(normalizedImagePath, forKey: .normalizedImagePath)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
        // Sorted because `Set` has no order: without this, encoding the same
        // value twice can produce different bytes, which turns any
        // payload-equality assertion into an intermittent failure.
        try container.encode(fieldsBelowConfidenceThreshold.map(\.rawValue).sorted(), forKey: .fieldsBelowConfidenceThreshold)
    }
}

// MARK: - Low-confidence resolution

extension ClosetItemAnalysisResult {
    /// Every field the review screen must visibly mark (spec §12): the
    /// server's own declarations unioned with the client's threshold
    /// comparison. See Decision 3 in this file's header for why it is the
    /// union and not either half alone.
    public var lowConfidenceFields: Set<AnalysisField> {
        var resolved = fieldsBelowConfidenceThreshold
        for (field, isBelowThreshold) in computedLowConfidenceFields where isBelowThreshold {
            resolved.insert(field)
        }
        return resolved
    }

    /// The single predicate the review screen should call per field.
    public func isLowConfidence(_ field: AnalysisField) -> Bool {
        lowConfidenceFields.contains(field)
    }

    /// The client-side half of the union: field → "is this field's own
    /// confidence below the threshold".
    ///
    /// Written as a lookup table rather than a `switch` over
    /// `AnalysisField` deliberately. Both forms have to name all fifteen
    /// fields, but the table reads as one list you can diff against the
    /// stored properties above, and adding a sixteenth field is a one-line
    /// addition rather than a new control-flow branch. A `switch` here also
    /// carried enough cyclomatic complexity to trip the linter, which is the
    /// tool correctly pointing out that fifteen branches computing the same
    /// expression is not really branching.
    private var computedLowConfidenceFields: [AnalysisField: Bool] {
        [
            .name: Self.isLow(name),
            .brand: Self.isLow(brand),
            .category: Self.isLow(category),
            .subcategory: Self.isLow(subcategory),
            .primaryColor: Self.isLow(primaryColor),
            .secondaryColors: Self.isLow(secondaryColors),
            .pattern: Self.isLow(pattern),
            .material: Self.isLow(material),
            .size: Self.isLow(size),
            .fit: Self.isLow(fit),
            .condition: Self.isLow(condition),
            .seasonality: Self.isLow(seasonality),
            .formalityScore: Self.isLow(formalityScore),
            .warmthScore: Self.isLow(warmthScore),
            .waterResistanceScore: Self.isLow(waterResistanceScore)
        ]
    }

    private static func isLow<Value>(_ suggestion: FieldSuggestion<Value>?) -> Bool {
        suggestion?.isLowConfidence == true
    }

    /// A list field counts as low-confidence when ANY element is, because the
    /// marker the user sees sits on the group of chips. Each chip's own
    /// `isLowConfidence` is what decides which chips inside the group get
    /// marked (Decision 2).
    private static func isLow<Value>(_ suggestions: [FieldSuggestion<Value>]) -> Bool {
        suggestions.contains { $0.isLowConfidence }
    }
}

// MARK: - Request side

/// Pre-computed on-device results passed to the server as priors
/// (`docs/08-provider-abstraction.md` §2's `GarmentAnalysisRequest.deviceHints`).
///
/// These exist on the request type rather than being re-derived server-side
/// because the device pass (spec §12 "Device-side") has already done the work
/// and, per `docs/08` §2.5, is *better* at it: label OCR is Apple Vision's
/// job, and the server model reasons over the extracted text rather than
/// re-reading small angled type out of pixels.
public struct GarmentDeviceHints: Codable, Hashable, Sendable {
    /// Hex RGB strings from the device's dominant-colour extraction.
    public var dominantColorsRGB: [String]
    /// Raw care-label text lines from the device OCR pass.
    public var detectedText: [String]
    /// The device pass's coarse guess. Also the server's fallback for
    /// `category` when analysis fails outright (`docs/08` §2.2).
    public var approximateCategory: ClothingCategory?

    public init(dominantColorsRGB: [String] = [], detectedText: [String] = [], approximateCategory: ClothingCategory? = nil) {
        self.dominantColorsRGB = dominantColorsRGB
        self.detectedText = detectedText
        self.approximateCategory = approximateCategory
    }

    enum CodingKeys: String, CodingKey {
        case dominantColorsRGB = "dominant_colors_rgb"
        case detectedText = "detected_text"
        case approximateCategory = "approximate_category"
    }
}

/// One image submitted for analysis, with a client-minted identity.
///
/// The identity is the whole point. The previous batch signature took
/// `[Data]` and returned `[ClosetItemAnalysisResult]`, which made position
/// the only correspondence between an input and its result — and position is
/// not preserved by anything in the pipeline: the mock fanned out with
/// `withThrowingTaskGroup` and returned completion-ordered results, and a
/// server that uses a provider batch endpoint (`docs/08` §2.3 recommends
/// exactly that) has no reason to preserve submission order either. A
/// position-keyed contract makes "the wrong photo's suggestions attached to
/// this garment" a silent data error rather than a crash.
///
/// Deliberately NOT `Codable`. `imageData` is uploaded to Storage and the
/// wire request carries the resulting signed path (`docs/08` §2's
/// `imageStoragePath`, "never a public URL"); making this encodable would
/// invite base64-ing megabytes of garment photo into a JSON body.
public struct ClosetItemAnalysisRequest: Identifiable, Hashable, Sendable {
    /// Correlation id echoed back by the server on the matching result.
    /// Minted client-side, not server-side, so the caller can build its
    /// id → capture mapping before the request is ever sent — which is what
    /// makes a partial failure attributable to a specific photo the user
    /// can retake.
    public let id: UUID
    public var imageData: Data
    /// When set (from a prior `uploadCapturedImage`), the live repository
    /// skips the upload leg and sends this path to the Edge Function.
    /// Keeps analyze-retry from orphaning a second Storage object.
    public var storagePath: String?
    public var imageType: ClosetImageType
    public var deviceHints: GarmentDeviceHints?

    public init(
        id: UUID = UUID(),
        imageData: Data,
        storagePath: String? = nil,
        imageType: ClosetImageType = .front,
        deviceHints: GarmentDeviceHints? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.storagePath = storagePath
        self.imageType = imageType
        self.deviceHints = deviceHints
    }
}

// MARK: - Batch response

/// Why one item of a batch produced no analysis.
public enum ClosetItemAnalysisFailureReason: String, Codable, CaseIterable, Sendable {
    /// Blur/exposure/framing made the capture unusable — the user can fix
    /// this by retaking the photo.
    case imageUnusable = "image_unusable"
    /// The image analysed fine but contains no recognisable garment.
    case noGarmentDetected = "no_garment_detected"
    /// The vision provider errored or exhausted its retries (`docs/08` §0.1).
    case providerUnavailable = "provider_unavailable"
    /// 429 from the provider or Astra's own limiter (spec §14 "Rate limit").
    case rateLimited = "rate_limited"
    /// Exceeded the §20 latency ceiling for this item.
    case timedOut = "timed_out"
    /// Anything this client build does not recognise. Present so a server
    /// that adds a reason does not break decoding on already-shipped
    /// clients — a batch that decodes with one vague reason is far better
    /// than a batch that fails to decode at all.
    case unknown

    /// Whether resubmitting the same photo could plausibly succeed. Drives
    /// the difference between offering "try again" and asking for a new
    /// capture — spec §22's acceptance bar forbids a dead button, and a
    /// retry control on `noGarmentDetected` is exactly that.
    public var isRetryable: Bool {
        switch self {
        case .providerUnavailable, .rateLimited, .timedOut: true
        case .imageUnusable, .noGarmentDetected, .unknown: false
        }
    }
}

/// The failure half of a per-item outcome.
public struct ClosetItemAnalysisFailure: Codable, Hashable, Sendable, Error {
    public var reason: ClosetItemAnalysisFailureReason
    /// Diagnostic detail from the server. Not user-facing copy — the client
    /// owns what the user reads, per spec §11's rule that the app renders
    /// structured payloads rather than reformatting server prose.
    public var message: String?

    public init(reason: ClosetItemAnalysisFailureReason, message: String? = nil) {
        self.reason = reason
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case reason
        case message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawReason = try container.decode(String.self, forKey: .reason)
        reason = ClosetItemAnalysisFailureReason(rawValue: rawReason) ?? .unknown
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

/// What happened to one submitted image. An enum rather than a struct with
/// two optionals so "neither a result nor an error" and "both at once" are
/// unrepresentable — a batch item that is somehow neither is precisely the
/// state a review screen would render as a blank, editable, saveable card.
public enum ClosetItemAnalysisOutcome: Hashable, Sendable {
    case analyzed(ClosetItemAnalysisResult)
    case failed(ClosetItemAnalysisFailure)

    public var result: ClosetItemAnalysisResult? {
        if case .analyzed(let result) = self { result } else { nil }
    }

    public var failure: ClosetItemAnalysisFailure? {
        if case .failed(let failure) = self { failure } else { nil }
    }
}

/// One entry of a batch response: an outcome bound to the request id it
/// answers.
public struct ClosetItemAnalysisBatchItem: Identifiable, Codable, Hashable, Sendable {
    /// Echoes `ClosetItemAnalysisRequest.id`.
    public let id: UUID
    public var outcome: ClosetItemAnalysisOutcome

    public init(id: UUID, outcome: ClosetItemAnalysisOutcome) {
        self.id = id
        self.outcome = outcome
    }

    enum CodingKeys: String, CodingKey {
        case id = "request_id"
        case result
        case error
    }

    /// `error` is checked first: if the server sent both (it should not),
    /// treating the item as failed is the conservative reading — it shows
    /// the user a retry affordance instead of silently accepting suggestions
    /// the server itself flagged as broken.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if let failure = try container.decodeIfPresent(ClosetItemAnalysisFailure.self, forKey: .error) {
            outcome = .failed(failure)
        } else {
            outcome = .analyzed(try container.decode(ClosetItemAnalysisResult.self, forKey: .result))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch outcome {
        case .analyzed(let result): try container.encode(result, forKey: .result)
        case .failed(let failure): try container.encode(failure, forKey: .error)
        }
    }
}

/// Enqueue response from `POST /closet/batch-analyze` (job+poll, not sync).
public struct ClosetItemAnalysisBatchJob: Codable, Hashable, Sendable {
    public var jobID: UUID
    public var status: ClosetItemAnalysisBatchJobStatus

    public init(jobID: UUID, status: ClosetItemAnalysisBatchJobStatus) {
        self.jobID = jobID
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
    }
}

/// Status vocabulary shared with `generation_status` / Style Studio polls.
public enum ClosetItemAnalysisBatchJobStatus: String, Codable, Hashable, Sendable {
    case queued
    case generating
    case complete
    case failed

    public var isTerminal: Bool {
        switch self {
        case .complete, .failed: true
        case .queued, .generating: false
        }
    }
}

/// Poll response from `GET /closet/batch-status/:id`.
public struct ClosetItemAnalysisBatchJobStatusPayload: Codable, Hashable, Sendable {
    public var jobID: UUID
    public var status: ClosetItemAnalysisBatchJobStatus
    public var results: [ClosetItemAnalysisBatchItem]
    public var errorMessage: String?

    public init(
        jobID: UUID,
        status: ClosetItemAnalysisBatchJobStatus,
        results: [ClosetItemAnalysisBatchItem] = [],
        errorMessage: String? = nil
    ) {
        self.jobID = jobID
        self.status = status
        self.results = results
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case results
        case errorMessage = "error_message"
    }

    public var asBatch: ClosetItemAnalysisBatch {
        ClosetItemAnalysisBatch(results: results)
    }
}

/// The completed batch payload (results keyed by request id).
///
/// An object wrapping `results` rather than a bare top-level array, for two
/// reasons: a JSON array has nowhere to hang batch-level metadata (a partial
/// batch will eventually want a request id or a cost/latency record, spec
/// §14 "Log request ID and latency"), and a top-level array cannot be
/// extended without breaking every existing decoder.
///
/// `POST /closet/batch-analyze` itself no longer returns this synchronously
/// — it returns `ClosetItemAnalysisBatchJob`. `LiveClosetRepository` polls
/// `batch-status` and reassembles this type for `batchAnalyzeItems` callers.
public struct ClosetItemAnalysisBatch: Codable, Hashable, Sendable {
    public var results: [ClosetItemAnalysisBatchItem]

    public init(results: [ClosetItemAnalysisBatchItem]) {
        self.results = results
    }

    enum CodingKeys: String, CodingKey {
        case results
    }

    /// Look up by identity. This — not `results[index]` — is how a caller is
    /// meant to read a batch; see `ClosetItemAnalysisRequest` for why.
    public func outcome(for requestID: UUID) -> ClosetItemAnalysisOutcome? {
        results.first { $0.id == requestID }?.outcome
    }

    public func result(for requestID: UUID) -> ClosetItemAnalysisResult? {
        outcome(for: requestID)?.result
    }

    public func failure(for requestID: UUID) -> ClosetItemAnalysisFailure? {
        outcome(for: requestID)?.failure
    }

    /// Successfully analysed items, keyed by request id.
    public var analyzed: [UUID: ClosetItemAnalysisResult] {
        results.reduce(into: [:]) { partial, item in
            partial[item.id] = item.outcome.result
        }
    }

    /// Failed items, keyed by request id — the thing "identifies which one
    /// failed" is asking for.
    public var failures: [UUID: ClosetItemAnalysisFailure] {
        results.reduce(into: [:]) { partial, item in
            partial[item.id] = item.outcome.failure
        }
    }

    /// True when at least one item failed and at least one succeeded — the
    /// state the batch flow must render rather than treating as success or
    /// as a thrown error.
    public var isPartialFailure: Bool {
        !failures.isEmpty && !analyzed.isEmpty
    }
}
