//
//  OnboardingLifestyleView.swift
//  AstraStyle
//
//  Spec §6.8 — Lifestyle. Eleven fields, which makes this the longest step in
//  the flow and the one most at risk of being abandoned halfway.
//
//  Two structural decisions follow from that:
//
//  1. THE THREE FIELDS THAT CHANGE RECOMMENDATIONS COME FIRST — dress code,
//     occasions, laundry cadence. Everything else is genuinely secondary and
//     sits below a divider that says so. A user who quits after the first
//     screenful has still given Kyra the answers that matter, and a user who
//     reads the whole thing knows the rest is optional detail rather than more
//     of the same.
//
//  2. BUDGET IS ASKED WITH ITS CURRENCY, ALWAYS. `LifestyleProfile.currency` is
//     NOT NULL for this reason: `CostPerWearCalculator` divides money by wears
//     and shows the result. A budget of 250 without a currency is not a display
//     bug, it is wrong advice — and it is wrong in the direction of
//     recommending things a user cannot afford.
//
//  Climate location permission (§6.8's fifth bullet) is deliberately NOT asked
//  here. A location prompt in the middle of onboarding, before the Daily Brief
//  that uses weather exists, is a permission request with no visible payoff —
//  the reliable way to get it denied permanently. It belongs on first use of
//  §6.11, where the reason is on screen.
//

import SwiftUI

struct OnboardingLifestyleView: View {
    @Binding var draft: OnboardingDraft

    @FocusState private var focusedField: String?

    /// What the user typed, kept separately from `draft.monthlyBudget`.
    ///
    /// The draft always holds a MONTHLY figure. Rendering the field straight
    /// from it would rewrite "3000" into "250" the moment the period switched to
    /// yearly, which looks like the app editing his answer.
    @State private var enteredBudget: String = ""
    @State private var budgetPeriod: BudgetPeriod = .monthly

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            whatYouDressForSection
            secondarySection
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "Done", comment: "Dismiss the keyboard")) {
                    focusedField = nil
                }
                .accessibilityIdentifier("onboarding.keyboardDone")
            }
        }
    }

    // MARK: - The part that changes recommendations

    private var whatYouDressForSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "What you actually dress for", comment: "Onboarding section title"),
                eyebrow: String(localized: "YOUR WEEK", comment: "Onboarding section eyebrow")
            )

            SingleChoiceGroup(
                title: String(localized: "What are you dressed for most days?", comment: "Lifestyle question"),
                reason: String(localized: "The single biggest filter on what Kyra suggests.",
                               comment: "Why dress code is asked"),
                options: DressCode.allCases,
                label: { $0.displayName },
                identity: { $0.rawValue },
                selection: $draft.dressCode,
                identifier: "dressCode"
            )

            // §6.8's "typical week", which is a different question from dress
            // code and was missing entirely. Dress code says what he wears when
            // he is dressed for work; this says how many days that is. Five days
            // in an office and one need different QUANTITIES of the same
            // wardrobe, and nothing else on the profile tells them apart.
            SingleChoiceGroup(
                title: String(localized: "And what does a normal week look like?", comment: "Lifestyle question"),
                reason: String(localized: "Decides how much of your wardrobe has to work hard versus sit in reserve.",
                               comment: "Why typical week is asked"),
                options: LifestyleOptions.typicalWeeks,
                label: { $0 },
                identity: { $0 },
                selection: $draft.typicalWeek,
                identifier: "typicalWeek"
            )

            SingleChoiceGroup(
                title: String(localized: "What line of work are you in?", comment: "Lifestyle question"),
                reason: String(localized: "Sets the baseline for how hard your clothes have to work.",
                               comment: "Why occupation is asked"),
                options: OccupationCategory.allCases,
                label: { $0.displayName },
                identity: { $0.rawValue },
                selection: $draft.occupationCategory,
                identifier: "occupation"
            )

            MultiChoiceGroup(
                title: String(localized: "What else comes up?", comment: "Lifestyle question"),
                // Was "the outfits men get caught out by", then "caught short
                // on" — the first a British idiom, the second a British idiom
                // with an unfortunate second meaning. Both also generalised
                // about men rather than addressing the user.
                reason: String(localized: "Pick as many as apply. Kyra keeps something ready for each one.",
                               comment: "Why occasions are asked"),
                options: LifestyleOptions.occasions,
                selection: $draft.commonOccasions,
                identifier: "occasion"
            )

            SingleChoiceGroup(
                title: String(localized: "How often do you do laundry?", comment: "Lifestyle question"),
                // The reason is concrete because the question sounds irrelevant.
                // Without it this reads as the app being nosy for no return.
                reason: String(localized: "Decides how many shirts a rotation needs. Kyra won't tell you to buy seven if you wash twice a week.",
                               comment: "Why laundry cadence is asked"),
                options: LaundryCadence.allCases,
                label: { $0.displayName },
                identity: { $0.rawValue },
                selection: $draft.laundryCadence,
                identifier: "laundryCadence"
            )
        }
    }

    // MARK: - Everything else

    private var secondarySection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.md) {
            AstraSectionHeader(
                title: String(localized: "Anything else worth knowing", comment: "Onboarding section title"),
                eyebrow: String(localized: "OPTIONAL", comment: "Onboarding section eyebrow")
            )

            // Says plainly that the rest can be left alone. On an eleven-field
            // screen the honest thing is to mark where the required-feeling part
            // ends, rather than letting the length imply it is all needed.
            Text("Leave any of these blank if you'd rather. Each one narrows what Kyra puts in front of you.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            budgetRow

            SingleChoiceGroup(
                title: String(localized: "How often do you travel?", comment: "Lifestyle question"),
                reason: String(localized: "Changes what's worth owning — linen wrinkles differently when it lives in a bag.",
                               comment: "Why travel frequency is asked"),
                options: LifestyleOptions.travelFrequencies,
                label: { $0 },
                identity: { $0 },
                selection: $draft.travelFrequency,
                identifier: "travel"
            )

            SingleChoiceGroup(
                title: String(localized: "Any dress requirements for services or ceremonies?", comment: "Lifestyle question"),
                // Neutral and opt-in. Naming specific traditions here would
                // require guessing at the user's, so the question asks about the
                // requirement rather than about him.
                reason: String(localized: "Only asked so Kyra doesn't suggest something inappropriate for an occasion that matters to you.",
                               comment: "Why service attire needs are asked"),
                options: LifestyleOptions.serviceAttireNeeds,
                label: { $0 },
                identity: { $0 },
                selection: $draft.religiousServiceAttireNeeds,
                identifier: "serviceAttire"
            )

            SingleChoiceGroup(
                title: String(localized: "How much does sustainability matter?", comment: "Lifestyle question"),
                reason: String(localized: "Affects which brands and fabrics Kyra puts in front of you.",
                               comment: "Why sustainability preference is asked"),
                options: LifestyleOptions.sustainabilityPreferences,
                label: { $0 },
                identity: { $0 },
                selection: $draft.sustainabilityPreference,
                identifier: "sustainability"
            )

            brandsRow
        }
    }

    // MARK: - Budget

    private var budgetRow: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text("Roughly what do you spend on clothes?")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Used to keep suggestions in range. Nothing is ever bought for you.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // §6.8 says "monthly OR annual", and the screen previously asked
            // neither — just a number next to a currency code. $250 a month and
            // $250 a year are different customers, and Kyra would have
            // calibrated against whichever the user happened to assume.
            Picker("Budget period", selection: $budgetPeriod) {
                ForEach(BudgetPeriod.allCases, id: \.self) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.lifestyle.budgetPeriod")

            HStack(spacing: AstraSpacing.sm) {
                // The currency is shown, not assumed. It is stored NOT NULL and
                // defaults from the device locale, but a user whose phone is set
                // to one region and whose money is in another needs to see which
                // one the number is in before he types it.
                Text(draft.currency)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textMuted)
                    .monospaced()
                    .accessibilityLabel(
                        String(format: String(localized: "Currency: %@",
                                              comment: "VoiceOver: budget currency"), draft.currency)
                    )

                TextField(
                    budgetPeriod.placeholder,
                    text: Binding(
                        get: { enteredBudget },
                        set: { raw in
                            enteredBudget = raw
                            commitBudget()
                        }
                    )
                )
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: "budget")
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                .accessibilityIdentifier("onboarding.lifestyle.budget")
                .accessibilityLabel(budgetPeriod.accessibilityLabel)
            }
            .padding(.horizontal, AstraSpacing.md)
            .padding(.vertical, AstraSpacing.sm)
            .frame(minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card).fill(AstraColor.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card)
                    .stroke(AstraColor.divider, lineWidth: 1)
            )
        }
        .onChange(of: budgetPeriod) { _, _ in commitBudget() }
    }

    /// Normalises whatever the user typed into the monthly figure that
    /// `lifestyle_profiles.monthly_budget` stores.
    ///
    /// The conversion lives here, once, for the same reason `MeasurementEntry`
    /// converts units in one place: a yearly figure stored raw in a column named
    /// `monthly_budget` would be wrong by a factor of twelve everywhere
    /// downstream, and `CostPerWearCalculator` would report it without
    /// complaint.
    private func commitBudget() {
        guard let typed = Decimal(string: enteredBudget), typed > 0 else {
            draft.monthlyBudget = nil
            return
        }
        draft.monthlyBudget = budgetPeriod == .yearly ? typed / 12 : typed
    }

    // MARK: - Brands

    private var brandsRow: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text("Any brands or stores you already like?")
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Brands or shops, separated by commas. Kyra uses them as a starting point, not a limit.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                String(localized: "Uniqlo, Todd Snyder…", comment: "Brands placeholder"),
                text: Binding(
                    get: { draft.preferredBrands.joined(separator: ", ") },
                    set: { raw in
                        // Split on the separator the placeholder asked for, trim,
                        // and drop empties — so a trailing comma while typing does
                        // not store a blank brand that shows up as an empty chip
                        // everywhere downstream.
                        draft.preferredBrands = raw
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                )
            )
            .focused($focusedField, equals: "brands")
            .astraText(.body)
            .foregroundStyle(AstraColor.textPrimary)
            .autocorrectionDisabled()
            .padding(.horizontal, AstraSpacing.md)
            .padding(.vertical, AstraSpacing.sm)
            .frame(minHeight: AstraSize.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AstraRadius.card).fill(AstraColor.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AstraRadius.card)
                    .stroke(AstraColor.divider, lineWidth: 1)
            )
            .accessibilityIdentifier("onboarding.lifestyle.brands")
        }
    }
}

// MARK: - Budget period

/// Which period the typed budget figure refers to.
///
/// Presentation-only: the database column is `monthly_budget` and always holds
/// a monthly figure. This exists so a man who thinks in yearly terms can answer
/// in yearly terms.
enum BudgetPeriod: String, CaseIterable, Sendable {
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .monthly: String(localized: "A month", comment: "Budget period")
        case .yearly: String(localized: "A year", comment: "Budget period")
        }
    }

    var placeholder: String {
        switch self {
        case .monthly: String(localized: "e.g. 250", comment: "Monthly budget placeholder")
        case .yearly: String(localized: "e.g. 3000", comment: "Yearly budget placeholder")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .monthly: String(localized: "Clothing budget per month", comment: "VoiceOver")
        case .yearly: String(localized: "Clothing budget per year", comment: "VoiceOver")
        }
    }
}

// MARK: - Options

/// The free-text vocabularies §6.8 leaves open.
///
/// These columns are `text` rather than enums because the migration says so and
/// the reasoning holds: cadence and travel phrasing are naturally open. Offering
/// a short list keeps the common answers consistent without closing the set.
enum LifestyleOptions {
    static let occasions = [
        "Date nights", "Weddings", "Client meetings", "Weekend travel",
        "Gym", "Nights out", "Family events", "Funerals", "Interviews"
    ]

    /// Ordered by how much of the week is "dressed for work", because that is
    /// the axis the answer actually feeds.
    static let typicalWeeks = [
        "Mostly in an office", "Split between home and office",
        "Mostly working from home", "On site or on the move", "Different every week"
    ]

    static let travelFrequencies = [
        "Rarely", "A few times a year", "Monthly", "Most weeks"
    ]

    /// Phrased as requirements, not traditions.
    static let serviceAttireNeeds = [
        "None", "Covered shoulders and knees", "Head covering", "Modest dress", "Formal only"
    ]

    static let sustainabilityPreferences = [
        "Not a factor", "Prefer natural fibers", "Prefer secondhand", "Buy less, buy better"
    ]
}

// MARK: - Components

/// A question with a reason and a wrapping row of single-select chips.
///
/// Generic over the option type so enum-backed and string-backed questions share
/// one component — the alternative was two near-identical views that drift.
private struct SingleChoiceGroup<Option: Hashable>: View {
    let title: String
    let reason: String
    let options: [Option]
    let label: (Option) -> String
    let identity: (Option) -> String
    @Binding var selection: Option?
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(title)
                .astraText(.headline)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(reason)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(options, id: \.self) { option in
                    AstraChip(
                        label(option),
                        isSelected: selection == option,
                        action: {
                            // Re-tapping clears. Every field on this step is
                            // optional, so "no answer" must stay reachable after
                            // a mis-tap.
                            selection = selection == option ? nil : option
                            AstraHaptics.selection()
                        }
                    )
                    .accessibilityIdentifier(
                        "onboarding.lifestyle.\(identifier).\(Self.slug(identity(option)))"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(reason)
    }

    private static func slug(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}

/// Same, but any number of options may be chosen.
private struct MultiChoiceGroup: View {
    let title: String
    let reason: String
    let options: [String]
    @Binding var selection: [String]
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .astraText(.headline)
                    .foregroundStyle(AstraColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AstraSpacing.sm)

                // A count, because multi-select with no counter gives the user no
                // way to confirm a tap registered other than re-reading every
                // chip. Hidden at zero so an untouched question is not decorated
                // with a "0".
                if !selection.isEmpty {
                    Text("\(selection.count)")
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
            }

            Text(reason)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AstraWrappingHStack(spacing: AstraSpacing.xs) {
                ForEach(options, id: \.self) { option in
                    AstraChip(
                        option,
                        isSelected: selection.contains(option),
                        action: {
                            if let index = selection.firstIndex(of: option) {
                                selection.remove(at: index)
                            } else {
                                selection.append(option)
                            }
                            AstraHaptics.selection()
                        }
                    )
                    .accessibilityIdentifier(
                        "onboarding.lifestyle.\(identifier).\(option.lowercased().replacingOccurrences(of: " ", with: "_"))"
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(reason)
    }
}

#Preview("Lifestyle") {
    @Previewable @State var draft = OnboardingDraft()
    return ScrollView {
        OnboardingLifestyleView(draft: $draft)
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
}
