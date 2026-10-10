//
//  SliceViewModel.swift
//  AstraStyle
//
//  Drives `SliceView` (see `README.md` in this directory for what this
//  module is and why it's temporary). `@Observable` + `@MainActor` per
//  spec §8's state-management rules, exactly like `HomeViewModel`
//  (Features/Home), which this file patterns its state-enum style after:
//  an explicit state per screen concern (auth, garments, outfit
//  generation, mark-worn) rather than one giant enum, a separate
//  `isOffline` flag, and zero networking in this file — every operation
//  goes through `AuthRepository` / `ClosetRepository` / `OutfitRepository`
//  (Domain/Repositories) or `AppleSignInProviding` (Core/Auth).
//

import Foundation
import Observation

@MainActor
@Observable
public final class SliceViewModel {

    // MARK: - State

    public enum AuthPhase: Equatable, Sendable {
        case signedOut
        case signingIn
        case signedIn(userID: UUID)

        var signedInUserID: UUID? {
            if case .signedIn(let userID) = self { return userID }
            return nil
        }
    }

    /// Mirrors `HomeViewModel.ViewState`'s loading/loaded/empty/failed
    /// shape (Features/Home/ViewModels/HomeViewModel.swift).
    public enum GarmentsState: Equatable, Sendable {
        case loading
        case empty
        case loaded([ClosetItem])
        case failed(AstraError)

        var items: [ClosetItem] {
            if case .loaded(let items) = self { return items }
            return []
        }
    }

    public enum AddGarmentState: Equatable, Sendable {
        case idle
        case saving
        case failed(AstraError)
    }

    public enum OutfitState: Equatable, Sendable {
        case idle
        case generating
        case loaded(SliceOutfitDisplay)
        case failed(AstraError)
    }

    public enum MarkWornState: Equatable, Sendable {
        case idle
        case saving
        case saved
        case failed(AstraError)
    }

    public private(set) var authPhase: AuthPhase = .signedOut
    public private(set) var garmentsState: GarmentsState = .empty
    public private(set) var addGarmentState: AddGarmentState = .idle
    public private(set) var outfitState: OutfitState = .idle
    public private(set) var markWornState: MarkWornState = .idle

    /// Independent of every state above — offline is orthogonal to
    /// "what's on screen right now," matching `HomeViewModel.isOffline`.
    public private(set) var isOffline = false

    // Add-garment draft form fields, bound directly by `SliceView`.
    public var draftName: String = ""
    public var draftCategory: ClothingCategory = .top
    public var draftPrimaryColor: String = ""

    public var isSignedIn: Bool { authPhase.signedInUserID != nil }

    public var canGenerateOutfit: Bool {
        isSignedIn && !garmentsState.items.isEmpty && outfitState != .generating
    }

    // MARK: - Dependencies

    private let authRepository: AuthRepository
    private let closetRepository: ClosetRepository
    private let outfitRepository: OutfitRepository
    private let appleSignIn: AppleSignInProviding
    private let networkMonitor: NetworkReachabilityMonitoring

    public init(
        authRepository: AuthRepository,
        closetRepository: ClosetRepository,
        outfitRepository: OutfitRepository,
        appleSignIn: AppleSignInProviding,
        networkMonitor: NetworkReachabilityMonitoring = SystemNetworkReachabilityMonitor()
    ) {
        self.authRepository = authRepository
        self.closetRepository = closetRepository
        self.outfitRepository = outfitRepository
        self.appleSignIn = appleSignIn
        self.networkMonitor = networkMonitor
    }

    // MARK: - Session lifecycle

    /// Attempts to restore a previously-persisted session (Keychain-backed
    /// via `SessionStore.restoreSession()`), so relaunching mid-slice
    /// doesn't force a fresh sign-in every time. Call once from `.task {}`
    /// on the root view.
    public func restoreSessionIfNeeded() async {
        isOffline = await networkMonitor.isOffline()
        guard case .signedOut = authPhase else { return }
        do {
            if let session = try await authRepository.restoreSession() {
                authPhase = .signedIn(userID: session.userID)
                await loadGarments()
            }
        } catch {
            // No stored session, or refresh failed — a normal "not signed
            // in yet" outcome, not an error state, mirroring
            // `AstraStyleApp.bootstrap()`'s own handling of the same call.
            authPhase = .signedOut
        }
    }

    public func signInWithApple() async {
        guard case .signedOut = authPhase else { return }
        authPhase = .signingIn
        isOffline = await networkMonitor.isOffline()
        do {
            let result = try await appleSignIn.performSignIn()
            let session = try await authRepository.signInWithApple(
                identityToken: result.identityToken,
                nonce: result.rawNonce
            )
            authPhase = .signedIn(userID: session.userID)
            await loadGarments()
        } catch let error as AstraError where error.category == .cancelled {
            // User dismissed the Apple sheet — back to signed-out silently,
            // not an error state.
            authPhase = .signedOut
        } catch let error as AstraError {
            authPhase = .signedOut
            garmentsState = .failed(error)
        } catch {
            authPhase = .signedOut
            garmentsState = .failed(AstraError.auth(error.localizedDescription))
        }
    }

    public func signOut() async {
        try? await authRepository.signOut()
        authPhase = .signedOut
        garmentsState = .empty
        addGarmentState = .idle
        outfitState = .idle
        markWornState = .idle
        draftName = ""
        draftPrimaryColor = ""
    }

    // MARK: - Closet (spec: "manual add-garment form — no camera, no
    // Vision, no segmentation, no photo import")

    public func loadGarments() async {
        isOffline = await networkMonitor.isOffline()
        garmentsState = .loading
        do {
            let items = try await closetRepository.fetchItems()
            garmentsState = items.isEmpty ? .empty : .loaded(items)
        } catch let error as AstraError {
            garmentsState = .failed(error)
        } catch {
            garmentsState = .failed(AstraError.server(error.localizedDescription))
        }
    }

    public func addGarment() async {
        guard let userID = authPhase.signedInUserID else { return }

        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColor = draftPrimaryColor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            addGarmentState = .failed(AstraError.validation("Give the garment a name before saving."))
            return
        }

        addGarmentState = .saving
        let draft = ClosetItem(
            id: UUID(),
            userID: userID,
            name: trimmedName,
            category: draftCategory,
            primaryColor: trimmedColor.isEmpty ? nil : trimmedColor
        )

        do {
            let created = try await closetRepository.createItem(draft, images: [])
            garmentsState = .loaded([created] + garmentsState.items)
            draftName = ""
            draftPrimaryColor = ""
            addGarmentState = .idle
        } catch let error as AstraError {
            addGarmentState = .failed(error)
        } catch {
            addGarmentState = .failed(AstraError.server(error.localizedDescription))
        }
    }

    // MARK: - Outfit generation (real `POST /outfits/generate` Edge
    // Function — spec "deterministic/simplified scoring rule", not
    // `CompatibilityScorer`)

    public func generateOutfit() async {
        guard isSignedIn else { return }
        isOffline = await networkMonitor.isOffline()
        outfitState = .generating
        markWornState = .idle
        do {
            let recommendations = try await outfitRepository.generateOutfits(
                OutfitGenerationRequest(desiredCount: 1)
            )
            guard let recommendation = recommendations.first else {
                outfitState = .failed(
                    AstraError.validation(
                        "Kyra couldn't put together an outfit from what's in your closet yet. Add a top, a bottom, and a pair of shoes, then try again."
                    )
                )
                return
            }
            // `POST /outfits/generate` returns a transient recommendation —
            // it does not write to the database itself, so
            // `recommendation.id` isn't a real `outfits.id` yet. Persist it
            // now (outfits + outfit_items) so "Mark Worn" below has a real
            // row to reference: `outfit_wears.outfit_id` is a NOT NULL
            // foreign key with no ON DELETE SET NULL, and the wear-count
            // trigger needs `outfit_items` rows to bump anything at all.
            // See `LiveOutfitRepository.saveOutfit`'s doc comment.
            let savedOutfit = try await outfitRepository.saveOutfit(
                from: recommendation,
                name: nil,
                closetItems: garmentsState.items
            )
            outfitState = .loaded(
                SliceOutfitDisplay(outfitID: savedOutfit.id, recommendation: recommendation, closetItems: garmentsState.items)
            )
        } catch let error as AstraError {
            outfitState = .failed(error)
        } catch {
            outfitState = .failed(AstraError.server(error.localizedDescription))
        }
    }

    // MARK: - Mark worn (writes `outfit_wears`; `closet_items.wear_count`
    // is bumped server-side by the `bump_closet_item_wear_stats` trigger —
    // see README.md's schema note. Do NOT also increment it here.)

    public func markWorn() async {
        guard case .loaded(let outfit) = outfitState else { return }
        isOffline = await networkMonitor.isOffline()
        markWornState = .saving
        do {
            try await outfitRepository.recordWear(
                outfitID: outfit.id,
                wornAt: .now,
                occasion: nil,
                rating: nil,
                feedback: nil
            )
            markWornState = .saved
        } catch let error as AstraError {
            markWornState = .failed(error)
        } catch {
            markWornState = .failed(AstraError.server(error.localizedDescription))
        }
    }
}

/// View-friendly projection of `OutfitRecommendation` (the transient shape
/// `POST /outfits/generate` returns) resolved against the closet items the
/// view model already has in memory — the slice never has to make a
/// second network call just to render names/colors for the items in the
/// recommendation.
public struct SliceOutfitDisplay: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let reason: String
    public let compatibilityScore: Int
    public let items: [ClosetItem]
    /// Slots the generator wanted to fill but couldn't from the owned
    /// closet (`OutfitRecommendation.missingProductIDs`) — surfaced so the
    /// UI can be honest about a partial outfit rather than silently
    /// dropping the slot.
    public let missingItemCount: Int

    /// - Parameter outfitID: The **persisted** `outfits.id` (from
    ///   `OutfitRepository.saveOutfit`'s return value), not necessarily
    ///   `recommendation.id` — see `SliceViewModel.generateOutfit()` for
    ///   why those can, in principle, differ even though today's
    ///   `LiveOutfitRepository.saveOutfit` happens to reuse the
    ///   recommendation's id verbatim.
    init(outfitID: UUID, recommendation: OutfitRecommendation, closetItems: [ClosetItem]) {
        id = outfitID
        name = recommendation.name
        reason = recommendation.reason
        compatibilityScore = recommendation.compatibilityScore
        let itemsByID = Dictionary(uniqueKeysWithValues: closetItems.map { ($0.id, $0) })
        items = recommendation.itemIDs.compactMap { itemsByID[$0] }
        missingItemCount = recommendation.missingProductIDs.count
    }
}
