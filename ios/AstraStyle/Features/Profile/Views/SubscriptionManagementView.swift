//
//  SubscriptionManagementView.swift
//  AstraStyle
//
//  Profile's subscription destination and StoreKit restore entry point.
//

import SwiftUI

struct SubscriptionManagementView: View {
    @State private var viewModel: SubscriptionManagementViewModel
    @Environment(AppRouter.self) private var router

    init(viewModel: SubscriptionManagementViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                switch viewModel.phase {
                case .loading:
                    loadingState
                case .ready(let subscription):
                    subscriptionCard(subscription)
                    actions(subscription)
                case .failed(let message):
                    failureState(message)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(String(localized: "Subscription", comment: "Subscription management title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.retry() }
    }

    private var loadingState: some View {
        HStack(spacing: AstraSpacing.sm) {
            ProgressView().tint(AstraColor.accentChampagne)
            Text(String(localized: "Checking your plan.", comment: "Subscription loading state"))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subscriptionCard(_ subscription: Subscription) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                HStack(spacing: AstraSpacing.md) {
                    Image(systemName: subscription.isEntitledToPremium ? "crown.fill" : "person.crop.circle")
                        .astraIcon(.emphasis)
                        .foregroundStyle(AstraColor.accentChampagneAccessible)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                        Text(planName(subscription))
                            .astraText(.headline)
                            .foregroundStyle(AstraColor.textPrimary)
                        Text(statusName(subscription.status))
                            .astraText(.callout)
                            .foregroundStyle(subscription.isEntitledToPremium ? AstraColor.accentChampagneAccessible : AstraColor.textSecondary)
                    }
                }
                if let expiresAt = subscription.expiresAt {
                    Text(expirationText(for: subscription, at: expiresAt))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textSecondary)
                }
                if subscription.environment == .sandbox {
                    Text(String(localized: "Sandbox purchase", comment: "Subscription sandbox environment note"))
                        .astraText(.caption)
                        .foregroundStyle(AstraColor.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("profile.subscription.status")
        }
    }

    @ViewBuilder
    private func actions(_ subscription: Subscription) -> some View {
        VStack(spacing: AstraSpacing.sm) {
            if subscription.isEntitledToPremium {
                if let manageURL = URL(string: "https://apps.apple.com/account/subscriptions") {
                    Link(destination: manageURL) {
                        Label(
                            String(localized: "Manage with Apple", comment: "Opens Apple's subscription management page"),
                            systemImage: "arrow.up.right.square"
                        )
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                    }
                    .buttonStyle(.astraSecondary)
                    .accessibilityIdentifier("profile.subscription.manage")
                }
            } else {
                Button(String(localized: "Explore Premium", comment: "Opens the Premium paywall from Profile")) {
                    router.presentModal(.paywall(context: .settingsUpgrade))
                }
                .buttonStyle(.astraPrimary)
                .accessibilityIdentifier("profile.subscription.upgrade")
            }

            Button {
                Task { await viewModel.restore() }
            } label: {
                if viewModel.isRestoring {
                    ProgressView()
                        .tint(AstraColor.accentChampagne)
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                } else {
                    Text(String(localized: "Restore Purchases", comment: "Restores App Store subscriptions"))
                        .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                }
            }
            .buttonStyle(.astraSecondary)
            .disabled(viewModel.isRestoring)
            .accessibilityIdentifier("profile.subscription.restore")
            if let restoreError = viewModel.restoreError {
                Text(restoreError)
                    .astraText(.caption)
                    .foregroundStyle(AstraColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("profile.subscription.restoreError")
            }
        }
    }

    private func failureState(_ message: String) -> some View {
        AstraCard {
            VStack(alignment: .leading, spacing: AstraSpacing.md) {
                Text(message)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textSecondary)
                Button(String(localized: "Try again", comment: "Retry subscription status load")) {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.astraSecondary)
                .accessibilityIdentifier("profile.subscription.retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func planName(_ subscription: Subscription) -> String {
        switch subscription.productID {
        case AstraProductID.monthly.rawValue:
            String(localized: "Astra Style Premium · Monthly", comment: "Monthly Premium plan")
        case AstraProductID.annual.rawValue:
            String(localized: "Astra Style Premium · Annual", comment: "Annual Premium plan")
        default:
            if subscription.isEntitledToPremium {
                String(localized: "Astra Style Premium", comment: "Premium plan")
            } else {
                String(localized: "Free plan", comment: "Free subscription plan")
            }
        }
    }

    private func statusName(_ status: SubscriptionStatus) -> String {
        switch status {
        case .trialing: String(localized: "Free trial", comment: "Subscription status")
        case .active: String(localized: "Active", comment: "Subscription status")
        case .inGracePeriod: String(localized: "Billing grace period", comment: "Subscription status")
        case .inBillingRetry: String(localized: "Billing retry", comment: "Subscription status")
        case .expired: String(localized: "Expired", comment: "Subscription status")
        case .revoked: String(localized: "Revoked", comment: "Subscription status")
        case .cancelled: String(localized: "Cancelled", comment: "Subscription status")
        }
    }

    private func expirationText(for subscription: Subscription, at date: Date) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        if subscription.isEntitledToPremium {
            return String(localized: "Premium access through \(formatted)", comment: "Subscription access end date")
        }
        return String(localized: "Access ended on \(formatted)", comment: "Expired subscription date")
    }
}
