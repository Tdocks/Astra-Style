//
//  HomeEmptyStateView.swift
//  AstraStyle
//
//  Spec §6.11's empty state, split three ways.
//
//  §21's example copy — "Add five pieces and Kyra can begin building real
//  outfits." — is verbatim and still right, but only for the case it was
//  written about. It used to be the ONLY case, and it was read by a man with
//  fifteen garments who had photographed fifteen shirts: the engine built
//  zero outfits, correctly, and the screen told him he owned almost nothing.
//  Following the advice would not have changed the screen.
//
//  The rule this screen now keeps: say the thing that is actually in the way.
//

import SwiftUI

struct HomeEmptyStateView: View {
    let reason: HomeBriefData.EmptyReason
    let onScanItem: () -> Void

    var body: some View {
        VStack(spacing: AstraSpacing.md) {
            Spacer(minLength: AstraSpacing.xl)

            Image(systemName: "hanger")
                .astraIcon(.display)
                .foregroundStyle(AstraColor.accentChampagne)
                .accessibilityHidden(true)

            Text(title)
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .astraText(.body)
                .foregroundStyle(AstraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AstraSpacing.xl)

            AstraButton(title: callToAction, action: onScanItem)
                .padding(.top, AstraSpacing.sm)

            Spacer(minLength: AstraSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(AstraSpacing.pagePadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.empty")
    }

    private var title: String {
        switch reason {
        case .tooFewItems:
            String(localized: "Let's build your first look", comment: "Home empty state title")
        case .missingRoles:
            String(localized: "Almost there", comment: "Home empty state title, a role is missing")
        case .noOutfitYet:
            String(localized: "No look for today yet", comment: "Home empty state title, nothing scored")
        }
    }

    /// `ClothingCategory.displayName` is already plural and capitalised
    /// ("Tops", "Bottoms", "Shoes"), so these sentences are built to read
    /// with capitals mid-phrase rather than lowercasing a localised noun,
    /// which is not a safe transform in every language this may ship in.
    private var message: String {
        switch reason {
        case .tooFewItems:
            // §21's copy, verbatim, for the case §21 was describing.
            String(localized: "Add five pieces and Kyra can begin building real outfits.",
                   comment: "Home empty state, closet under the minimum")
        case .missingRoles(let roles):
            String(
                localized: "Your closet has \(list(present(excluding: roles))). Kyra needs \(list(roles)) too before she can put a look together.",
                comment: "Home empty state naming the garment roles the closet is missing"
            )
        case .noOutfitYet:
            String(
                localized: "Everything Kyra needs is in your closet, but nothing came together today. Check what's in the wash, or add a piece.",
                comment: "Home empty state, closet complete but no outfit scored"
            )
        }
    }

    private var callToAction: String {
        switch reason {
        case .tooFewItems:
            String(localized: "Scan Your First Item", comment: "Home empty state CTA")
        case .missingRoles(let roles):
            // Naming what to go and photograph, because "Scan an Item" is
            // exactly what he has already been doing.
            String(localized: "Add \(list(roles))", comment: "Home empty state CTA naming the missing roles")
        case .noOutfitYet:
            String(localized: "Add a Piece", comment: "Home empty state CTA")
        }
    }

    /// What he DOES own, said back to him first. A screen that lists only
    /// absences reads as a scolding; leading with the shirts he actually
    /// photographed is what makes "and now some trousers" land as progress.
    private func present(excluding missing: [ClothingCategory]) -> [ClothingCategory] {
        HomeBriefData.requiredRoles.filter { !missing.contains($0) }
    }

    private func list(_ roles: [ClothingCategory]) -> String {
        let names = roles.map(\.displayName)
        switch names.count {
        case 0:
            return String(localized: "a start", comment: "Home empty state, no required role present")
        case 1:
            return names[0]
        case 2:
            return String(localized: "\(names[0]) and \(names[1])", comment: "Two garment roles")
        default:
            let head = names.dropLast().joined(separator: ", ")
            return String(localized: "\(head) and \(names[names.count - 1])",
                          comment: "Three or more garment roles")
        }
    }
}
