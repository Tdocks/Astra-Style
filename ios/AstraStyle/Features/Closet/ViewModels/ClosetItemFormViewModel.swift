//
//  ClosetItemFormViewModel.swift
//  AstraStyle
//
//  The manual, non-scan way a garment gets into the closet, and the only
//  surface that edits one (spec §6.15's "editable fields", ticket
//  P3-CLOSET-08). Drives `ClosetItemFormView`.
//
//  IT NEVER TOUCHES THE CAMERA. That is the entire point of the ticket —
//  "a garment can be added end-to-end without ever opening the camera" —
//  and it is also spec §7's permission rule: the scanner asks for the
//  camera because the scanner is the camera. Nothing here imports
//  AVFoundation, offers a "scan instead" affordance, or reaches
//  `ClosetRepository.analyzeItem`.
//
//  ONE FORM FOR ADD AND EDIT. `Mode` is the only difference, and it is a
//  difference of three things: the copy, where the user id comes from, and
//  which repository verb runs. Two screens would have meant two field
//  lists, and a field list that exists twice is a field list that drifts —
//  which is exactly the reasoning `OnboardingViewModel+FirstItems` gives
//  for keeping the onboarding step to three fields and leaving the full
//  editor here.
//
//  WHY THERE IS NO `ViewState` ENUM. `HomeViewModel` is the reference
//  implementation for this phase and it has one, because it has content to
//  fetch: loading / loaded / empty / failed are real, mutually exclusive
//  things a brief can be. A form has none of that. Its content is the
//  draft, which exists from `init` and never loads; there is no empty
//  state (an empty form is the normal state) and a failure does not
//  replace the screen, it appears beside the button with the draft
//  untouched. What this file does copy from `HomeViewModel` is everything
//  that actually applies: `@MainActor @Observable public final class`,
//  `public private(set)` for anything the view must not write, `public
//  var` only for draft fields that need a `$` binding, a per-action
//  in-flight boolean guarded with `guard` + `defer`, and protocol-only
//  dependencies with defaulted optional collaborators.
//
//  PROGRESSIVE DISCLOSURE, AND WHY IT IS NOT SYMMETRIC. The ticket names
//  eight fields (name, brand, category, subcategory, primary colour, size,
//  fit, condition); spec §6.15 names eleven more that the item detail
//  screen must be able to edit. Putting nineteen fields in one flat column
//  turns "I bought a jumper" into a tax return, and the §10 wardrobe graph
//  can already say something useful from the first eight. So the eight are
//  always visible and the rest sit behind a "More details" disclosure —
//  collapsed when adding, and expanded when editing an item that already
//  HAS one of them. That asymmetry is deliberate: a value that is already
//  on the row and is hidden behind a closed section is a value the user
//  concludes the app lost, whereas a blank field behind a closed section
//  is just a field he has not needed yet.
//
//  TWO §6.15 FIELDS ARE ABSENT ON PURPOSE. "Care instructions" has no
//  property on `ClosetItem` and no column in `closet_items`; adding a
//  `CodingKeys` entry without a migration is exactly what
//  `scripts/check_column_drift.py` exists to fail, and it would fail
//  silently at runtime rather than loudly (see that script's header).
//  "Outfit count" is derived from `outfit_items`, which is Phase 4, and is
//  not an editable field in any case. Neither is invented here.
//
//  THE GUEST CAP IS NOT AN ERROR AND IS NOT A DISMISSAL. See
//  `capReachedDoesNotCloseTheForm` in this file's tests and the note on
//  `Failure` below.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class ClosetItemFormViewModel {

    // MARK: - Mode

    /// Which of the two jobs this instance is doing.
    ///
    /// `.editing` carries the WHOLE original row rather than just its id,
    /// because `submit()` rebuilds the updated item by mutating a copy of
    /// it (see `edited(from:category:)`). Carrying only the id would mean
    /// re-fetching, or — far more likely — constructing a fresh
    /// `ClosetItem` from the draft and quietly resetting every column the
    /// form does not show.
    public enum Mode: Equatable, Sendable {
        case adding
        case editing(ClosetItem)
    }

    /// The three things a submit can actually fail with, and the reason
    /// they are one type with two cases rather than a bare `AstraError`.
    ///
    /// `GuestClosetError.capReached` is a permanent fact about this
    /// session, not a transient failure with a retry — the eleventh guest
    /// item will be refused every time it is offered. `AstraError` is the
    /// opposite: a network drop is worth trying again. Rendering both as
    /// "something went wrong" would put a retry button in front of a
    /// condition retrying cannot clear, which is spec §22's dead-button
    /// bar failed by a different route. Same split, and the same reason,
    /// as `OnboardingViewModel.AddItemState.guestCapReached`.
    public enum Failure: Equatable, Sendable {
        case guestCapReached(limit: Int)
        case failed(AstraError)

        /// What to put on screen.
        ///
        /// The cap case re-derives its copy from `GuestClosetError` rather
        /// than restating it, so the sentence a guest reads here and the
        /// sentence he reads anywhere else cannot drift.
        /// `localizedDescription` and not `errorDescription` only because
        /// the latter is `String?` and the alternative would be a `??`
        /// fallback string that can never be reached — dead copy is still
        /// copy someone has to maintain.
        public var message: String {
            switch self {
            case .guestCapReached(let limit):
                GuestClosetError.capReached(limit: limit).localizedDescription
            case .failed(let error):
                // `AstraError.message` is already user-facing (see that
                // type's header); rendering it directly is correct.
                error.message
            }
        }

        /// Whether retrying could ever succeed. Drives whether the form
        /// keeps offering its submit button.
        public var isRecoverable: Bool {
            switch self {
            case .guestCapReached: false
            case .failed: true
            }
        }
    }

    // MARK: - Draft: the eight fields the ticket names

    public var name: String
    public var brand: String
    public var category: ClothingCategory?
    public var subcategory: String
    public var primaryColor: String
    public var size: String
    public var fit: ItemFit?
    public var condition: ItemCondition?

    // MARK: - Draft: the rest of spec §6.15, behind `showsMoreDetails`

    public var secondaryColors: [String]
    public var pattern: GarmentPattern?
    public var material: [String]
    public var seasonality: [Season]
    public var laundryState: LaundryState
    public var availabilityState: AvailabilityState
    public var purchaseDate: Date?
    public var pricePaid: Decimal?
    public var currency: String
    public var retailer: String
    /// The raw text, not a `URL`. A half-typed address is a legitimate
    /// thing to be in the middle of, and a `Binding<URL?>` would have to
    /// throw away every keystroke that does not yet parse.
    public var productURLText: String

    /// Whether the "More details" section is open. `public var` because
    /// the disclosure control binds to it directly.
    public var showsMoreDetails: Bool

    // MARK: - Submission

    public private(set) var isSubmitting = false
    public private(set) var failure: Failure?

    /// Called on the main actor after a successful create or update.
    ///
    /// The presenting surface owns dismissal: the Closet tab pops, the
    /// item detail sheet closes. This view model deliberately does not
    /// know which of those it is inside.
    public var onSaved: (@MainActor @Sendable (ClosetItem) -> Void)?

    // MARK: - Dependencies

    public let mode: Mode

    private let closetRepository: any ClosetRepository
    /// Only consulted when ADDING — an edit already knows whose row it is.
    ///
    /// A closure rather than a `SessionStore` because that is how the rest
    /// of the codebase passes this exact fact across an isolation boundary
    /// (`AppContainer` hands `GuestClosetRepository` a
    /// `currentGuestUserID` closure the same way), and because taking the
    /// store itself would drag a live Supabase client into every unit test
    /// of a form that never makes an auth call.
    private let currentUserID: (@Sendable () async -> UUID?)?
    private let analyticsClient: any AnalyticsClient
    private let logger = Logger(subsystem: "com.astrastyle.app", category: "closet")

    // MARK: - Init

    public init(
        mode: Mode,
        closetRepository: any ClosetRepository,
        currentUserID: (@Sendable () async -> UUID?)? = nil,
        analyticsClient: any AnalyticsClient = NoOpAnalyticsClient()
    ) {
        self.mode = mode
        self.closetRepository = closetRepository
        self.currentUserID = currentUserID
        self.analyticsClient = analyticsClient

        let item: ClosetItem? = switch mode {
        case .adding: nil
        case .editing(let existing): existing
        }

        name = item?.name ?? ""
        brand = item?.brand ?? ""
        category = item?.category
        subcategory = item?.subcategory ?? ""
        primaryColor = item?.primaryColor ?? ""
        size = item?.size ?? ""
        fit = item?.fit
        condition = item?.condition

        secondaryColors = item?.secondaryColors ?? []
        pattern = item?.pattern
        material = item?.material ?? []
        seasonality = item?.seasonality ?? []
        laundryState = item?.laundryState ?? .clean
        availabilityState = item?.availabilityState ?? .available
        purchaseDate = item?.purchaseDate
        pricePaid = item?.pricePaid
        // Falls back to the device's own currency rather than a hardcoded
        // "USD": the price a man types is in the money he spent. An
        // existing row keeps whatever it was bought in, so a jacket
        // recorded in SEK is never silently relabelled as sterling because
        // it was edited on a UK phone.
        currency = item?.currency ?? Locale.current.currency?.identifier ?? "USD"
        retailer = item?.retailer ?? ""
        productURLText = item?.productURL?.absoluteString ?? ""

        showsMoreDetails = item.map(Self.hasAnyDetailField) ?? false

        // Said at construction rather than only at the first failed
        // submit. `adding(closetRepository:)` compiles without a user-id
        // provider — it has to, the factory signature is a fixed contract
        // — and a call site that forgets one produces a form that looks
        // completely normal until the man taps the button. This is the
        // cheapest way for that wiring mistake to be visible on the first
        // run rather than on the first save.
        if case .adding = mode, currentUserID == nil {
            logger.warning("Closet form built for adding with no currentUserID provider; every submit will fail as .auth.")
        }
    }

    /// The add path. Presented by the Closet tab.
    public static func adding(
        closetRepository: ClosetRepository,
        currentUserID: (@Sendable () async -> UUID?)? = nil,
        analyticsClient: any AnalyticsClient = NoOpAnalyticsClient()
    ) -> ClosetItemFormViewModel {
        ClosetItemFormViewModel(
            mode: .adding,
            closetRepository: closetRepository,
            currentUserID: currentUserID,
            analyticsClient: analyticsClient
        )
    }

    /// The edit path. Presented as a sheet from item detail (spec §6.15).
    public static func editing(
        item: ClosetItem,
        closetRepository: ClosetRepository,
        analyticsClient: any AnalyticsClient = NoOpAnalyticsClient()
    ) -> ClosetItemFormViewModel {
        ClosetItemFormViewModel(
            mode: .editing(item),
            closetRepository: closetRepository,
            // Deliberately absent: an edit takes the owner from the row it
            // is editing, so there is nothing to look up and nothing that
            // could reassign a garment to whoever happens to be signed in.
            currentUserID: nil,
            analyticsClient: analyticsClient
        )
    }

    // MARK: - Submission

    /// Creates or updates one `closet_items` row.
    ///
    /// The in-flight guard is not decoration: `AstraButton` disables
    /// itself while `isLoading`, but a hardware keyboard return, a
    /// VoiceOver double-tap and a fast double-tap can all land a second
    /// call before the first `await` returns, and for `.adding` that would
    /// write the garment twice.
    public func submit() async {
        guard !isSubmitting, canSubmit, let category else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        failure = nil

        do {
            let saved: ClosetItem
            switch mode {
            case .adding:
                guard let userID = await resolveUserID() else {
                    failure = .failed(AstraError.auth(
                        String(localized: "You need to be signed in to save this.",
                               comment: "Shown when a garment can't be saved because there's no session")
                    ))
                    return
                }
                saved = try await closetRepository.createItem(newItem(userID: userID, category: category), images: [])
                analyticsClient.log(.closetItemAdded(category: category, source: .manualEntry))

            case .editing(let original):
                saved = try await closetRepository.updateItem(edited(from: original, category: category))
            }
            onSaved?(saved)

        } catch let error as GuestClosetError {
            // Typed, and caught before `AstraError`, so the cap is
            // recognised without matching on a message string — the reason
            // `GuestClosetError` is a separate type at all.
            switch error {
            case .capReached(let limit):
                failure = .guestCapReached(limit: limit)
            }
        } catch let error as AstraError {
            failure = .failed(error)
        } catch {
            // The raw description goes to the log, not to the screen: an
            // arbitrary `Error`'s `localizedDescription` is developer text
            // ("The operation couldn't be completed…"), and spec §22's bar
            // is a handled failure, not a legible-to-us one.
            logger.error("Closet item submit failed: \(error.localizedDescription, privacy: .public)")
            failure = .failed(AstraError(
                category: .unknown,
                message: String(localized: "That didn't save. Nothing you typed has been lost — try again.",
                                comment: "Generic closet form save failure")
            ))
        }
    }

    /// Clears a stale failure so the form stops reporting the last attempt
    /// while the user edits for the next one. The cap is exempt: it is
    /// still true after another keystroke.
    public func acknowledgeFailure() {
        guard let failure, failure.isRecoverable else { return }
        self.failure = nil
    }

    private func resolveUserID() async -> UUID? {
        guard let currentUserID else { return nil }
        return await currentUserID()
    }
}

// MARK: - Copy
//
// In an extension rather than the class body for the reason
// `OnboardingViewModel` gives for hoisting its state enums: these are
// declarations with no behaviour, and inlining them pushed the part of the
// class that actually does something past the point it could be read in one
// pass. Callers still spell them `model.title`.

public extension ClosetItemFormViewModel {

    var isEditing: Bool {
        if case .editing = mode { return true }
        return false
    }

    /// The screen's own title. Rendered in the form's content rather than
    /// as a `.navigationTitle`, because this view is pushed from the
    /// Closet tab in one place and presented as a sheet from item detail
    /// in another, and only one of those two has a navigation bar to put a
    /// title in.
    var title: String {
        isEditing
            ? String(localized: "Edit garment", comment: "Title of the closet item form when editing")
            : String(localized: "Add a garment", comment: "Title of the closet item form when adding")
    }

    /// One line under the title saying what this screen is for.
    var subtitle: String {
        isEditing
            ? String(localized: "Change anything here and it updates everywhere Kyra uses this piece.",
                     comment: "Subtitle of the closet item form when editing")
            : String(localized: "Type it in. Two fields is enough to start — the rest sharpens what Kyra suggests.",
                     comment: "Subtitle of the closet item form when adding")
    }

    /// The primary button's label. Deliberately different in each mode:
    /// "Save changes" on an add would be describing a change to something
    /// that does not exist yet.
    var submitTitle: String {
        isEditing
            ? String(localized: "Save changes", comment: "Primary button on the closet item form when editing")
            : String(localized: "Add garment", comment: "Primary button on the closet item form when adding")
    }

    /// The submit button's VoiceOver hint while it is ENABLED. When it is
    /// disabled the view substitutes `blockingReason`, so the reason is
    /// spoken as well as printed — a sighted user reading the line under
    /// the button and a VoiceOver user hearing the hint get the same
    /// sentence.
    var submitHint: String {
        isEditing
            ? String(localized: "Saves your changes to this piece.", comment: "Closet form submit hint when editing")
            : String(localized: "Saves this piece to your closet.", comment: "Closet form submit hint when adding")
    }
}

// MARK: - Validation

public extension ClosetItemFormViewModel {

    /// Whitespace is not a name. Without the trim, a spacebar tap creates
    /// a garment called " " that the man can neither find nor recognise —
    /// the same check `OnboardingViewModel.trimmedNewItemName` makes, for
    /// the same reason.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A field-level error for the product link, and the only one on this
    /// form.
    ///
    /// The ticket says name and category block submission and "all other
    /// fields are optional" — optional means it may be left EMPTY, not
    /// that a value the app cannot store should be accepted and then
    /// dropped on the floor. A `URL?` that fails to parse is not saved
    /// anywhere, so accepting it silently would be data the user believes
    /// he entered and will never see again.
    var productURLError: String? {
        let trimmed = productURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard Self.webURL(from: trimmed) == nil else { return nil }
        return String(localized: "That doesn't look like a web address. Paste the link from the shop, or leave it blank.",
                      comment: "Validation error on the product link field")
    }

    /// Why the submit button is off, or `nil` when it is on.
    ///
    /// The button is disabled rather than left tappable-and-failing —
    /// but a disabled control with no explanation is its own dead end, so
    /// every reason it can be off has a sentence here and the view renders
    /// whichever one applies next to the button.
    var blockingReason: String? {
        if case .guestCapReached(let limit) = failure {
            return Failure.guestCapReached(limit: limit).message
        }
        let needsName = trimmedName.isEmpty
        let needsCategory = category == nil
        if needsName && needsCategory {
            return String(localized: "Give it a name and pick a category to save it.",
                          comment: "Why the closet form can't be submitted: both required fields empty")
        }
        if needsName {
            return String(localized: "Give it a name — it's how you'll find it again.",
                          comment: "Why the closet form can't be submitted: no name")
        }
        if needsCategory {
            return String(localized: "Pick a category so Kyra knows what it is.",
                          comment: "Why the closet form can't be submitted: no category")
        }
        if productURLError != nil {
            return String(localized: "Fix the product link, or clear it.",
                          comment: "Why the closet form can't be submitted: bad product link")
        }
        return nil
    }

    var canSubmit: Bool {
        blockingReason == nil && !isSubmitting
    }

    /// Parses what a man actually pastes into a link field.
    ///
    /// `URL(string:)` alone is far too permissive — it happily returns a
    /// URL for "navy", which would then be written to `product_url` as a
    /// relative path nothing can open. Two rules make it honest: a
    /// scheme-less "zara.com/x" is upgraded to https rather than rejected
    /// (that is what a paste from a share sheet often looks like), and the
    /// host must contain a dot, which is what separates a hostname from a
    /// word someone typed by mistake.
    static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), host.contains(".") else { return nil }
        return url
    }
}

// MARK: - Multi-select editing
//
// These live on the view model rather than in the view for the same reason
// the network calls do: a chip row that does its own array bookkeeping is
// logic that cannot be unit-tested and gets re-derived slightly differently
// the next time somebody adds a chip row.

public extension ClosetItemFormViewModel {

    /// The materials offered as chips: a short list of what most of a
    /// wardrobe is actually made of, plus anything already on this item
    /// that is not in that list.
    ///
    /// The second half matters — an item whose material came back from the
    /// scanner as "ramie" must show "ramie" as a selected chip, not lose
    /// it because this build's suggestion list is shorter than the world.
    var materialOptions: [String] {
        let known = Set(Self.suggestedMaterials.map { $0.lowercased() })
        return Self.suggestedMaterials + material.filter { !known.contains($0.lowercased()) }
    }

    func toggleMaterial(_ value: String) {
        toggle(value, in: &material)
    }

    func toggleSeason(_ season: Season) {
        if let index = seasonality.firstIndex(of: season) {
            seasonality.remove(at: index)
        } else {
            seasonality.append(season)
        }
    }

    /// Adds a secondary colour word, ignoring blanks and repeats.
    ///
    /// Case-insensitive on the way in so "Navy" and "navy" cannot both sit
    /// in `secondary_colors`, but the user's own casing is what gets
    /// stored — `AstraGarmentColor` lowercases before it looks anything
    /// up, so casing costs nothing and re-typing a man's word back at him
    /// in a different case reads as the app correcting him.
    func addSecondaryColor(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !secondaryColors.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        secondaryColors.append(trimmed)
    }

    func removeSecondaryColor(_ value: String) {
        secondaryColors.removeAll { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    private func toggle(_ value: String, in list: inout [String]) {
        if let index = list.firstIndex(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            list.remove(at: index)
        } else {
            list.append(value)
        }
    }

    /// Stored verbatim, in the case shown on the chip.
    ///
    /// `closet_items.material` is a free-text array with no consumer that
    /// case-matches it, so there is nothing to normalise against — and
    /// `String(localized:)` would be wrong here in a way that is easy to
    /// miss: these are DATA written to a shared column, not interface
    /// copy, and a French build must not write "Laine" into a row a
    /// server-side scorer will later read as English.
    static let suggestedMaterials: [String] = [
        "Cotton", "Wool", "Merino wool", "Cashmere", "Linen", "Silk",
        "Denim", "Leather", "Suede", "Down", "Polyester", "Nylon"
    ]
}

// MARK: - Building the row

private extension ClosetItemFormViewModel {

    /// A brand-new row. Everything the form does not ask about is left at
    /// `ClosetItem`'s own defaults on purpose:
    ///
    /// * `wearCount` / `lastWornAt` — nobody has worn it yet on the day he
    ///   says he owns it.
    /// * `formalityScore` / `warmthScore` / `waterResistanceScore` /
    ///   `embedding` — server-derived signals (spec §9, §10). A number a
    ///   user guessed is worse than no number, because the graph cannot
    ///   tell the two apart.
    func newItem(userID: UUID, category: ClothingCategory) -> ClosetItem {
        ClosetItem(
            id: UUID(),
            userID: userID,
            name: trimmedName,
            brand: Self.nilIfBlank(brand),
            category: category,
            subcategory: Self.nilIfBlank(subcategory),
            primaryColor: Self.nilIfBlank(primaryColor),
            secondaryColors: cleanedSecondaryColors,
            pattern: pattern,
            material: cleanedMaterial,
            size: Self.nilIfBlank(size),
            fit: fit,
            condition: condition,
            seasonality: seasonality,
            purchaseDate: purchaseDate,
            pricePaid: pricePaid,
            currency: storedCurrency,
            retailer: Self.nilIfBlank(retailer),
            productURL: Self.webURL(from: productURLText),
            laundryState: laundryState,
            availabilityState: availabilityState
        )
    }

    /// An edit, built by MUTATING A COPY OF THE ORIGINAL rather than by
    /// constructing a fresh `ClosetItem` from the draft.
    ///
    /// This is the whole safety property of the edit path and it is
    /// structural, not a checklist: `id`, `userID`, `createdAt`,
    /// `wearCount`, `lastWornAt`, `archivedAt`, `embedding` and the three
    /// derived scores are preserved because nothing here assigns them, so
    /// a field added to `ClosetItem` next year is preserved too without
    /// anyone remembering to come back here. The alternative — building a
    /// new value and passing the ones we care about through — silently
    /// resets `wearCount` to 0 the day someone adds a property and forgets
    /// a line, and a wear history is not recoverable. `wearCountSurvivesAnEdit`
    /// in the tests pins it.
    func edited(from original: ClosetItem, category: ClothingCategory) -> ClosetItem {
        var item = original
        item.name = trimmedName
        item.brand = Self.nilIfBlank(brand)
        item.category = category
        item.subcategory = Self.nilIfBlank(subcategory)
        item.primaryColor = Self.nilIfBlank(primaryColor)
        item.secondaryColors = cleanedSecondaryColors
        item.pattern = pattern
        item.material = cleanedMaterial
        item.size = Self.nilIfBlank(size)
        item.fit = fit
        item.condition = condition
        item.seasonality = seasonality
        item.purchaseDate = purchaseDate
        item.pricePaid = pricePaid
        item.currency = storedCurrency
        item.retailer = Self.nilIfBlank(retailer)
        item.productURL = Self.webURL(from: productURLText)
        item.laundryState = laundryState
        item.availabilityState = availabilityState
        item.updatedAt = .now
        return item
    }

    /// A currency with no price attached is noise in the column — it says
    /// "he paid an unknown amount of pounds". The code only travels with a
    /// number.
    var storedCurrency: String? {
        pricePaid == nil ? nil : Self.nilIfBlank(currency)
    }

    var cleanedSecondaryColors: [String] {
        secondaryColors.compactMap(Self.nilIfBlank)
    }

    var cleanedMaterial: [String] {
        material.compactMap(Self.nilIfBlank)
    }

    static func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether an existing row has anything in the "More details" half, and
    /// therefore whether that section should start open (see this file's
    /// header).
    static func hasAnyDetailField(_ item: ClosetItem) -> Bool {
        !item.secondaryColors.isEmpty
            || item.pattern != nil
            || !item.material.isEmpty
            || !item.seasonality.isEmpty
            || item.purchaseDate != nil
            || item.pricePaid != nil
            || item.retailer != nil
            || item.productURL != nil
            || item.laundryState != .clean
            || item.availabilityState != .available
    }
}
