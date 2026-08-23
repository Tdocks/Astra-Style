//
//  PaywallView.swift
//  AstraStyle
//
//  Marble hero, two StoreKit prices, restore. Legal URLs omitted while
//  AstraLegal.isPublished is false — a 404 Terms link is review poison.
//

import SwiftUI

struct PaywallView: View {
    @State private var viewModel: PaywallViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PaywallViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    hero
                    plans
                    if case .failed(let message) = viewModel.state {
                        Text(message)
                            .astraText(.callout)
                            .foregroundStyle(AstraColor.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("paywall.error")
                    }
                    restoreButton
                    if viewModel.showsLegalLinks {
                        legal
                    }
                }
                .padding(AstraSpacing.pagePadding)
            }
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close", comment: "Dismisses the paywall")) {
                        dismiss()
                    }
                }
            }
            .task { await viewModel.onAppear() }
            .onChange(of: viewModel.state) { _, newState in
                if newState == .succeeded { dismiss() }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AstraMarble()
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous))
            VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                Text(viewModel.headline)
                    .astraText(.title2)
                    .foregroundStyle(AstraColor.textOnAccent)
                Text(viewModel.subhead)
                    .astraText(.callout)
                    .foregroundStyle(AstraColor.textOnAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AstraSpacing.md)
        }
        .accessibilityIdentifier("paywall.hero")
    }

    private var plans: some View {
        VStack(spacing: AstraSpacing.sm) {
            ForEach(viewModel.offerings) { offering in
                Button {
                    Task { await viewModel.purchase(offering.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: AstraSpacing.xxs) {
                            Text(offering.displayName)
                                .astraText(.headline)
                                .foregroundStyle(AstraColor.textPrimary)
                            Text(offering.displayPrice)
                                .astraText(.callout)
                                .foregroundStyle(AstraColor.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(AstraSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: AstraSize.minTapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: AstraRadius.card, style: .continuous)
                            .fill(AstraColor.surfaceElevated)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.state == .purchasing || viewModel.state == .loading)
                .accessibilityIdentifier("paywall.plan.\(offering.id.rawValue)")
            }
        }
    }

    private var restoreButton: some View {
        Button(String(localized: "Restore Purchases", comment: "Paywall restore")) {
            Task { await viewModel.restore() }
        }
        .buttonStyle(.astraSecondary)
        .disabled(viewModel.state == .purchasing)
        .accessibilityIdentifier("paywall.restore")
    }

    @ViewBuilder
    private var legal: some View {
        if let terms = AstraLegal.termsURL, let privacy = AstraLegal.privacyURL {
            HStack(spacing: AstraSpacing.md) {
                Link(String(localized: "Terms", comment: "Paywall terms"), destination: terms)
                Link(String(localized: "Privacy", comment: "Paywall privacy"), destination: privacy)
            }
            .astraText(.caption)
        }
    }
}
