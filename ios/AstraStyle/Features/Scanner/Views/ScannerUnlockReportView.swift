//
//  ScannerUnlockReportView.swift
//  AstraStyle
//
//  Post-save unlock count (P3-SCAN-11 / spec §5.3 step 9). Kept in its own
//  file so `ScannerReviewView` stays under SwiftLint `type_body_length`.
//

import SwiftUI

struct ScannerUnlockReportView: View {
    let outfitsUnlockedCount: Int?
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.xl) {
            Spacer(minLength: AstraSpacing.xxl)
            VStack(spacing: AstraSpacing.md) {
                Text(String(localized: "Saved to your closet", comment: "Post-scan save confirmation title"))
                    .astraText(.title1)
                    .foregroundStyle(AstraColor.textPrimary)
                    .multilineTextAlignment(.center)

                if let count = outfitsUnlockedCount {
                    Text(unlockCopy(count))
                        .astraText(.body)
                        .foregroundStyle(AstraColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("scanner.review.unlockCount")
                }
            }
            .padding(.horizontal, AstraSpacing.pagePadding)

            Button(String(localized: "Done", comment: "Dismiss scanner after save")) {
                onDone()
            }
            .buttonStyle(.astraPrimary)
            .padding(.horizontal, AstraSpacing.pagePadding)
            .accessibilityIdentifier("scanner.review.done")

            Spacer(minLength: AstraSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlockCopy(_ count: Int) -> String {
        if count == 0 {
            return String(localized: "No new outfit combinations yet — add a few more pieces and this will start to compound.",
                          comment: "Post-scan unlock count is zero")
        }
        if count == 1 {
            return String(localized: "This unlocks 1 new outfit combination with what you already own.",
                          comment: "Post-scan unlock count singular")
        }
        return String(localized: "This unlocks \(count) new outfit combinations with what you already own.",
                      comment: "Post-scan unlock count plural")
    }
}
