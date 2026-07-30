//
//  StyleQuizCatalog.swift
//  AstraStyle
//
//  The set of paired-image comparisons spec §6.9 draws on, loaded from a
//  manifest rather than declared in Swift.
//
//  WHY THIS IS CONTENT AND NOT CODE.
//
//  §6.9 wants 12–20 comparisons across eight dimensions. `brand/quiz-imagery/`
//  currently holds three pairs. The remaining thirteen-plus are a photography
//  and art-direction job, not an engineering one — and `docs/01-build-roadmap.md`
//  names that content dependency as a Phase 2 risk that "can silently block the
//  whole phase if treated as 'just wire up the UI'." So the shape of this file
//  is the mitigation: adding the missing pairs must be dropping two images and
//  a JSON stanza into `Resources/QuizImagery/`, with no Swift touched and no
//  build knowledge required. `P2-ONBOARD-07`'s acceptance criteria say the same
//  thing in one line — "content-managed (loaded from a config/catalog), not
//  hardcoded per-build."
//
//  WHY THE CATALOG FILTERS ITSELF.
//
//  A manifest entry whose image is not actually in the bundle is dropped, not
//  rendered as a grey box. The alternative — shipping a placeholder frame —
//  would be worse than useless here: the user answers the comparison anyway, and
//  the inference records a style preference derived from a picture of nothing.
//  A short honest quiz is a correct outcome. A long dishonest one is not.
//
//  The same rule is what makes the manifest safe to edit ahead of the imagery:
//  a content editor can stage the full 16-pair manifest today, and each pair
//  switches on by itself as its photographs land.
//

import Foundation
import OSLog

// MARK: - Locating imagery

/// Finds the file backing a manifest's image name.
///
/// A protocol rather than a direct `Bundle` call so the catalog's parsing and
/// validation are testable without a bundle at all — which matters because the
/// interesting cases (a pair referencing a missing image, a manifest listing all
/// eight axes) are exactly the ones there is no imagery for yet.
public protocol StyleQuizImageLocating: Sendable {
    func imageURL(named name: String) -> URL?
}

/// Resolves against the app bundle's `QuizImagery` content directory.
public struct BundleStyleQuizImageLocator: StyleQuizImageLocating {
    public static let directoryName = "QuizImagery"

    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func imageURL(named name: String) -> URL? {
        // Both lookups, in this order, on purpose. Whether a resource directory
        // survives into the built product as a real subdirectory or is flattened
        // into the bundle root depends on how the copy-resources phase was
        // configured — and that is a project-generation detail that can change
        // under this code without any Swift changing. Asking for both costs one
        // extra failed lookup on a cold path and removes an entire class of
        // "works in the simulator, empty on device" bug.
        bundle.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: Self.directoryName
        ) ?? bundle.url(forResource: name, withExtension: "jpg")
    }
}

/// Test double: claims every name resolves, without touching the file system.
public struct AlwaysResolvingImageLocator: StyleQuizImageLocating {
    public init() {}
    public func imageURL(named name: String) -> URL? {
        URL(string: "astra-test://quiz-imagery/\(name).jpg")
    }
}

/// Test double: resolves only the names it was given.
public struct FixedStyleQuizImageLocator: StyleQuizImageLocating {
    private let available: Set<String>
    public init(available: Set<String>) { self.available = available }
    public func imageURL(named name: String) -> URL? {
        available.contains(name) ? URL(string: "astra-test://quiz-imagery/\(name).jpg") : nil
    }
}

// MARK: - One side of a comparison

/// One of the two outfits in a comparison.
public struct StyleQuizOption: Hashable, Sendable, Identifiable {

    /// The value written to `StylePreferenceQuizAnswer.chosenOptionID`, and
    /// therefore part of the stored record of what the user chose. Unique within
    /// its pair, not globally.
    public let id: String

    /// Manifest image name, without extension.
    public let imageName: String

    /// Resolved at load time, so a pair only ever reaches the UI with real
    /// imagery behind it.
    public let imageURL: URL

    /// What VoiceOver reads instead of the photograph.
    ///
    /// NOT optional, and validated as non-empty. A paired-IMAGE quiz with no
    /// alternative text is not a degraded experience for a blind user, it is a
    /// screen with two unlabelled buttons — spec §19 requires VoiceOver labels
    /// and this is the one screen in onboarding where the entire question lives
    /// in the picture.
    ///
    /// Written as a description of the clothes, never of the intent: "a navy
    /// blazer over a white shirt with grey trousers", not "the formal option".
    /// Naming the axis would tell a VoiceOver user which answer means what,
    /// which is a different question from the one sighted users are answering.
    public let accessibilityDescription: String

    /// How strongly, and in which direction, choosing this option loads on each
    /// axis. −1…+1 per axis, per `StyleDimension`'s sign convention.
    ///
    /// A dictionary rather than a single dimension because a well-designed pair
    /// can legitimately probe more than one axis — a tailored look is usually
    /// also a higher-contrast one. It is also how a pair overstates its reach:
    /// see `StyleQuizCatalog`'s notes and the manifest README for why the three
    /// shipped pairs each declare exactly one loading.
    public let loadings: [StyleDimension: Double]

    public init(
        id: String,
        imageName: String,
        imageURL: URL,
        accessibilityDescription: String,
        loadings: [StyleDimension: Double]
    ) {
        self.id = id
        self.imageName = imageName
        self.imageURL = imageURL
        self.accessibilityDescription = accessibilityDescription
        self.loadings = loadings
    }
}

// MARK: - A comparison

public struct StyleQuizPair: Hashable, Sendable, Identifiable {

    /// The reserved option id recording "I have no preference between these
    /// two".
    ///
    /// A real answer, stored like any other, rather than an absence. A user who
    /// is indifferent between two outfits and is forced to pick one contributes
    /// a coin flip to the inference, and a coin flip is indistinguishable
    /// downstream from a real preference. Given how few comparisons each axis
    /// gets (see `StylePreferenceInference`), one coin flip can be an entire
    /// axis's evidence.
    ///
    /// Reserved: `StyleQuizCatalog` rejects a manifest that uses this as an
    /// option id, so a content edit can never collide with it.
    public static let noPreferenceOptionID = "no_preference"

    public let id: String
    public let optionA: StyleQuizOption
    public let optionB: StyleQuizOption

    /// Lower sorts earlier among pairs that are otherwise equally useful. Lets
    /// content decide which comparison opens the quiz — the first one sets the
    /// tone on the highest-drop-off screen in the app — without giving content
    /// control over the rest of the ordering, which the engine chooses on
    /// coverage grounds.
    public let priority: Int

    public init(id: String, optionA: StyleQuizOption, optionB: StyleQuizOption, priority: Int = 0) {
        self.id = id
        self.optionA = optionA
        self.optionB = optionB
        self.priority = priority
    }

    public var options: [StyleQuizOption] { [optionA, optionB] }

    public func option(withID optionID: String) -> StyleQuizOption? {
        options.first { $0.id == optionID }
    }

    /// Every axis either side of this comparison touches.
    public var probedDimensions: Set<StyleDimension> {
        Set(optionA.loadings.keys).union(optionB.loadings.keys)
    }

    /// The most signal this pair could contribute to one axis, if answered
    /// rather than passed on. Used by the engine to order for coverage.
    public func maximumLoading(on dimension: StyleDimension) -> Double {
        max(abs(optionA.loadings[dimension] ?? 0), abs(optionB.loadings[dimension] ?? 0))
    }
}

// MARK: - The catalog

public struct StyleQuizCatalog: Sendable {

    /// Spec §6.9: "Use 12–20 comparisons." Held as a value rather than a
    /// comment so `meetsSpecifiedLength` can say plainly whether the imagery
    /// that exists is enough yet, and so the day it becomes enough is a data
    /// change that flips a Bool rather than a doc nobody re-reads.
    public static let specifiedComparisonRange = 12...20

    /// Why a manifest entry did not make it into `pairs`.
    ///
    /// Surfaced rather than swallowed: the whole point of a content-managed
    /// catalog is that someone who is not an engineer edits it, and a typo that
    /// silently removes a comparison is a bad way to find that out.
    public struct Exclusion: Hashable, Sendable {
        public let pairID: String
        public let reason: String
        public init(pairID: String, reason: String) {
            self.pairID = pairID
            self.reason = reason
        }
    }

    /// Every comparison that is fully usable: valid, and with both photographs
    /// actually present.
    public let pairs: [StyleQuizPair]

    /// Manifest entries that were dropped, with the reason for each.
    public let excluded: [Exclusion]

    public init(pairs: [StyleQuizPair], excluded: [Exclusion] = []) {
        self.pairs = pairs
        self.excluded = excluded
    }

    public static let empty = StyleQuizCatalog(pairs: [], excluded: [])

    /// Whether the imagery that exists can satisfy §6.9's stated length.
    ///
    /// Currently false, and that is reported rather than hidden — the UI counts
    /// the comparisons it actually has instead of showing "1 of 16" against a
    /// number it cannot reach. A progress indicator that lies is worse on this
    /// screen than on any other in the app: `docs/01-build-roadmap.md` calls
    /// onboarding the highest-drop-off surface there is, and a bar that stalls
    /// is the thing people quit on.
    public var meetsSpecifiedLength: Bool {
        Self.specifiedComparisonRange.contains(pairs.count)
    }

    /// Axes at least one available comparison touches.
    public var probedDimensions: Set<StyleDimension> {
        pairs.reduce(into: Set<StyleDimension>()) { $0.formUnion($1.probedDimensions) }
    }

    /// The §6.9 axes no available comparison can say anything about, in spec
    /// order. These come back from the inference as absent rather than neutral.
    public var unprobedDimensions: [StyleDimension] {
        let probed = probedDimensions
        return StyleDimension.allCases.filter { !probed.contains($0) }
    }
}

// MARK: - Manifest decoding

/// The on-disk shape of `Resources/QuizImagery/quiz-pairs.json`.
///
/// Kept private and separate from `StyleQuizPair` so the file format and the
/// in-memory model can move independently: the manifest is edited by hand by
/// people adding content, and it should be able to gain optional fields without
/// every one of them becoming a property the rest of the app has to reason
/// about.
private struct QuizManifest: Decodable {
    struct Option: Decodable {
        let id: String
        let image: String
        let accessibilityDescription: String
        let loadings: [String: Double]

        enum CodingKeys: String, CodingKey {
            case id
            case image
            case accessibilityDescription = "accessibility_description"
            case loadings
        }
    }

    struct Pair: Decodable {
        let id: String
        let priority: Int?
        let optionA: Option
        let optionB: Option

        enum CodingKeys: String, CodingKey {
            case id
            case priority
            case optionA = "option_a"
            case optionB = "option_b"
        }
    }

    let version: Int
    let pairs: [Pair]
}

public enum StyleQuizCatalogError: Error, CustomStringConvertible {
    case unreadableManifest(String)

    public var description: String {
        switch self {
        case .unreadableManifest(let detail): "Quiz manifest could not be read: \(detail)"
        }
    }
}

public extension StyleQuizCatalog {

    /// File name of the manifest inside the content directory.
    static let manifestFileName = "quiz-pairs"

    /// Parses a manifest and keeps only the comparisons that are both valid and
    /// backed by imagery that exists.
    ///
    /// Never throws on a bad individual pair — a single malformed stanza must
    /// not take the whole quiz down, because the person who introduced it is
    /// editing content, not code, and the failure would surface as a blank step
    /// in onboarding rather than as a compile error. It throws only when the
    /// document as a whole is unreadable, which is the case a caller genuinely
    /// has to handle differently.
    static func load(
        manifestData: Data,
        locator: any StyleQuizImageLocating
    ) throws -> StyleQuizCatalog {
        let manifest: QuizManifest
        do {
            manifest = try JSONDecoder().decode(QuizManifest.self, from: manifestData)
        } catch {
            throw StyleQuizCatalogError.unreadableManifest(String(describing: error))
        }

        var pairs: [StyleQuizPair] = []
        var excluded: [Exclusion] = []
        var seenPairIDs: Set<String> = []

        for entry in manifest.pairs {
            if entry.id.isEmpty {
                excluded.append(Exclusion(pairID: "(unnamed)", reason: "The pair has no id."))
                continue
            }
            if !seenPairIDs.insert(entry.id).inserted {
                // Answers are recorded against the pair id, so two pairs sharing
                // one would make the stored answers ambiguous forever after.
                excluded.append(Exclusion(
                    pairID: entry.id,
                    reason: "Duplicate pair id; answers are recorded against it and must be unique."
                ))
                continue
            }

            switch Self.makePair(from: entry, locator: locator) {
            case .usable(let pair): pairs.append(pair)
            case .unusable(let reason): excluded.append(Exclusion(pairID: entry.id, reason: reason))
            }
        }

        return StyleQuizCatalog(pairs: pairs, excluded: excluded)
    }
}

/// A manifest entry that either survived validation or did not, with the reason
/// it did not.
///
/// A dedicated type rather than `Result<Value, String>`, because `String` is not
/// an `Error` and rather than making it one — or inventing an error type that is
/// never thrown — this says what is actually happening: nothing here fails, it
/// is a filter that keeps its rejects' reasons so a content editor can read them.
private enum Validated<Value> {
    case usable(Value)
    case unusable(String)
}

private extension StyleQuizCatalog {

    /// Validates one manifest entry and resolves its imagery, or says why it
    /// cannot be used. The reason strings are read by whoever is adding content,
    /// so they name the fix rather than the rule.
    static func makePair(
        from entry: QuizManifest.Pair,
        locator: any StyleQuizImageLocating
    ) -> Validated<StyleQuizPair> {
        guard entry.optionA.id != entry.optionB.id else {
            return .unusable("Both options have the id \"\(entry.optionA.id)\"; they must differ.")
        }
        let reserved = StyleQuizPair.noPreferenceOptionID
        guard entry.optionA.id != reserved, entry.optionB.id != reserved else {
            return .unusable(
                "\"\(reserved)\" is reserved for the no-preference answer and "
                + "cannot be an option id."
            )
        }

        var built: [StyleQuizOption] = []
        for option in [entry.optionA, entry.optionB] {
            switch makeOption(from: option, locator: locator) {
            case .usable(let value): built.append(value)
            case .unusable(let reason): return .unusable(reason)
            }
        }
        guard built.count == 2 else {
            return .unusable("Expected exactly two options.")
        }

        // A comparison that loads on nothing records an answer and infers
        // nothing from it — a question asked for no reason, on the screen users
        // are most likely to abandon.
        let optionA = built[0]
        let optionB = built[1]
        if optionA.loadings.isEmpty && optionB.loadings.isEmpty {
            return .unusable("Neither option loads on any dimension, so the answer could not be used.")
        }

        return .usable(
            StyleQuizPair(
                id: entry.id,
                optionA: optionA,
                optionB: optionB,
                priority: entry.priority ?? 0
            )
        )
    }

    static func makeOption(
        from option: QuizManifest.Option,
        locator: any StyleQuizImageLocating
    ) -> Validated<StyleQuizOption> {
        guard !option.id.isEmpty else { return .unusable("An option has no id.") }
        guard !option.image.isEmpty else { return .unusable("Option \"\(option.id)\" has no image.") }

        let description = option.accessibilityDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return .unusable(
                "Option \"\(option.id)\" has no accessibility_description. The whole "
                + "question is in the photograph, so without it this comparison is "
                + "unanswerable with VoiceOver."
            )
        }

        var loadings: [StyleDimension: Double] = [:]
        for (key, value) in option.loadings {
            guard let dimension = StyleDimension(rawValue: key) else {
                return .unusable(
                    "Option \"\(option.id)\" loads on \"\(key)\", which is not one of "
                    + "the eight dimensions in spec §6.9."
                )
            }
            guard value >= -1, value <= 1 else {
                return .unusable(
                    "Option \"\(option.id)\" loads \(value) on \"\(key)\"; loadings run from -1 to 1."
                )
            }
            // A zero loading is not an error, but it is not evidence either, so
            // it is dropped rather than counted as an observation of nothing.
            guard value != 0 else { continue }
            loadings[dimension] = value
        }

        guard let url = locator.imageURL(named: option.image) else {
            return .unusable(
                "The image \"\(option.image)\" is not in the app bundle. The comparison "
                + "is left out until it is — a placeholder frame would be answered like a "
                + "real one and recorded as a real preference."
            )
        }

        return .usable(
            StyleQuizOption(
                id: option.id,
                imageName: option.image,
                imageURL: url,
                accessibilityDescription: description,
                loadings: loadings
            )
        )
    }
}

// MARK: - The bundled catalog

public extension StyleQuizCatalog {

    /// The comparisons shipped in this build.
    ///
    /// Non-throwing on purpose. Every failure mode here — no manifest, bad JSON,
    /// no imagery — ends in an empty catalog, and an empty catalog is a state
    /// the quiz already has to handle correctly because §6.9's step is
    /// skippable. Turning a content problem into a thrown error would convert
    /// "the quiz has nothing to ask" into "onboarding is broken", which is a far
    /// worse outcome for the same underlying cause.
    ///
    /// Everything that went wrong is logged, and everything that was dropped is
    /// on `excluded`, so the silence is only towards the user.
    static func bundled(
        bundle: Bundle = .main,
        locator: (any StyleQuizImageLocating)? = nil
    ) -> StyleQuizCatalog {
        let logger = Logger(subsystem: "com.astrastyle.app", category: "onboarding")
        let resolver = locator ?? BundleStyleQuizImageLocator(bundle: bundle)

        let url = bundle.url(
            forResource: manifestFileName,
            withExtension: "json",
            subdirectory: BundleStyleQuizImageLocator.directoryName
        ) ?? bundle.url(forResource: manifestFileName, withExtension: "json")

        guard let url else {
            logger.error("Quiz manifest \(manifestFileName).json is not in the bundle; the quiz has no comparisons.")
            return .empty
        }

        do {
            let catalog = try load(manifestData: try Data(contentsOf: url), locator: resolver)
            for exclusion in catalog.excluded {
                logger.warning("Quiz pair \(exclusion.pairID) excluded: \(exclusion.reason)")
            }
            logger.info("Quiz catalog loaded with \(catalog.pairs.count) comparison(s).")
            return catalog
        } catch {
            logger.error("Quiz manifest unreadable: \(String(describing: error))")
            return .empty
        }
    }
}
