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

            // §22, "no dead buttons": `.unimplemented` means the endpoint
            // or table this screen needs has not been built, so retrying
            // cannot succeed — not now, not in an hour. Offering the
            // control anyway teaches the user that Astra's buttons don't
            // do anything. `AstraError.isRetryable` already draws exactly
            // this line, so read it rather than restating it here.
            if error.isRetryable {
                Button(action: onRetry) {
                    Text("Try Again")
                }
                .buttonStyle(.bordered)
                .padding(.top, AstraSpacing.sm)
            }

            // Correlates what he saw with the server-side log (spec §14).
            // Muted and unlabelled — it is there for the moment he sends a
            // screenshot, not for him to read.
            if let requestID = error.requestID {
                Text(verbatim: requestID)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.textMuted)
                    .textSelection(.enabled)
                    .padding(.top, AstraSpacing.sm)
                    .accessibilityLabel(Text("Reference code"))
            }

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
        case .unimplemented: String(localized: "Not ready yet")
        default: String(localized: "Something went wrong")
        }
    }

    private var iconName: String {
        switch error.category {
        case .network: "wifi.slash"
        case .auth: "lock"
        case .rateLimited: "hourglass"
        case .unimplemented: "hammer"
        default: "exclamationmark.triangle"
        }
    }
}
