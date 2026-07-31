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
//  Nothing here touches the scanner. `P3-SCAN-*` does not exist, and a step
//  that offered "scan instead" would be offering a control that cannot work.
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
        /// A guest at `GuestLimits.maxClosetItems` (spec §6.2; ADR 0011).
        /// Its own case rather than a `.failed` with a particular message,
        /// because it is a permanent state of this session that changes what
        /// the screen offers, not a transient error with a retry.
        case guestCapReached(limit: Int)
    }

    /// Whether the form currently describes an item worth writing.
    ///
    /// Name and category only. A colourless item is a real item — a man
    /// adding "Grandad's watch" should not have to invent a colour for it —
    /// and `primary_color` is nullable in the schema precisely because of
    /// cases like that.
    var canAddItem: Bool {
        guard case .guestCapReached = addItemState else {
            return !trimmedNewItemName.isEmpty && newItemCategory != nil
        }
        return false
    }

    var trimmedNewItemName: String {
        newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads the guest cap once, when the step opens.
    ///
    /// Only for a guest. A signed-in user's item count would need a full
    /// closet read to compute and would mean nothing — there is no cap to show
    /// him — so the call is not made at all rather than made and discarded.
    func prepareFirstItemsStep() async {
        guard await sessionStore.currentIsGuest() else {
            guestItemsRemaining = nil
            return
        }
        // Counts what is ALREADY in local guest storage, not just what this
        // session added. A guest who added items, quit, and resumed would
        // otherwise be told he has ten left while the repository refuses the
        // third — the app disagreeing with itself about its own rule.
        let existing = (try? await closetRepository.fetchItems().count) ?? firstItems.count
        let remaining = max(0, GuestLimits.maxClosetItems - existing)
        guestItemsRemaining = remaining
        if remaining == 0 {
            addItemState = .guestCapReached(limit: GuestLimits.maxClosetItems)
        }
    }

    /// Creates one real `closet_items` row (or one local guest item — the
    /// repository decides, see `GuestAwareClosetRepository`).
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
            if let remaining = guestItemsRemaining {
                let left = max(0, remaining - 1)
                guestItemsRemaining = left
                if left == 0 {
                    addItemState = .guestCapReached(limit: GuestLimits.maxClosetItems)
                }
            }
        } catch let error as GuestClosetError {
            // The typed guest failure exists so this call site can recognise
            // the cap without matching on a message string (see
            // `GuestLimits.swift`). Reaching it here rather than at the
            // pre-check means the boundary is enforced by the repository, and
            // this is only how the screen finds out.
            switch error {
            case .capReached(let limit):
                guestItemsRemaining = 0
                addItemState = .guestCapReached(limit: limit)
            }
        } catch {
            logger.error("createItem during onboarding failed: \(error.localizedDescription)")
            addItemState = .failed(error.localizedDescription)
        }
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
            if let remaining = guestItemsRemaining {
                guestItemsRemaining = min(GuestLimits.maxClosetItems, remaining + 1)
                if case .guestCapReached = addItemState { addItemState = .idle }
            }
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
        case .idle, .saving, .guestCapReached: break
        }
    }
}
