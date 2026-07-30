//
//  OnboardingMeasurementsView.swift
//  AstraStyle
//
//  Spec §6.6 — Measurements and fit.
//
//  This screen feeds `FrameProfile` (docs/14), so it is the one whose answers do
//  the most downstream work. It is also the one most likely to be abandoned: it
//  asks a man for six numbers about his body, and the ones he does not know he
//  will not guess.
//
//  Hence three decisions:
//
//  1. "I DON'T KNOW" IS A BUTTON, NOT AN EMPTY FIELD. Spec §6.6 requires it, and
//     `MeasurementEntry.State` distinguishes declined from unanswered so the app
//     never re-prompts for something he has already declined. An empty field
//     cannot carry that difference.
//
//  2. THE UNIT TOGGLE IS AT THE TOP AND EVERY FIELD LABELS ITS UNIT. Storage is
//     canonically centimetres (`BodyProfile`), and conversion happens in exactly
//     one place — `MeasurementEntry.centimetres`. The value the user typed is
//     kept as typed alongside the unit he typed it in, so flipping the toggle
//     never silently reinterprets 71 inches as 71cm.
//
//  3. FIT ISSUES ARE PHRASED AS GARMENT BEHAVIOUR. "Trousers are tight through
//     the thigh", never "large thighs" (see `FitIssue.displayName`). Spec §2
//     forbids shaming body type, and this is the screen where that is easiest to
//     get wrong.
//

import SwiftUI

struct OnboardingMeasurementsView: View {
    @Binding var draft: OnboardingDraft

    @FocusState private var focusedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xl) {
            unitToggle
            measurementFields
            sizeFields
            preferredFitSection
            fitIssuesSection
        }
        // The decimal pad has NO return key. Without an explicit Done, a user who
        // taps a measurement field has the keyboard covering the Continue button
        // and no obvious way to put it away — he can scroll it down, but nothing
        // on screen says so. This was visible the first time the flow was walked
        // in the simulator and is the kind of dead end that ends an onboarding.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "Done", comment: "Dismiss the number keypad")) {
                    focusedField = nil
                }
                .accessibilityIdentifier("onboarding.keyboardDone")
            }
        }
    }

    // MARK: - Units

    private var unitToggle: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text("Units")
                .astraText(.micro)
                .foregroundStyle(AstraColor.textMuted)

            Picker("Units", selection: $draft.units) {
                Text("Inches / lb").tag(UnitsPreference.imperial)
                Text("cm / kg").tag(UnitsPreference.metric)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.units")
            .onChange(of: draft.units) { _, newValue in
                // Re-stamps the unit on fields the user has not filled in, so a
                // later entry is interpreted with the unit now on screen.
                // Deliberately does NOT touch entries already provided: their
                // stored unit is the one they were typed in, and rewriting it
                // would change what the number means.
                restampUnansweredUnits(to: newValue)
            }
        }
    }

    private func restampUnansweredUnits(to unit: UnitsPreference) {
        for keyPath in Self.measurementKeyPaths where draft[keyPath: keyPath].state == .unanswered {
            draft[keyPath: keyPath].unit = unit
        }
    }

    private static let measurementKeyPaths: [WritableKeyPath<OnboardingDraft, MeasurementEntry>] = [
        \.height, \.weight, \.chest, \.waist, \.inseam, \.neck
    ]

    // MARK: - Measurements

    private var measurementFields: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "Roughly is fine", comment: "Onboarding section title"),
                eyebrow: String(localized: "MEASUREMENTS", comment: "Onboarding section eyebrow")
            )

            MeasurementField(
                label: String(localized: "Height", comment: "Measurement label"),
                focusedField: $focusedField,
                entry: $draft.height,
                lengthUnitLabel: lengthUnitLabel,
                identifier: "height"
            )
            MeasurementField(
                label: String(localized: "Chest", comment: "Measurement label"),
                focusedField: $focusedField,
                entry: $draft.chest,
                lengthUnitLabel: lengthUnitLabel,
                identifier: "chest"
            )
            MeasurementField(
                label: String(localized: "Waist", comment: "Measurement label"),
                focusedField: $focusedField,
                entry: $draft.waist,
                lengthUnitLabel: lengthUnitLabel,
                identifier: "waist"
            )
            MeasurementField(
                label: String(localized: "Inseam", comment: "Measurement label"),
                focusedField: $focusedField,
                entry: $draft.inseam,
                lengthUnitLabel: lengthUnitLabel,
                identifier: "inseam"
            )
            MeasurementField(
                label: String(localized: "Neck", comment: "Measurement label"),
                focusedField: $focusedField,
                entry: $draft.neck,
                lengthUnitLabel: lengthUnitLabel,
                identifier: "neck"
            )
            MeasurementField(
                // §6.6 marks weight optional, and it is the field most likely to
                // be declined. Saying outright that it does not drive advice is
                // both true — docs/14 §2 excludes weight from every frame axis —
                // and the thing that makes declining it feel permitted.
                label: String(localized: "Weight", comment: "Measurement label"),
                focusedField: $focusedField,
                footnote: String(localized: "Optional, and not used for fit advice.",
                                 comment: "Weight field footnote"),
                entry: $draft.weight,
                lengthUnitLabel: massUnitLabel,
                identifier: "weight"
            )
        }
    }

    private var lengthUnitLabel: String {
        draft.units == .metric
            ? String(localized: "cm", comment: "Centimetres abbreviation")
            : String(localized: "in", comment: "Inches abbreviation")
    }

    private var massUnitLabel: String {
        draft.units == .metric
            ? String(localized: "kg", comment: "Kilograms abbreviation")
            : String(localized: "lb", comment: "Pounds abbreviation")
    }

    // MARK: - Sizes

    private var sizeFields: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "What you usually buy", comment: "Onboarding section title"),
                eyebrow: String(localized: "SIZES", comment: "Onboarding section eyebrow")
            )

            // Free text rather than pickers. Sizing vocabulary is not universal
            // — "10.5 US", "44 EU", "L", "16.5/34" are all real answers — and a
            // picker would force a man to translate his own size into ours.
            // `FrameDerivation` parses these leniently and returns nil rather
            // than guessing when it cannot.
            SizeField(
                label: String(localized: "Shirt size", comment: "Size label"),
                placeholder: String(localized: "M, 16.5/34…", comment: "Size placeholder"),
                text: $draft.shirtSize,
                identifier: "shirtSize"
            )
            SizeField(
                label: String(localized: "Trouser size", comment: "Size label"),
                placeholder: String(localized: "32, 32x30…", comment: "Size placeholder"),
                text: $draft.trouserSize,
                identifier: "trouserSize"
            )
            SizeField(
                label: String(localized: "Shoe size", comment: "Size label"),
                placeholder: String(localized: "10.5 US, 44 EU…", comment: "Size placeholder"),
                text: $draft.shoeSize,
                identifier: "shoeSize"
            )
        }
    }

    // MARK: - Preferred fit

    private var preferredFitSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "How you like things to sit", comment: "Onboarding section title"),
                eyebrow: String(localized: "FIT", comment: "Onboarding section eyebrow")
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AstraSpacing.xs) {
                    ForEach(ItemFit.allCases, id: \.self) { fit in
                        AstraChip(
                            fit.displayName,
                            isSelected: draft.preferredFit == fit,
                            action: {
                                // Tapping the selected chip clears it, so a user
                                // who changes his mind can return to "no
                                // preference" instead of being stuck with a
                                // choice he made by accident.
                                draft.preferredFit = draft.preferredFit == fit ? nil : fit
                                AstraHaptics.selection()
                            }
                        )
                        .accessibilityIdentifier("onboarding.fit.\(fit.rawValue)")
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Fit issues

    private var fitIssuesSection: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            AstraSectionHeader(
                title: String(localized: "Anything that's usually a problem?",
                              comment: "Onboarding section title"),
                eyebrow: String(localized: "WHAT DOESN'T FIT", comment: "Onboarding section eyebrow")
            )

            // Stated because it is true, and because it earns the answer: a
            // stated fit issue overrides a derived axis at full confidence
            // (docs/14 §2), making this the highest-leverage input on the screen.
            Text("These outrank the measurements above — if you tell Kyra sleeves come up short, she takes your word for it.")
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: AstraSpacing.xs) {
                ForEach(FitIssue.allCases.filter { $0 != .other }) { issue in
                    FitIssueRow(
                        issue: issue,
                        isSelected: draft.fitIssues.contains(issue),
                        toggle: {
                            if draft.fitIssues.contains(issue) {
                                draft.fitIssues.remove(issue)
                            } else {
                                draft.fitIssues.insert(issue)
                            }
                            AstraHaptics.selection()
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Field components

private struct MeasurementField: View {
    let label: String
    /// Shared focus binding so the keyboard's Done button can clear whichever
    /// field is active. A per-field `@FocusState` could not be reached from the
    /// parent's toolbar.
    @FocusState.Binding var focusedField: String?
    var footnote: String?
    @Binding var entry: MeasurementEntry
    let lengthUnitLabel: String
    let identifier: String

    @State private var text: String = ""

    private var isDeclined: Bool { entry.state == .declined }

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            HStack(spacing: AstraSpacing.sm) {
                Text(label)
                    .astraText(.body)
                    .foregroundStyle(isDeclined ? AstraColor.textMuted : AstraColor.textPrimary)
                    .frame(width: 84, alignment: .leading)

                TextField(isDeclined ? "—" : "", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: identifier)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                    .disabled(isDeclined)
                    .onChange(of: text) { _, newValue in commit(newValue) }
                    .accessibilityIdentifier("onboarding.measurement.\(identifier)")

                Text(lengthUnitLabel)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)

                Button(action: toggleDeclined) {
                    Text(isDeclined
                         ? String(localized: "Undo", comment: "Undo declining a measurement")
                         : String(localized: "Not sure", comment: "Decline a measurement"))
                        .astraText(.caption)
                        .foregroundStyle(
                            isDeclined ? AstraColor.accentChampagneAccessible : AstraColor.textSecondary
                        )
                }
                .buttonStyle(.plain)
                .frame(minWidth: 56, minHeight: AstraSize.minTapTarget, alignment: .trailing)
                .accessibilityIdentifier("onboarding.notSure.\(identifier)")
                .accessibilityLabel(
                    isDeclined
                    ? String(format: String(localized: "Undo not sure for %@",
                                            comment: "VoiceOver: undo declining"), label)
                    : String(format: String(localized: "Mark %@ as not sure",
                                            comment: "VoiceOver: decline"), label)
                )
            }
            .padding(.vertical, AstraSpacing.xs)

            if let footnote {
                Text(footnote)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .padding(.leading, 84 + AstraSpacing.sm)
            }

            Divider().overlay(AstraColor.divider)
        }
        .onAppear {
            // Seed from the draft so a resumed session shows what was typed.
            if entry.state == .provided, let value = entry.value {
                text = Self.format(value)
            }
        }
    }

    private func commit(_ raw: String) {
        // Accept both separators: a decimal keypad emits the locale's separator,
        // and Double(_:) only parses ".".
        let normalised = raw.replacingOccurrences(of: ",", with: ".")
        guard !normalised.isEmpty else {
            entry = MeasurementEntry(state: .unanswered, value: nil, unit: entry.unit)
            return
        }
        guard let value = Double(normalised), value > 0 else { return }
        entry = .provided(value, unit: entry.unit)
    }

    private func toggleDeclined() {
        if isDeclined {
            entry = MeasurementEntry(state: .unanswered, value: nil, unit: entry.unit)
        } else {
            text = ""
            if focusedField == identifier { focusedField = nil }
            entry = .declined(unit: entry.unit)
        }
        AstraHaptics.selection()
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

private struct SizeField: View {
    let label: String
    let placeholder: String
    @Binding var text: String?
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            HStack(spacing: AstraSpacing.sm) {
                Text(label)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                    .frame(width: 110, alignment: .leading)

                TextField(
                    placeholder,
                    text: Binding(
                        get: { text ?? "" },
                        // Empty string becomes nil, not "". A blank size stored
                        // as an empty string reads as answered everywhere
                        // downstream and would defeat `FrameDerivation`'s
                        // fallback checks.
                        set: { text = $0.isEmpty ? nil : $0 }
                    )
                )
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .accessibilityIdentifier("onboarding.size.\(identifier)")
            }
            .frame(minHeight: AstraSize.minTapTarget)

            Divider().overlay(AstraColor.divider)
        }
    }
}

private struct FitIssueRow: View {
    let issue: FitIssue
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: AstraSpacing.md) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        isSelected ? AstraColor.accentChampagneAccessible : AstraColor.textMuted
                    )
                    .accessibilityHidden(true)

                Text(issue.displayName)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .frame(minHeight: AstraSize.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("onboarding.fitIssue.\(issue.rawValue)")
    }
}

#Preview("Measurements") {
    @Previewable @State var draft = OnboardingDraft()
    return ScrollView {
        OnboardingMeasurementsView(draft: $draft)
            .padding(AstraSpacing.pagePadding)
    }
    .background(AstraColor.backgroundPrimary)
}
