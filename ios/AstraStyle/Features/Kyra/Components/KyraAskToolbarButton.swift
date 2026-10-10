//
//  KyraAskToolbarButton.swift
//  AstraStyle
//
//  The Ask Kyra action used by detail screens whose bottom controls would
//  otherwise sit underneath the global floating button.
//

import SwiftUI

struct KyraAskToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AstraColor.surfaceElevated)
                Circle()
                    .strokeBorder(AstraColor.accentChampagneAccessible, lineWidth: 1)
                AstraMonogram(size: AstraSpacing.lg)
            }
            .frame(width: AstraSize.minTapTarget, height: AstraSize.minTapTarget)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "Ask Kyra", comment: "Opens the Kyra conversation")))
        .accessibilityIdentifier("kyra.ask.toolbar")
    }
}
