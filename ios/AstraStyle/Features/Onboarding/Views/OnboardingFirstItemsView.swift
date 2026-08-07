//
//  OnboardingFirstItemsView.swift
//  AstraStyle
//
//  §5.1 step 12 — "add first closet items, or skip".
//
//  THE STEP'S JOB IS TO BE EASY TO LEAVE. Phase 2's last unmet exit criterion
//  is "skipping 'add first closet items' does not block reaching Home", so
//  nothing on this screen is required, nothing here can disable the footer's
//  forward button, and every failure below resolves to a line of text beside
//  the form rather than to a state the user has to clear before he can move
//  on. The forward button's own label comes from `stepHasAnyAnswer`, so it
//  reads "Skip for now" until something has actually been added — which is the
//  honest description of what tapping it does.
//
//  THREE FIELDS, NOT THIRTY. `ClosetItem` has around thirty properties and
//  `P3-CLOSET-08` owns the screen that edits them. What the §10 wardrobe graph
//  needs before it can say anything at all is a category and a colour; a name
//  is what makes the row recognisable to the man who typed it. Everything else
//  — brand, material, formality, price, seasonality — refines a recommendation
//  that can already be made, and asking for it here would turn a sixty-second
//  step into a data-entry session one screen before the payoff.
//
//  NOT A CLOSET BROWSER. The list below shows what this step added, not what
//  the user owns. A signed-in user with an existing closet would otherwise
//  find twenty-five garments on an onboarding screen, and the step would read
//  as a management surface rather than a starting point.
//
//  THE PHOTO PATH IS THE FIRST THING ON THE SCREEN. This header used to say
//  "nothing here touches the scanner — a 'scan instead' affordance would be
//  the loudest control on the screen and the only one that cannot work". That
//  was true while the `closet` Edge Function was undeployed. It has shipped,
//  so the loudest control on the screen is now the one that works best: point
//  a camera at a garment and let the analysis fill in the fields, instead of
//  typing three of them from memory.
//
//  The typed form stays underneath, and it is not a no-camera fallback — the
//  scanner handles that itself by offering a Photos import. It stays because
//  the garment might not be in front of him: at the cleaners, in a suitcase,
//  on someone else's floor. Making the step conditional on where he is
//  standing would be worse than making him type.
//
//  THIS SCREEN DOES NOT PRESENT THE SHEET. `onScanTapped` goes up to
//  `OnboardingFlowView`, which owns the `AppContainer` the scanner's view
//  models are built from. A `View` that reached into the container to
//  construct a repository-backed view model would be a composition root in a
//  leaf, which is the thing CLAUDE.md's "no network calls in views" rule is
//  actually protecting against.
//

import SwiftUI

struct OnboardingFirstItemsView: View {
    let model: OnboardingViewModel

    /// Asks the flow to present the scanner. See the header: this screen
    /// cannot build the scanner's view models, so it asks for the sheet
    /// rather than opening one.
    let onScanTapped: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            scanCard
            typeInsteadDivider
            addForm

            if !model.firstItems.isEmpty {
                addedList
            }
        }
        .task { await model.prepareFirstItemsStep() }
    }

    // MARK: - The photo path

    /// The recommended way in, and the first thing on the screen.
    ///
    /// Says what happens after the shutter, not just what the button does.
    /// The scanner's own review screen is where corrections are made and the
    /// promise that they are POSSIBLE is what makes a man willing to let a
    /// machine guess — without it, "Astra reads it" sounds like a decision
    /// being taken away from him.
    private var scanCard: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "Photograph something you own",
                              comment: "First items scan section title"),
                eyebrow: String(localized: "FASTEST WAY", comment: "First items scan section eyebrow")
            )

            Text("Astra reads the piece from the photo — kind, colour, brand where it can — and shows you everything it worked out before anything is saved. You can correct any of it.")
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isNameFocused = false
                onScanTapped()
            } label: {
                HStack(spacing: AstraSpacing.xs) {
                    Image(systemName: "camera.viewfinder")
                        .astraIcon(.inline)
                        .accessibilityHidden(true)
                    Text("Take a photo")
                }
            }
            .buttonStyle(.astraPrimary)
            .accessibilityIdentifier("onboarding.firstItems.scan")
            .accessibilityHint(
                Text("Opens the camera. You'll see what Astra worked out and can change it before saving.",
                     comment: "Scan button hint")
            )
        }
    }

    /// Marks the typed form as the second option without calling it a lesser
    /// one. "Or" alone would read as two equal choices; naming the case the
    /// form is for is what stops a man photographing a shirt he does not have
    /// with him.
    private var typeInsteadDivider: some View {
        HStack(spacing: AstraSpacing.sm) {
            Rectangle()
                .fill(AstraColor.divider)
                .frame(height: 1)
            Text("Or if it isn't to hand")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(AstraColor.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The form

    private var addForm: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Describe it instead", comment: "First items typed form title"),
                eyebrow: String(localized: "THREE FIELDS", comment: "First items typed form eyebrow")
            )

            LabelledField(
                title: String(localized: "What is it?", comment: "First item name field"),
                hint: String(localized: "However you'd describe it to someone — \"navy merino crewneck\".",
                             comment: "First item name hint"),
                placeholder: String(localized: "Navy merino crewneck", comment: "First item name placeholder"),
                text: Binding(
                    get: { model.newItemName },
                    set: { model.newItemName = $0; model.acknowledgeAddItemState() }
                ),
                identifier: "onboarding.firstItems.name"
            )
            .focused($isNameFocused)

            categoryPicker

            LabelledField(
                title: String(localized: "Main colour", comment: "First item colour field"),
                hint: String(localized: "Optional. Kyra uses it to judge what goes with what.",
                             comment: "First item colour hint"),
                placeholder: String(localized: "Navy", comment: "First item colour placeholder"),
                text: Binding(
                    get: { model.newItemColor },
                    set: { model.newItemColor = $0; model.acknowledgeAddItemState() }
                ),
                identifier: "onboarding.firstItems.color"
            )

            statusLine

            AstraButton(
                title: String(localized: "Add to closet", comment: "Save the first closet item"),
                isLoading: model.addItemState == .saving
            ) {
                isNameFocused = false
                Task { await model.addFirstItem() }
            }
            .disabled(!model.canAddItem)
            .accessibilityIdentifier("onboarding.firstItems.add")
            .accessibilityHint(
                Text(model.canAddItem
                     ? "Saves this piece to your closet."
                     : "Add a description and pick a category first.",
                     comment: "Add-item button hint")
            )
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text("Which kind?")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)

            // Wrapping, never a horizontal scroller — the same reasoning as
            // §6.7's chip rows: a sideways scroller hides its last option
            // behind a gesture nobody knows is available, and it is the
            // gesture least likely to be found at an accessibility text size.
            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(ClothingCategory.allCases, id: \.self) { category in
                    AstraChip(
                        category.displayName,
                        isSelected: model.newItemCategory == category
                    ) {
                        model.newItemCategory = model.newItemCategory == category ? nil : category
                        model.acknowledgeAddItemState()
                        AstraHaptics.selection()
                    }
                    .accessibilityIdentifier("onboarding.firstItems.category.\(category.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Which kind?", comment: "Category picker accessibility label"))
    }

    /// One place for all four post-add outcomes, so they cannot stack up and
    /// so none of them can render as an empty box.
    @ViewBuilder
    private var statusLine: some View {
        switch model.addItemState {
        case .idle, .saving:
            EmptyView()

        case .added(let name):
            HStack(alignment: .top, spacing: AstraSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .astraIcon(.inline)
                    .accessibilityHidden(true)
                Text(String(format: String(localized: "%@ is in your closet.",
                                           comment: "Confirmation after adding an item; %@ is its name"), name))
                    .astraText(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(AstraColor.successOlive)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboarding.firstItems.added")

        case .capReached(let limit):
            noticeCard(
                headline: String(localized: "That's the free-plan limit.", comment: "Closet cap headline"),
                detail: String(
                    format: String(localized: "The free plan keeps %d pieces. You can carry on — the rest of onboarding doesn't need any more than this.",
                                   comment: "Closet cap detail; %d is the limit"),
                    limit
                ),
                identifier: "onboarding.firstItems.capNotice"
            )

        case .failed(let message):
            VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                noticeCard(
                    headline: String(localized: "That didn't save.", comment: "Add-item failure headline"),
                    detail: message,
                    identifier: "onboarding.firstItems.error"
                )
                Text("Nothing you typed has been lost, and you can carry on without adding anything.")
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func noticeCard(headline: String, detail: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            // Named in words as well as tinted — spec §19: a colour on its own
            // is not a message.
            Text(headline)
                .astraText(.headline)
                .foregroundStyle(AstraColor.warningAmber)

            Text(detail)
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .fill(AstraColor.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                .strokeBorder(AstraColor.warningAmber, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - What was added

    private var addedList: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "In your closet", comment: "Added items section title"),
                eyebrow: String(
                    format: String(localized: "%d SO FAR", comment: "Added items count eyebrow; %d is a count"),
                    model.firstItems.count
                )
            )

            ForEach(model.firstItems) { item in
                AddedItemRow(item: item) {
                    Task {
                        await model.removeFirstItem(item)
                        AstraHaptics.warning()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.firstItems.list")
    }
}

// MARK: - Components

/// A titled text field with its own explanation underneath.
///
/// The hint is a line of text rather than a placeholder, because a placeholder
/// disappears the moment the user types — taking the explanation with it at
/// exactly the point he might need it.
private struct LabelledField: View {
    let title: String
    let hint: String
    let placeholder: String
    @Binding var text: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(placeholder, text: $text)
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .padding(AstraSpacing.sm)
                .frame(minHeight: AstraSize.minTapTarget)
                .background(
                    RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                        .fill(AstraColor.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                        .strokeBorder(AstraColor.divider, lineWidth: 1)
                )
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text(hint))
                .accessibilityIdentifier(identifier)

            Text(hint)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AddedItemRow: View {
    let item: ClosetItem
    let remove: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Stacks at accessibility sizes rather than squeezing a two-line label
        // and a Remove button onto one row, where the name truncates to a word
        // and a half.
        let stackVertically = typeSize >= .accessibility1

        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            if stackVertically {
                details
                removeButton
            } else {
                HStack(alignment: .top, spacing: AstraSpacing.sm) {
                    details
                    Spacer(minLength: AstraSpacing.xs)
                    removeButton
                }
            }
        }
        .padding(AstraSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                .fill(AstraColor.backgroundSecondary)
        )
        .accessibilityElement(children: .contain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            Text(item.name)
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.name), \(subtitle)"))
    }

    private var removeButton: some View {
        Button(String(localized: "Remove", comment: "Remove an item added during onboarding"), action: remove)
            .buttonStyle(.astraTertiary)
            .accessibilityLabel(Text(String(
                format: String(localized: "Remove %@", comment: "Remove a named item; %@ is its name"),
                item.name
            )))
            .accessibilityIdentifier("onboarding.firstItems.remove.\(item.id.uuidString.lowercased())")
    }

    private var subtitle: String {
        guard let color = item.primaryColor, !color.isEmpty else { return item.category.displayName }
        return "\(item.category.displayName) · \(color)"
    }
}

#Preview("First items") {
    ScrollView {
        OnboardingFirstItemsView(
            model: OnboardingViewModel(
                store: InMemoryOnboardingDraftStore(),
                profileRepository: MockProfileRepository(),
                closetRepository: MockClosetRepository(items: []),
                referenceStore: InMemoryReferenceImageStore(),
                sessionStore: SessionStore(
                    apiClient: .previewClient,
                    supabase: AstraSupabaseClientFactory.previewClient
                )
            ),
            onScanTapped: {}
        )
        .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
}
