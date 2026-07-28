//
//  HomeOfflineBanner.swift
//  AstraStyle
//
//  Shown alongside otherwise-normal cached content (spec §7 "Cached closet
//  and outfits remain viewable" — offline is not, by itself, an error
//  state).
//

import SwiftUI

struct HomeOfflineBanner: View {
    var body: some View {
        HStack(spacing: AstraSpacing.xs) {
            Image(systemName: "wifi.slash")
            Text("You're offline. Showing your last saved brief.")
                .astraText(.caption)
        }
        .foregroundStyle(AstraColor.textSecondary)
        .padding(.horizontal, AstraSpacing.sm)
        .padding(.vertical, AstraSpacing.xxs)
        .frame(maxWidth: .infinity)
        .background(AstraColor.surfaceElevated, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("You're offline. Showing your last saved brief."))
    }
}
