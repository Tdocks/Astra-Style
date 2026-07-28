//
//  HomeLoadingSkeletonView.swift
//  AstraStyle
//
//  Spec §21 "Skeleton state" for Home, shown while the first Daily Brief
//  load is in flight (spec §20 target: cached render under 500 ms, so this
//  should rarely be visible for long once a brief has ever loaded once).
//

import SwiftUI

struct HomeLoadingSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: AstraSpacing.xs) {
                    skeletonBlock(width: 220, height: 22)
                    skeletonBlock(width: 140, height: 14)
                }
                Spacer()
                Circle().fill(AstraColor.surfaceElevated).frame(width: 44, height: 44)
            }

            skeletonBlock(width: nil, height: 420, cornerRadius: AstraSpacing.cardRadius)

            skeletonBlock(width: 160, height: 18)
            HStack(spacing: AstraSpacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    skeletonBlock(width: 140, height: 175, cornerRadius: AstraSpacing.cardRadius)
                }
            }
        }
        .padding(AstraSpacing.pagePadding)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading today's brief"))
    }

    private func skeletonBlock(width: CGFloat?, height: CGFloat, cornerRadius: CGFloat = AstraRadius.small) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AstraColor.surfaceElevated)
            .frame(width: width, height: height)
    }
}
