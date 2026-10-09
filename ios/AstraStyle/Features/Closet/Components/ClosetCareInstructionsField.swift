import SwiftUI

struct ClosetCareInstructionsField: View {
    @Binding var careInstructions: String

    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Care instructions", comment: "User-entered garment care notes field label"))
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textSecondary)
                Spacer(minLength: AstraSpacing.sm)
                if !careInstructions.isEmpty {
                    Button(String(localized: "Clear", comment: "Clears optional garment care notes")) {
                        careInstructions = ""
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: AstraSize.minTapTarget, minHeight: AstraSize.minTapTarget)
                    .foregroundStyle(AstraColor.accentChampagneAccessible)
                    .accessibilityIdentifier("closet.form.careInstructions.clear")
                    .accessibilityHint(String(localized: "Removes the entered care instructions; save the item to apply the change."))
                }
            }
            TextField(
                String(localized: "Add notes from the care label", comment: "Care instructions placeholder"),
                text: $careInstructions,
                axis: .vertical
            )
            .lineLimit(3...6)
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("closet.form.careInstructions")
        }
    }

}
