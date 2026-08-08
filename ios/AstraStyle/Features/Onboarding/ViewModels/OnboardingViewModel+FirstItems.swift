//
//  OnboardingViewModel+FirstItems.swift
//  AstraStyle
//
//  §5.1 step 12 — "add first closet items, or skip".
//
//  THE MOST IMPORTANT PROPERTY OF THIS FILE IS WHAT IT CANNOT DO: it cannot
//  stop the user leaving. Nothing here is reachable from `canAdvance`, nothing
//  here sets a state the scaffold's forward button reads, and every failure
//  mode below resolves to a message beside the form rather than to a blocked
//  step. "Skipping does not block reaching Home" is a Phase 2 exit criterion,
//  and the cheapest way to keep it true is to give this step no way to say no.
//
//  WHY THE FORM IS THIS SMALL. Three fields — name, category, colour — out of
//  the thirty-odd on `ClosetItem`. This is a man's first minute in the app, one
//  screen before he sees his Style DNA, and the §10 wardrobe graph needs
//  category and colour to say anything at all; everything else (brand,
//  material, formality, purchase price, seasonality) sharpens a recommendation
//  rather than enabling one. `P3-CLOSET-08` owns the full editor, and building
//  a second one here would guarantee the two drift.
//
//  THE SCANNER IS NOW REACHABLE FROM HERE, and it did not used to be. This
//  header said "nothing here touches the scanner; a step that offered 'scan
//  instead' would be offering a control that cannot work" — true while the
//  `closet` Edge Function was undeployed, false since it shipped. The photo
//  path does not live in this file: the sheet is presented by
//  `OnboardingFlowView` and the write is made by `ScannerReviewViewModel`
//  through the same `ClosetRepository` this file uses. All that arrives here
//  is `didScanItem(_:)`, a garment that already exists.
//
//  The typed form below stays, and is not a fallback for a missing camera —
//  the scanner degrades to a Photos import on its own. It stays because a man
//  can own a garment he cannot photograph right now: it is at the cleaners, it
//  is in a suitcase, he is on a train. Removing it would make the step
//  conditional on where he is standing.
//

import Foundation

public extension OnboardingViewModel {

    /// The §5.1 step 12 add-item form's state. Separate from
    /// `SubmissionState` because it describes one write of one garment, can
    /// fail and be retried without touching the rest of the flow, and must
    /// never be able to leave the whole step in an error state — the step is
    /// skippable and blocking it would break Phase 2's exit criterion.
    enum AddItemState: Equatable {
        case idle
        case saving
        /// The most recent add succeeded. Carries the name so the confirmation
        /// can say WHICH item landed rather than "Saved".
        case added(name: String)
        case failed(String)
        /// The free-tier closet cap (spec §16), refused by
        /// `FreeTierCappedClosetRepository`. Its own case rather than a
        /// `.failed` with a particular message, because it is a state that
        /// changes what the screen offers, not a transient error with a
        /// retry.
        case capReached(limit: Int)
    }

    /// Whether the form currently describes an item worth writing.
    ///
    /// Name and category only. A colourless item is a real item — a man
    /// adding "Grandad's watch" should not have to invent a colour for it —
    /// and `primary_color` is nullable in the schema precisely because of
    /// cases like that.
    var canAddItem: Bool {
        guard case .capReached = addItemState else {
            return !trimmedNewItemName.isEmpty && newItemCategory != nil
        }
        return false
    }

    var trimmedNewItemName: String {
        newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nothing to prepare any more.
    ///
    /// This used to read the guest cap so the step could show how many of
    /// ten local items were left. Guest mode is gone (ADR 0014) and the
    /// free-tier cap is 30 on a signed-in closet, enforced by
    /// `FreeTierCappedClosetRepository` and surfaced when a write is
    /// actually refused — a remaining-count on this screen would be a
    /// number about a limit nobody is near in their first minute.
    func prepareFirstItemsStep() async {}

    /// Creates one real `closet_items` row.
    ///
    /// The item is built with `laundryState: .clean` and no wear history
    /// because that is what "I own this" means on the day you say it; the
    /// alternative is a nil-riddled row that every downstream reader has to
    /// special-case.
    func addFirstItem() async {
        guard canAddItem, let category = newItemCategory else { return }
        guard let userID = await currentUserID() else {
            addItemState = .failed(
                String(localized: "You need to be signed in to save this.",
                       comment: "Onboarding submission error")
            )
            return
        }

        let name = trimmedNewItemName
        let color = newItemColor.trimmingCharacters(in: .whitespacesAndNewlines)
        addItemState = .saving

        let item = ClosetItem(
            id: UUID(),
            userID: userID,
            name: name,
            category: category,
            primaryColor: color.isEmpty ? nil : color
        )

        do {
            let created = try await closetRepository.createItem(item, images: [])
            firstItems.insert(created, at: 0)
            newItemName = ""
            newItemCategory = nil
            newItemColor = ""
            addItemState = .added(name: created.name)
            AstraHaptics.success()
        } catch let error as FreeTierClosetError {
            // The typed failure exists so this call site can recognise the
            // cap without matching on a message string. Reaching it here
            // rather than at a pre-check means the boundary is enforced by
            // the repository, and this is only how the screen finds out.
            switch error {
            case .capReached(let limit):
                addItemState = .capReached(limit: limit)
            }
        } catch {
            logger.error("createItem during onboarding failed: \(error.localizedDescription)")
            addItemState = .failed(error.localizedDescription)
        }
    }

    /// Records a garment the embedded scanner has already created.
    ///
    /// This writes nothing. `ScannerReviewViewModel.save()` has been through
    /// `ClosetRepository.createItem` by the time this is called, and `item` is
    /// the repository's return value — the server's normalisation of the
    /// garment, not the draft the review screen was holding. Re-saving it here
    /// would create a second row for one photograph.
    ///
    /// It exists because this step's list is what THIS step added, not what
    /// the user owns (see `firstItems`). Without being told, a garment scanned
    /// through the sheet would be genuinely saved and entirely invisible on
    /// the screen that asked for it — and `stepHasAnyAnswer` would still call
    /// the step untouched, so the footer would go on offering "Skip for now"
    /// after the user had done the thing.
    ///
    /// Guarded on `id` because presenting the sheet and dismissing it are
    /// separate events: a completion delivered twice must not list one garment
    /// twice.
    func didScanItem(_ item: ClosetItem) {
        guard !firstItems.contains(where: { $0.id == item.id }) else { return }
        firstItems.insert(item, at: 0)
        // Deliberately the same confirmation the typed form gets. Two ways in,
        // one way of saying it landed — and it names the garment, so a man who
        // scanned a jacket and reads "Navy field jacket is in your closet" can
        // tell the analysis got the right thing without opening it.
        addItemState = .added(name: item.name)
        AstraHaptics.success()
    }

    /// Undoes one add. Archives rather than hard-deletes, matching
    /// `ClosetRepository`'s only removal verb (spec §9's soft deletion).
    ///
    /// Offered because the alternative is a man who mistyped a garment name in
    /// his first minute carrying it in his closet until he finds the closet
    /// screen — which does not exist yet.
    func removeFirstItem(_ item: ClosetItem) async {
        do {
            try await closetRepository.archiveItem(id: item.id)
            firstItems.removeAll { $0.id == item.id }
            if case .capReached = addItemState { addItemState = .idle }
        } catch {
            logger.error("archiveItem during onboarding failed: \(error.localizedDescription)")
            addItemState = .failed(error.localizedDescription)
        }
    }

    /// Clears a transient message so the form stops shouting about the last
    /// thing that happened while the user types the next one.
    func acknowledgeAddItemState() {
        switch addItemState {
        case .added, .failed: addItemState = .idle
        case .idle, .saving, .capReached: break
        }
    }
}
