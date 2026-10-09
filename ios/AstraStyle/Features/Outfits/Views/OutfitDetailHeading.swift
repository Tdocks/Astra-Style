import SwiftUI

/// Keeps long outfit names readable beside scores at larger text sizes.
struct OutfitDetailHeading: View {
    let name: String
    let score: Int?
    let compatibilityTitle: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        layout {
            Text(name)
                .astraText(.title1)
                .foregroundStyle(AstraColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: AstraSpacing.sm)
            }
            if let score {
                AstraScoreMeter(score: score, title: compatibilityTitle, style: .compact)
            }
        }
    }

    private var layout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: AstraSpacing.sm))
        } else {
            AnyLayout(HStackLayout(alignment: .top, spacing: AstraSpacing.sm))
        }
    }
}
