//
//  LaundryAlertModuleView.swift
//  AstraStyle
//
//  Spec §6.11 secondary module: "Laundry/availability alert".
//

import SwiftUI

struct LaundryAlertModuleView: View {
    let itemCount: Int
    let onOpenCloset: () -> Void

    var body: some View {
        Button(action: onOpenCloset) {
            AstraCard {
                HStack(spacing: AstraSpacing.sm) {
                    Image(systemName: "washer")
                        .foregroundStyle(AstraColor.warningAmber)
                    Text(message)
                        .astraText(.callout)
                        .foregroundStyle(AstraColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .astraIcon(.disclosure)
                        .foregroundStyle(AstraColor.textMuted)
                }
                .padding(AstraSpacing.pagePadding)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(message))
        .accessibilityHint(Text("Opens your closet's laundry filter"))
    }

    private var message: String {
        String(localized: "^[\(itemCount) item](inflect: true) currently in the laundry", comment: "Laundry alert module")
    }
}
