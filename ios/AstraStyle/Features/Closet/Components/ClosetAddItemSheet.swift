//
//  ClosetAddItemSheet.swift
//  AstraStyle
//
//  The modal wrapper that turns `ClosetItemFormView` into the Closet tab's
//  manual add path (spec §6.14 header, ticket P3-CLOSET-08).
//
//  WHY THIS EXISTS AT ALL, RATHER THAN A `.sheet` CLOSURE.
//
//  `ClosetViewModel.makeAddItemViewModel()` builds a fresh form view model
//  and wires its `onSaved` so the new garment folds straight into the
//  loaded closet. A `.sheet { ClosetItemFormView(viewModel: vm.make…()) }`
//  would call that factory again on every re-evaluation of the enclosing
//  body, discarding whatever the man had typed each time the closet
//  behind the sheet changed. Holding the view model in `@State`,
//  initialised exactly once from the factory, is what makes the draft
//  survive — and `@State`'s initialiser is the only place SwiftUI
//  guarantees to run once, which is why this is a view and not a closure.
//
//  WHY THE SHEET OWNS DISMISSAL AND THE FORM DOES NOT.
//
//  `ClosetItemFormView` deliberately renders its own in-content header and
//  sets no `navigationTitle` or toolbar, because it is also presented from
//  the item-detail screen as the edit surface. A view that dismissed
//  itself would have to know which of those two presentations it was in.
//  So the presenter supplies the chrome: this file adds the Cancel button
//  and closes on save; the detail screen adds its own.
//
//  `onSaved` IS CHAINED, NOT REPLACED. The factory already installed a
//  handler that inserts the row into the closet. Assigning a fresh closure
//  here would silently drop it and the man would save a garment, watch the
//  sheet close, and find the closet unchanged — a bug that looks exactly
//  like a failed write while the row sits in the database.
//

import SwiftUI

/// Presents the manual garment form modally over the Closet.
struct ClosetAddItemSheet: View {
    /// Called once, by `@State`, to build the form's view model. Not a
    /// value, because a value would be rebuilt with the enclosing body.
    let makeViewModel: () -> ClosetItemFormViewModel

    /// Invoked when the sheet should close — on save, and on Cancel.
    let onFinished: () -> Void

    @State private var viewModel: ClosetItemFormViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ClosetItemFormView(viewModel: viewModel)
                } else {
                    // Unreachable in practice: `.task` runs before the
                    // first frame the user can act on. Rendered as the
                    // screen's own background rather than a spinner so
                    // the sheet does not flash a loading state for a
                    // form that loads nothing.
                    AstraColor.backgroundPrimary
                }
            }
            .background(AstraColor.backgroundPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Closes the add-garment sheet without saving")) {
                        onFinished()
                    }
                }
            }
        }
        .task {
            guard viewModel == nil else { return }
            let form = makeViewModel()
            let existing = form.onSaved
            form.onSaved = { item in
                existing?(item)
                onFinished()
            }
            viewModel = form
        }
    }
}
