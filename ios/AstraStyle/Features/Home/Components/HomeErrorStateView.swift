//
//  HomeErrorStateView.swift
//  AstraStyle
//
//  Spec §21 "Recoverable error" + "Retry", applied to Home.
//

import SwiftUI

struct HomeErrorStateView: View {
    let error: AstraError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.md) {
            Spacer(minLength: AstraSpacing.xl)

            Image(systemName: iconName)
                .astraIcon(.display)
                .foregroundStyle(AstraColor.textMuted)
                .accessibilityHidden(true)

            Text(title)
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)

            Text(error.message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AstraSpacing.xl)

            Button(action: onRetry) {
                Text("Try Again")
            }
            .buttonStyle(.bordered)
            .padding(.top, AstraSpacing.sm)

            Spacer(minLength: AstraSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(AstraSpacing.pagePadding)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch error.category {
        case .network: String(localized: "You're offline")
        case .auth: String(localized: "Please sign in again")
        case .rateLimited: String(localized: "One moment")
        default: String(localized: "Something went wrong")
        }
    }

    private var iconName: String {
        switch error.category {
        case .network: "wifi.slash"
        case .auth: "lock"
        case .rateLimited: "hourglass"
        default: "exclamationmark.triangle"
        }
    }
}
