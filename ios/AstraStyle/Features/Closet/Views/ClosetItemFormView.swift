//
//  ClosetItemFormView.swift
//  AstraStyle
//
//  The manual add/edit form for one garment (ticket P3-CLOSET-08, spec
//  §6.15's editable fields). Presented pushed from the Closet tab for
//  "add", and as a sheet from item detail for "edit" — see
//  `ClosetItemFormViewModel` for why one screen serves both, why the
//  second half of the fields is behind a disclosure, and why two fields
//  spec §6.15 lists are deliberately absent.
//
//  NO CAMERA, ANYWHERE ON THIS SCREEN. The ticket's first acceptance
//  criterion is that a garment can be added end to end without the camera
//  ever opening, and spec §7's permission rule says the camera is asked
//  for by the thing that IS the camera. There is no "scan instead" button
//  here — it would be the loudest control on the screen and it belongs to
//  a scanner that does not exist yet.
//
//  THE SUBMIT BUTTON IS DISABLED, AND SAYS WHY. `viewModel.blockingReason`
//  renders directly under it. A greyed-out button with no explanation is
//  the same dead end as a button that fails silently — the man can see
//  that he cannot continue and not what to do about it — and spec §22's
//  "no dead buttons" bar is about exactly that class of control.
//
//  DECOMPOSITION. Nineteen fields cannot be one `body`. The screen is
//  split by MEANING, not by line count: `essentials` is the eight fields
//  the ticket names, `moreDetails` is the rest of §6.15, and the four
//  primitives at the bottom of the file exist so that the thing which is
//  easy to forget nine times over — the VoiceOver GROUP label on a chip
//  cloud, without which a screen reader announces seven loose buttons and
//  nothing saying what they are choosing between — is written once.
//

import SwiftUI

public struct ClosetItemFormView: View {

    /// Keyboard focus order. Only the text fields are here: chips, the
    /// date picker and the price field are not part of a return-key chain
    /// (there is nothing sensible for `next` to mean on a chip cloud), so
    /// putting them in this enum would create focus targets the return key
    /// jumps to and then cannot leave.
    fileprivate enum Field: Hashable {
        case name, brand, subcategory, primaryColor, size
        case secondaryColor, material, retailer, productURL
    }

    @State private var viewModel: ClosetItemFormViewModel
    @FocusState private var focused: Field?

    /// Transient input buffers for the two "add one to the list" fields.
    /// View state rather than draft state on purpose: a half-typed
    /// "burgu…" is not part of the garment, and putting it on the view
    /// model would let a submit pick it up as a real value.
    @State private var secondaryColorDraft = ""
    @State private var materialDraft = ""

    public init(viewModel: ClosetItemFormViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.xl) {
                header
                essentials
                moreDetails
                submitSection
            }
            .padding(.horizontal, AstraSpacing.pagePadding)
            .padding(.vertical, AstraSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AstraColor.backgroundPrimary)
        // A nineteen-field form is taller than the keyboard leaves room
        // for, and a keyboard that can only be dismissed by finding the one
        // empty spot to tap is a keyboard that stays up.
        .scrollDismissesKeyboard(.interactively)
        // Putting a field into edit is the man saying he is composing the
        // next attempt, which makes the last one's message stale. The
        // cap is exempt inside `acknowledgeFailure()` — it stays true
        // however much he retypes.
        .onChange(of: focused) { _, _ in viewModel.acknowledgeFailure() }
    }

    /// The title lives in the content, not in a navigation bar: this view
    /// is pushed in one place and presented as a sheet in another, and
    /// `.navigationTitle` renders in the first and silently vanishes in the
    /// second. `viewModel.title` is public so a presenting surface that DOES
    /// have a bar can set one too.
    private var header: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(viewModel.title)
                .astraText(.title1)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(viewModel.subtitle)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("closet.form.header")
    }

    private var submitSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            if let failure = viewModel.failure {
                ClosetFormNotice(failure: failure)
            }
            // Shown alongside a recoverable failure, but not alongside the
            // free-tier cap — `blockingReason` IS the cap's message there, and
            // the notice above has already said it once.
            if let reason = viewModel.blockingReason, viewModel.failure?.isRecoverable != false {
                Text(reason)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("closet.form.blockingReason")
            }
            AstraButton(title: viewModel.submitTitle, isLoading: viewModel.isSubmitting) {
                focused = nil
                Task { await viewModel.submit() }
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("closet.form.submit")
            .accessibilityHint(Text(viewModel.blockingReason ?? viewModel.submitHint))
        }
    }

    fileprivate func focus(_ field: Field?) { focused = field }
}

// MARK: - The eight fields the ticket names

private extension ClosetItemFormView {

    var essentials: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "The piece", comment: "Closet form section title"),
                eyebrow: String(localized: "A NAME AND A CATEGORY IS ALL IT NEEDS", comment: "Closet form section eyebrow")
            )

            AstraTextField(
                String(localized: "Name", comment: "Closet form field label"),
                text: $viewModel.name,
                placeholder: String(localized: "Navy merino crewneck", comment: "Closet form name placeholder"),
                footnote: String(localized: "However you'd describe it to someone.", comment: "Closet form name footnote"),
                isRequired: true,
                submitLabel: .next
            )
            .focused($focused, equals: .name)
            .onSubmit { focus(.brand) }
            .accessibilityIdentifier("closet.form.name")

            ClosetSingleChoiceChips(
                label: String(localized: "Category", comment: "Closet form field label"),
                isRequired: true,
                identifierPrefix: "category",
                selection: viewModel.category,
                title: { $0.displayName },
                select: { viewModel.category = $0 }
            )

            AstraTextField(
                String(localized: "Brand", comment: "Closet form field label"),
                text: $viewModel.brand,
                placeholder: String(localized: "Uniqlo", comment: "Closet form brand placeholder"),
                submitLabel: .next,
                autocapitalization: .words
            )
            .focused($focused, equals: .brand)
            .onSubmit { focus(.subcategory) }
            .accessibilityIdentifier("closet.form.brand")

            AstraTextField(
                String(localized: "Type", comment: "Closet form field label for subcategory"),
                text: $viewModel.subcategory,
                placeholder: String(localized: "Crewneck", comment: "Closet form subcategory placeholder"),
                footnote: String(localized: "The narrower word for it — chinos, derbies, field jacket.", comment: "Closet form subcategory footnote"),
                submitLabel: .next
            )
            .focused($focused, equals: .subcategory)
            .onSubmit { focus(.primaryColor) }
            .accessibilityIdentifier("closet.form.subcategory")

            primaryColorField

            AstraTextField(
                String(localized: "Size", comment: "Closet form field label"),
                text: $viewModel.size,
                placeholder: String(localized: "M", comment: "Closet form size placeholder"),
                // Names what is printed on the label. Not a judgement about
                // the man wearing it — docs/14 §4: the garment is the subject.
                footnote: String(localized: "Whatever's printed on the label — M, 32R, 10½.", comment: "Closet form size footnote"),
                submitLabel: .done,
                autocapitalization: .characters
            )
            .focused($focused, equals: .size)
            .onSubmit { focus(nil) }
            .accessibilityIdentifier("closet.form.size")

            ClosetSingleChoiceChips(
                label: String(localized: "Fit", comment: "Closet form field label"),
                // Describes the cut of the garment. Never the wearer.
                footnote: String(localized: "How it's cut, not how it should be worn.", comment: "Closet form fit footnote"),
                identifierPrefix: "fit",
                selection: viewModel.fit,
                title: { $0.displayName },
                select: { viewModel.fit = $0 }
            )

            ClosetSingleChoiceChips(
                label: String(localized: "Condition", comment: "Closet form field label"),
                footnote: String(localized: "Kyra stops recommending a piece that's worn out.", comment: "Closet form condition footnote"),
                identifierPrefix: "condition",
                selection: viewModel.condition,
                title: { $0.displayName },
                select: { viewModel.condition = $0 }
            )
        }
    }

    var primaryColorField: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            AstraTextField(
                String(localized: "Main colour", comment: "Closet form field label"),
                text: $viewModel.primaryColor,
                placeholder: String(localized: "Navy", comment: "Closet form colour placeholder"),
                footnote: String(localized: "Tap one below, or write your own.", comment: "Closet form colour footnote"),
                submitLabel: .next,
                autocapitalization: .never
            )
            .focused($focused, equals: .primaryColor)
            .onSubmit { focus(.size) }
            .accessibilityIdentifier("closet.form.primaryColor")

            ClosetColorReading(name: viewModel.primaryColor)

            ClosetColorSuggestions(
                query: viewModel.primaryColor,
                isSelected: { $0.caseInsensitiveCompare(viewModel.primaryColor) == .orderedSame },
                select: { viewModel.primaryColor = $0 },
                groupLabel: String(localized: "Suggested colours", comment: "VoiceOver label for the colour chip group")
            )
        }
    }
}

// MARK: - The rest of spec §6.15

private extension ClosetItemFormView {

    var moreDetails: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            disclosureButton
            if viewModel.showsMoreDetails {
                ClosetSingleChoiceChips(
                    label: String(localized: "Pattern", comment: "Closet form field label"),
                    identifierPrefix: "pattern",
                    selection: viewModel.pattern,
                    title: { $0.displayName },
                    select: { viewModel.pattern = $0 }
                )
                materialField
                secondaryColorField
                ClosetMultiChoiceChips(
                    label: String(localized: "Seasons", comment: "Closet form field label"),
                    footnote: String(localized: "Leave it blank if it goes out all year.", comment: "Closet form seasons footnote"),
                    options: Season.allCases,
                    isSelected: { viewModel.seasonality.contains($0) },
                    title: { $0.displayName },
                    identifier: { "closet.form.season.\($0.rawValue)" },
                    toggle: { viewModel.toggleSeason($0) }
                )
                purchaseBlock
                statusChips
            }
        }
        .astraAnimation(AstraMotion.standard, value: viewModel.showsMoreDetails)
    }

    /// A button with a rotating chevron rather than SwiftUI's
    /// `DisclosureGroup`, which draws its own label row and its own
    /// typography and would be the one section header on this screen that
    /// does not look like `AstraSectionHeader`.
    var disclosureButton: some View {
        Button {
            viewModel.showsMoreDetails.toggle()
            AstraHaptics.selection()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: AstraSpacing.sm) {
                VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                    Text("MORE DETAILS")
                        .astraText(.micro)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                    Text(String(localized: "Material, seasons, what it cost", comment: "Closet form disclosure subtitle"))
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: AstraSpacing.sm)
                Image(systemName: "chevron.down")
                    .astraIcon(.inline)
                    .foregroundStyle(AstraColor.accentChampagne)
                    .rotationEffect(.degrees(viewModel.showsMoreDetails ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "More details", comment: "Closet form disclosure label")))
        .accessibilityValue(Text(viewModel.showsMoreDetails
                                 ? String(localized: "Showing", comment: "Disclosure is open")
                                 : String(localized: "Hidden", comment: "Disclosure is closed")))
        .accessibilityHint(Text(String(localized: "Shows material, pattern, seasons, price and where it came from.", comment: "Closet form disclosure hint")))
        .accessibilityIdentifier("closet.form.moreDetails")
    }

    /// Laundry and availability. Both live behind the disclosure because
    /// neither is a fact about a garment on the day it is added — a piece
    /// you have just bought is clean and available, which is what
    /// `ClosetItem`'s own defaults already say. They are here at all because
    /// spec §6.15 requires laundry state to be editable, and this form is
    /// the edit surface.
    ///
    /// `allowsDeselection: false` on both: every garment is in exactly one
    /// of these states, so a chip that cleared the selection would be
    /// offering a value the column cannot hold.
    var statusChips: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            // The generic argument is spelled out on these two because
            // their `selection` is a NON-optional column, so there is no
            // `Value?` for the compiler to read `Value` straight off.
            ClosetSingleChoiceChips<LaundryState>(
                label: String(localized: "Laundry", comment: "Closet form field label"),
                identifierPrefix: "laundry",
                selection: viewModel.laundryState,
                title: { $0.displayName },
                allowsDeselection: false,
                select: { if let state = $0 { viewModel.laundryState = state } }
            )
            ClosetSingleChoiceChips<AvailabilityState>(
                label: String(localized: "Where it is", comment: "Closet form field label for availability"),
                footnote: String(localized: "Kyra leaves out anything that isn't to hand.", comment: "Closet form availability footnote"),
                identifierPrefix: "availability",
                selection: viewModel.availabilityState,
                title: { $0.displayName },
                allowsDeselection: false,
                select: { if let state = $0 { viewModel.availabilityState = state } }
            )
        }
    }
}

// MARK: - Material, other colours, purchase

private extension ClosetItemFormView {

    var materialField: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            ClosetMultiChoiceChips(
                label: String(localized: "Material", comment: "Closet form field label"),
                footnote: String(localized: "Pick as many as apply — a coat can be wool and nylon.", comment: "Closet form material footnote"),
                options: viewModel.materialOptions,
                isSelected: { viewModel.material.contains($0) },
                title: { $0 },
                identifier: { "closet.form.material.\($0.lowercased())" },
                toggle: { viewModel.toggleMaterial($0) }
            )
            ClosetAddToListField(
                label: String(localized: "Something else", comment: "Closet form add-material field label"),
                placeholder: String(localized: "Ramie", comment: "Closet form add-material placeholder"),
                text: $materialDraft,
                focus: $focused,
                focusValue: .material,
                identifier: "closet.form.materialEntry",
                add: { viewModel.toggleMaterial($0); materialDraft = "" }
            )
        }
    }

    var secondaryColorField: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(String(localized: "Other colours", comment: "Closet form field label"))
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            ClosetColorTokenList(colors: viewModel.secondaryColors) { viewModel.removeSecondaryColor($0) }
            ClosetAddToListField(
                label: String(localized: "Add a colour", comment: "Closet form add-colour field label"),
                placeholder: String(localized: "Cream", comment: "Closet form add-colour placeholder"),
                text: $secondaryColorDraft,
                focus: $focused,
                focusValue: .secondaryColor,
                identifier: "closet.form.secondaryColorEntry",
                add: { viewModel.addSecondaryColor($0); secondaryColorDraft = "" }
            )
            ClosetColorSuggestions(
                query: secondaryColorDraft,
                isSelected: { word in viewModel.secondaryColors.contains { $0.caseInsensitiveCompare(word) == .orderedSame } },
                select: { viewModel.addSecondaryColor($0) },
                groupLabel: String(localized: "Suggested other colours", comment: "VoiceOver label for the other-colours chip group")
            )
        }
    }

    var purchaseBlock: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            purchaseDateField
            AstraDecimalField(
                String(localized: "Price paid", comment: "Closet form field label"),
                value: $viewModel.pricePaid,
                placeholder: String(localized: "0", comment: "Closet form price placeholder"),
                footnote: String(localized: "Kyra divides it by how often you wear it. Leave it blank if you'd rather not.", comment: "Closet form price footnote"),
                currencyCode: viewModel.currency
            )
            .accessibilityIdentifier("closet.form.pricePaid")

            AstraTextField(
                String(localized: "Where it came from", comment: "Closet form field label for retailer"),
                text: $viewModel.retailer,
                placeholder: String(localized: "Uniqlo, Regent Street", comment: "Closet form retailer placeholder"),
                submitLabel: .next,
                autocapitalization: .words
            )
            .focused($focused, equals: .retailer)
            .onSubmit { focus(.productURL) }
            .accessibilityIdentifier("closet.form.retailer")

            AstraTextField(
                String(localized: "Product link", comment: "Closet form field label"),
                text: $viewModel.productURLText,
                placeholder: String(localized: "shop.example.com/item", comment: "Closet form product link placeholder"),
                footnote: String(localized: "Makes it easy to buy the same one again.", comment: "Closet form product link footnote"),
                errorText: viewModel.productURLError,
                keyboardType: .URL,
                textContentType: .URL,
                submitLabel: .done,
                autocapitalization: .never
            )
            .focused($focused, equals: .productURL)
            .onSubmit { focus(nil) }
            .accessibilityIdentifier("closet.form.productURL")
        }
    }

    /// An optional date needs a way to say "there isn't one", and a
    /// `DatePicker` cannot: it always shows a date, so a form that showed
    /// one unconditionally would be asserting that every garment was bought
    /// today.
    @ViewBuilder
    var purchaseDateField: some View {
        let label = String(localized: "Bought on", comment: "Closet form field label for purchase date")
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(label)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            if let purchased = viewModel.purchaseDate {
                // Nothing was bought in the future; an open-ended picker only
                // ever produces a typo.
                DatePicker(
                    label,
                    selection: Binding(get: { purchased }, set: { viewModel.purchaseDate = $0 }),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(AstraColor.accentChampagne)
                .frame(minHeight: AstraSize.minTapTarget, alignment: .leading)
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier("closet.form.purchaseDate")

                Button(String(localized: "Clear the date", comment: "Closet form clears the purchase date")) {
                    viewModel.purchaseDate = nil
                }
                .buttonStyle(.astraTertiary)
                .accessibilityIdentifier("closet.form.clearPurchaseDate")
            } else {
                Button(String(localized: "Add a date", comment: "Closet form adds a purchase date")) {
                    viewModel.purchaseDate = .now
                }
                .buttonStyle(.astraSecondary)
                .accessibilityHint(Text(String(localized: "Records when you bought it, for cost per wear.", comment: "Closet form purchase date hint")))
                .accessibilityIdentifier("closet.form.addPurchaseDate")
            }
        }
    }
}

// MARK: - Primitives

/// A labelled group with a caption, an optional required marker and an
/// optional footnote — the same shape `AstraTextField` renders, so a chip
/// row and a text field read as the same kind of thing on the page.
private struct ClosetFieldGroup<Content: View>: View {
    let label: String
    var footnote: String?
    var isRequired = false
    @ViewBuilder let content: () -> Content

    /// A word, not an asterisk — the same reasoning `AstraTextField` gives,
    /// and the two must agree or the form marks one idea two ways.
    private var requiredWord: String {
        String(localized: "Required", comment: "Marks a form field the user must fill in")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            HStack(spacing: AstraSpacing.xxs) {
                Text(label).astraText(.caption).foregroundStyle(AstraColor.textSecondary)
                if isRequired {
                    Text(requiredWord).astraText(.micro).foregroundStyle(AstraColor.textMuted)
                }
            }
            .accessibilityHidden(true)
            content()
            if let footnote {
                Text(footnote)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(isRequired ? "\(label), \(requiredWord)" : label))
        .accessibilityHint(Text(footnote ?? ""))
    }
}

/// A chip cloud where at most one option is chosen.
///
/// Takes no `options` array: every caller binds a closed Postgres enum, so
/// `allCases` in declaration order IS the list, and the raw value is a
/// stable accessibility identifier that does not move when a display name
/// is reworded.
///
/// `allowsDeselection` exists because two of the six callers bind a
/// NON-optional column (`laundry_state`, `availability_state`).
private struct ClosetSingleChoiceChips<Value>: View
where Value: CaseIterable & Hashable & RawRepresentable, Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    let label: String
    var footnote: String?
    var isRequired = false
    let identifierPrefix: String
    let selection: Value?
    let title: (Value) -> String
    var allowsDeselection = true
    let select: (Value?) -> Void

    var body: some View {
        ClosetFieldGroup(label: label, footnote: footnote, isRequired: isRequired) {
            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(Value.allCases, id: \.self) { option in
                    let isSelected = option == selection
                    AstraChip(title(option), isSelected: isSelected) {
                        if isSelected {
                            if allowsDeselection { select(nil) }
                        } else {
                            select(option)
                        }
                        AstraHaptics.selection()
                    }
                    .accessibilityIdentifier("closet.form.\(identifierPrefix).\(option.rawValue)")
                }
            }
        }
    }
}

/// A chip cloud where any number of options can be chosen. Takes an
/// explicit `options` array because one caller (`material`) is a list of
/// free-text strings rather than an enum.
private struct ClosetMultiChoiceChips<Value: Hashable>: View {
    let label: String
    var footnote: String?
    let options: [Value]
    let isSelected: (Value) -> Bool
    let title: (Value) -> String
    let identifier: (Value) -> String
    let toggle: (Value) -> Void

    var body: some View {
        ClosetFieldGroup(label: label, footnote: footnote) {
            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(options, id: \.self) { option in
                    AstraChip(title(option), isSelected: isSelected(option)) {
                        toggle(option)
                        AstraHaptics.selection()
                    }
                    .accessibilityIdentifier(identifier(option))
                }
            }
        }
    }
}

/// A text field whose value goes into a list rather than into a column.
///
/// The Add button and the return key do the same thing, and Add is disabled
/// while there is nothing to add — an Add that fired on an empty field
/// would append a blank chip, which is a control that appears to work and
/// produces nothing.
private struct ClosetAddToListField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    /// Applied to the inner `AstraTextField` rather than letting the caller
    /// wrap this whole composite in `.focused`: there is a button in here as
    /// well as a field, and a focus modifier on the container would be aimed
    /// at "whatever in here is focusable".
    let focus: FocusState<ClosetItemFormView.Field?>.Binding
    let focusValue: ClosetItemFormView.Field
    let identifier: String
    let add: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: AstraSpacing.xs) {
            AstraTextField(label, text: $text, placeholder: placeholder, submitLabel: .done, autocapitalization: .never)
                .focused(focus, equals: focusValue)
                .onSubmit(submit)
                .accessibilityIdentifier(identifier)
            Button(String(localized: "Add", comment: "Adds the typed value to a list on the closet form"), action: submit)
                .buttonStyle(.astraSecondary)
                .frame(maxWidth: AstraSize.minTapTarget * 2)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("\(identifier).add")
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        add(trimmed)
        AstraHaptics.success()
    }
}

/// The post-submit message.
///
/// Two treatments, because the two failures differ in kind: the free-tier
/// cap is amber and permanent (nothing about it is retryable, and it ends with
/// what to do instead), an `AstraError` is destructive and transient (the
/// button is still live behind it). Both name the state in WORDS as well as
/// in colour — spec §19: a colour on its own is not a message.
private struct ClosetFormNotice: View {
    let failure: ClosetItemFormViewModel.Failure

    var body: some View {
        let tint = failure.isRecoverable ? AstraColor.destructive : AstraColor.warningAmber
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(headline)
                .astraText(.headline)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Text(failure.message)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous).fill(AstraColor.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous).strokeBorder(tint, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("closet.form.notice")
    }

    private var headline: String {
        switch failure {
        case .freeTierCapReached:
            String(localized: "That's the free-plan limit.", comment: "Closet form free-tier cap headline")
        case .failed:
            String(localized: "That didn't save.", comment: "Closet form failure headline")
        }
    }
}

// MARK: - Previews

#Preview("Add") {
    ClosetItemFormView(viewModel: .adding(closetRepository: MockClosetRepository(items: []), currentUserID: { UUID() }))
}

#Preview("Edit") {
    ClosetItemFormView(viewModel: .editing(
        item: ClosetItem(
            id: UUID(), userID: UUID(), name: "Navy merino crewneck", brand: "Uniqlo", category: .top,
            subcategory: "Crewneck", primaryColor: "navy", secondaryColors: ["cream"], pattern: .solid,
            material: ["Merino wool"], size: "M", fit: .regular, condition: .good, seasonality: [.fall, .winter],
            pricePaid: 49.90, currency: "GBP", retailer: "Uniqlo", wearCount: 14
        ),
        closetRepository: MockClosetRepository(items: [])
    ))
}
