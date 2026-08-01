//
//  AstraTextField.swift
//  AstraStyle
//
//  Labelled text entry. Promotes the treatment that was inlined twice in
//  Features/Slice/SliceView.swift (`.astraText(.body)` + `AstraSpacing.sm`
//  padding + an `AstraRadius.small` `backgroundSecondary` rectangle) into a
//  real component, because the closet add/edit form needs it in eight
//  places and a copy-pasted field is where accessibility quietly stops
//  being done — the SliceView version renders the label as a floating
//  `Text` and then re-states it by hand in `.accessibilityLabel`, which is
//  correct only for as long as someone remembers to write both.
//
//  TWO TYPES, NOT ONE `format:` PARAMETER.
//  `AstraTextField` binds a `String`; `AstraDecimalField` binds a
//  `Decimal?`. A single component taking a `ParseableFormatStyle` was the
//  obvious alternative and is worse here for two concrete reasons:
//
//  1. SwiftUI's own `TextField(_:value:format:)` cannot express "empty
//     means nil". When the user clears the field it does not write a value
//     at all — the binding keeps whatever was there before, so an emptied
//     price silently stays at its old number, and a field seeded from
//     `nil` shows `0`. Price paid is optional on `ClosetItem`; "he didn't
//     say" and "he paid nothing" are different facts about a garment and
//     the wardrobe-graph cost-per-wear maths depends on telling them
//     apart. Getting that right needs a `String` buffer of our own, which
//     is exactly the thing a `format:` parameter is supposed to remove.
//  2. It would push a generic parameter onto all eight plain-text call
//     sites to serve one numeric one.
//
//  Both types share `AstraFieldScaffold` below, so there is still only one
//  implementation of the visual treatment.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A labelled single- or multi-line text field.
///
/// ```swift
/// AstraTextField(
///     String(localized: "Name", comment: "Closet item name field"),
///     text: $viewModel.name,
///     placeholder: String(localized: "e.g. Navy Merino Sweater", comment: "…"),
///     isRequired: true
/// )
/// ```
///
/// FOCUS. The component owns a `@FocusState` for its own border treatment
/// only. A form that wants return-key navigation between fields attaches
/// its own `.focused($field, equals:)` to the `AstraTextField` itself —
/// focus modifiers propagate to the focusable descendant — rather than this
/// type growing a focus-binding parameter that every single-field call site
/// would have to pass `nil` for.
public struct AstraTextField: View {
    private let label: String
    @Binding private var text: String
    private let placeholder: String
    private let footnote: String?
    private let errorText: String?
    private let isRequired: Bool
    private let keyboardType: UIKeyboardType
    private let textContentType: UITextContentType?
    private let submitLabel: SubmitLabel
    private let autocapitalization: TextInputAutocapitalization
    private let axis: Axis

    @FocusState private var isFocused: Bool

    /// - Parameters:
    ///   - label: The field's visible label, and its VoiceOver label. Pass
    ///     an already-localized string.
    ///   - text: The bound text.
    ///   - placeholder: Optional greyed-out example shown while empty.
    ///     Never used as the accessibility label — placeholder text
    ///     disappears the moment the user types, so a field labelled only
    ///     by its placeholder becomes an unlabelled field mid-edit.
    ///   - footnote: Optional helper text below the field.
    ///   - errorText: Optional validation error. Replaces `footnote` and
    ///     turns the border `destructive`.
    ///   - isRequired: Marks the label and appends "Required" to the
    ///     VoiceOver label.
    ///   - keyboardType: Pass-through to `.keyboardType`.
    ///   - textContentType: Pass-through to `.textContentType`, for
    ///     autofill and the QuickType bar.
    ///   - submitLabel: Pass-through to `.submitLabel`.
    ///   - autocapitalization: Pass-through to
    ///     `.textInputAutocapitalization`.
    ///   - axis: `.vertical` makes the field grow to multiple lines (notes,
    ///     care instructions).
    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String? = nil,
        footnote: String? = nil,
        errorText: String? = nil,
        isRequired: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        submitLabel: SubmitLabel = .return,
        autocapitalization: TextInputAutocapitalization = .sentences,
        axis: Axis = .horizontal
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder ?? ""
        self.footnote = footnote
        self.errorText = errorText
        self.isRequired = isRequired
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.submitLabel = submitLabel
        self.autocapitalization = autocapitalization
        self.axis = axis
    }

    public var body: some View {
        AstraFieldScaffold(
            label: label,
            isRequired: isRequired,
            footnote: footnote,
            errorText: errorText,
            isFocused: isFocused
        ) {
            TextField(placeholder, text: $text, axis: axis)
                .astraText(.body)
                .foregroundStyle(AstraColor.textPrimary)
                // The caret is the one place gold is a fill rather than
                // text, so `accentChampagne` and not the accessible variant.
                .tint(AstraColor.accentChampagne)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .submitLabel(submitLabel)
                .textInputAutocapitalization(autocapitalization)
                .focused($isFocused)
                .accessibilityLabel(Text(AstraFieldAccessibility.label(label, isRequired: isRequired, errorText: errorText)))
                .accessibilityHint(Text(AstraFieldAccessibility.hint(footnote: footnote, errorText: errorText)))
        }
    }
}

// MARK: - Decimal / money entry

/// A labelled field for an optional `Decimal` — the "price paid" case.
///
/// Empty input resolves to `nil`, not `0`. See this file's header for why
/// that is the whole reason this type exists separately.
public struct AstraDecimalField: View {
    private let label: String
    @Binding private var value: Decimal?
    private let placeholder: String
    private let footnote: String?
    private let errorText: String?
    private let isRequired: Bool
    private let currencyCode: String?

    /// The authoritative thing the user is editing while the field has
    /// focus. `value` is derived from it, never the other way round mid-
    /// keystroke: "12." and "0009" are legitimate things to be halfway
    /// through typing, and formatting the `Decimal` back into the field on
    /// every change would delete the character just entered.
    @State private var buffer: String
    @FocusState private var isFocused: Bool

    /// - Parameters:
    ///   - label: The field's visible and VoiceOver label.
    ///   - value: The bound amount. `nil` means "not stated".
    ///   - placeholder: Optional example shown while empty.
    ///   - footnote: Optional helper text below the field.
    ///   - errorText: Optional validation error; replaces `footnote` and
    ///     turns the border `destructive`.
    ///   - isRequired: Marks the label and the VoiceOver label.
    ///   - currencyCode: ISO 4217 code (`ClosetItem.currency`). Renders its
    ///     symbol as a static prefix. The symbol is decoration, not part of
    ///     the editable text — a user who types "£" into a number field
    ///     should not have to delete it again.
    public init(
        _ label: String,
        value: Binding<Decimal?>,
        placeholder: String? = nil,
        footnote: String? = nil,
        errorText: String? = nil,
        isRequired: Bool = false,
        currencyCode: String? = nil
    ) {
        self.label = label
        self._value = value
        self.placeholder = placeholder ?? ""
        self.footnote = footnote
        self.errorText = errorText
        self.isRequired = isRequired
        self.currencyCode = currencyCode
        self._buffer = State(initialValue: Self.text(from: value.wrappedValue))
    }

    public var body: some View {
        AstraFieldScaffold(
            label: label,
            isRequired: isRequired,
            footnote: footnote,
            errorText: errorText,
            isFocused: isFocused
        ) {
            HStack(spacing: AstraSpacing.xxs) {
                if let symbol = currencySymbol {
                    Text(symbol)
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textMuted)
                        // Already spoken as part of the field's
                        // accessibility label; left visible only.
                        .accessibilityHidden(true)
                }
                TextField(placeholder, text: $buffer)
                    .astraText(.body)
                    .foregroundStyle(AstraColor.textPrimary)
                    .tint(AstraColor.accentChampagne)
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
                    .accessibilityLabel(Text(accessibilityLabel))
                    .accessibilityHint(Text(AstraFieldAccessibility.hint(footnote: footnote, errorText: errorText)))
            }
            .onChange(of: buffer) { _, newValue in
                value = Self.decimal(from: newValue)
            }
            .onChange(of: value) { _, newValue in
                // Only for changes that did NOT come from typing — a form
                // reset, or a server round trip filling the field in. The
                // guard is what stops this from fighting `buffer`'s own
                // `onChange` above and truncating "12." to "12".
                guard Self.decimal(from: buffer) != newValue else { return }
                buffer = Self.text(from: newValue)
            }
        }
    }

    private var currencySymbol: String? {
        guard let currencyCode else { return nil }
        return Locale.current.currencySymbol(forCurrencyCode: currencyCode)
    }

    private var accessibilityLabel: String {
        let base = AstraFieldAccessibility.label(label, isRequired: isRequired, errorText: errorText)
        guard let symbol = currencySymbol else { return base }
        return "\(base), \(symbol)"
    }

    // MARK: Parsing

    /// Parses what the user typed, tolerating both `.` and `,` as the
    /// decimal mark and ignoring grouping marks.
    ///
    /// Not `Decimal(string:)` on the raw text: that method is locale-blind
    /// and reads "1,5" as `1`, which is the same shape of bug as accepting
    /// an emptied field as `0` — a wrong number that looks like a right
    /// one. Grouping separators are stripped BEFORE the decimal mark is
    /// normalised, because in `de_DE` the grouping mark is the `.` that
    /// would otherwise survive as a decimal point.
    static func decimal(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var normalised = trimmed
        if let grouping = Locale.current.groupingSeparator {
            normalised = normalised.replacingOccurrences(of: grouping, with: "")
        }
        if let separator = Locale.current.decimalSeparator, separator != "." {
            normalised = normalised.replacingOccurrences(of: separator, with: ".")
        }
        // POSIX rather than `.current`: `normalised` is now unambiguously
        // dot-decimal, so parsing it against a comma-decimal locale would
        // undo the normalisation immediately above.
        return Decimal(string: normalised, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Seeds/refreshes the buffer from a `Decimal`. Ungrouped, because the
    /// result goes back into an editable field and "1,299" is not something
    /// a decimal keypad can reproduce.
    static func text(from value: Decimal?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.grouping(.never))
    }
}

private extension Locale {
    /// The symbol for a SPECIFIC ISO 4217 code, presented the way this
    /// locale would present it.
    ///
    /// Not `Locale.currencySymbol`, which describes the locale's own
    /// currency — a jacket bought in Stockholm and recorded as `SEK` would
    /// render with a `£` for a UK user, which is not a cosmetic error but a
    /// wrong price. `NumberFormatter` is used rather than a `FormatStyle`
    /// because it is the only API that exposes the symbol on its own; the
    /// fallback is the raw code, so an unrecognised currency reads "SEK 450"
    /// rather than losing the unit entirely.
    func currencySymbol(forCurrencyCode code: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = self
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
}

// MARK: - Shared chrome

/// The label / field / supporting-text stack both field types render.
///
/// Separate from the two public types so the visual treatment exists once.
/// Deliberately NOT public: a caller who needs this shape for some third
/// control should get a third named component with its own accessibility
/// contract, not a naked box to put anything in.
private struct AstraFieldScaffold<Field: View>: View {
    let label: String
    let isRequired: Bool
    let footnote: String?
    let errorText: String?
    let isFocused: Bool
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
            labelRow
            field()
                .padding(AstraSpacing.sm)
                // `.topLeading` matters for the multi-line (`axis: .vertical`)
                // case: with the default centre alignment a note that has
                // grown to four lines centres its first line against a box
                // that is still `minTapTarget` tall at rest, and the text
                // visibly jumps as it wraps.
                .frame(minHeight: AstraSize.minTapTarget, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                        .fill(AstraColor.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AstraRadius.small, style: .continuous)
                        .strokeBorder(borderState.color, lineWidth: borderState.lineWidth)
                )
                .astraAnimation(AstraMotion.standard, value: borderState)
            supportingText
        }
    }

    private var labelRow: some View {
        HStack(spacing: AstraSpacing.xxs) {
            Text(label)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textSecondary)
            if isRequired {
                // A word, not an asterisk. An asterisk is a convention the
                // reader has to already know, VoiceOver reads it as "star",
                // and at 12 pt it is three pixels. The word is also why
                // `AstraFieldAccessibility.label` appends "Required" — the
                // two must say the same thing.
                Text(String(localized: "Required", comment: "Marks a form field the user must fill in"))
                    .astraText(.micro)
                    .foregroundStyle(AstraColor.textMuted)
            }
        }
        // The visible label IS the field's accessibility label (see
        // `AstraFieldAccessibility.label`). Left visible to VoiceOver it
        // would be a second, separate element announcing the same word
        // immediately before the field does — the exact duplication the
        // hand-rolled SliceView version produced.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var supportingText: some View {
        if let errorText {
            Text(errorText)
                .astraText(.caption)
                .foregroundStyle(AstraColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
                // Folded into the field's accessibility LABEL rather than
                // read as its own element or left as a hint: VoiceOver's
                // "Speak Hints" is a setting the user can turn off, and a
                // validation error that a user can switch off is a form he
                // cannot submit and cannot be told why.
                .accessibilityHidden(true)
        } else if let footnote {
            Text(footnote)
                .astraText(.caption)
                .foregroundStyle(AstraColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                // Helper text IS advisory, so it goes to the hint, which is
                // what hints are for.
                .accessibilityHidden(true)
        }
    }

    private var borderState: AstraFieldBorderState {
        if errorText != nil { return .invalid }
        return isFocused ? .focused : .idle
    }
}

/// Border treatments, in precedence order: an invalid field stays marked as
/// invalid while it is being corrected, so focus does not paint over the
/// only signal that something is wrong.
private enum AstraFieldBorderState {
    case idle
    case focused
    case invalid

    var color: Color {
        switch self {
        case .idle: AstraColor.divider
        // A border is a fill, not text, so this is `accentChampagne` and
        // not `accentChampagneAccessible` (spec §3 / docs/07).
        case .focused: AstraColor.accentChampagne
        case .invalid: AstraColor.destructive
        }
    }

    /// Focus and error are both thickened rather than only recolored —
    /// spec §19 and the same rule `AstraChip` follows: state must not be
    /// carried by hue alone.
    var lineWidth: CGFloat {
        switch self {
        case .idle: 1
        case .focused, .invalid: 2
        }
    }
}

/// Builds the VoiceOver strings both field types use, so "the label, then
/// required, then the error" is stated once instead of twice.
private enum AstraFieldAccessibility {
    static func label(_ label: String, isRequired: Bool, errorText: String?) -> String {
        var parts = [label]
        if isRequired {
            parts.append(String(localized: "Required", comment: "Marks a form field the user must fill in"))
        }
        if let errorText {
            parts.append(errorText)
        }
        return parts.joined(separator: ", ")
    }

    /// The helper text, or an empty string when there is none — an empty
    /// hint is silent, which lets the modifier be applied unconditionally
    /// instead of branching the view's type.
    static func hint(footnote: String?, errorText: String?) -> String {
        errorText == nil ? (footnote ?? "") : ""
    }
}
