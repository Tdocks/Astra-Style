//
//  TabNavigationStateTests.swift
//  AstraStyleTests
//
//  Phase 1 exit criterion: "Tapping each of the 5 tab bar items navigates
//  independently and preserves scroll/nav position when switching away and
//  back." (docs/01-build-roadmap.md)
//
//  The navigation half of that is a property of `AppRouter`: five separate
//  path arrays, owned above the `TabView`, each bound to its own
//  `NavigationStack`. Switching tabs changes `selectedTab` and nothing else,
//  so the stacks survive.
//
//  That is easy to state and easy to break — one shared `NavigationPath`, or
//  clearing a path in `onDisappear`, and every tab starts resetting itself.
//  These tests pin the behaviour so the regression is loud.
//

import Foundation
import Testing
@testable import AstraStyle

@MainActor
@Suite("Tab navigation state preservation (Phase 1 exit criterion)")
struct TabNavigationStateTests {
    @Test("Each tab owns a separate path, so pushing on one does not touch the others")
    func tabPathsAreIndependent() {
        let router = AppRouter()

        router.push(HomeRoute.outfitDetail(outfitID: UUID()))

        #expect(router.homePath.count == 1)
        #expect(router.closetPath.isEmpty)
        #expect(router.studioPath.isEmpty)
        #expect(router.discoverPath.isEmpty)
        #expect(router.profilePath.isEmpty)
    }

    @Test("Switching away from a tab and back preserves its navigation depth")
    func switchingTabsPreservesDepth() {
        let router = AppRouter()
        router.selectedTab = .home
        router.push(HomeRoute.outfitDetail(outfitID: UUID()))
        router.push(HomeRoute.alternativeLooks(briefID: UUID()))
        let depthBefore = router.homePath.count

        // Visit every other tab, then come back — the realistic version of
        // "switching away", not a single hop.
        for tab in [AppTab.closet, .studio, .discover, .profile, .home] {
            router.selectedTab = tab
        }

        #expect(router.selectedTab == .home)
        #expect(router.homePath.count == depthBefore)
        #expect(router.homePath.count == 2)
    }

    @Test("Two tabs can hold independent stacks at the same time")
    func tabsHoldConcurrentStacks() {
        let router = AppRouter()

        router.push(HomeRoute.alternativeLooks(briefID: UUID()))
        router.push(ClosetRoute.itemDetail(itemID: UUID()))
        router.push(ProfileRoute.privacyAndData)

        #expect(router.homePath.count == 1)
        #expect(router.closetPath.count == 1)
        #expect(router.profilePath.count == 1)
        #expect(router.studioPath.isEmpty)
        #expect(router.discoverPath.isEmpty)
    }

    @Test("Presenting and dismissing a modal leaves every tab stack untouched")
    func modalsDoNotDisturbTabStacks() {
        let router = AppRouter()
        router.push(HomeRoute.alternativeLooks(briefID: UUID()))
        router.push(ClosetRoute.itemDetail(itemID: UUID()))

        router.presentModal(.askKyra(.memories))
        router.dismissModal()

        #expect(router.homePath.count == 1)
        #expect(router.closetPath.count == 1)
        #expect(router.presentedModal == nil)
    }

    @Test("Signing out clears every tab stack, so the next user starts clean")
    func signOutResetsNavigation() {
        let router = AppRouter()
        router.push(HomeRoute.alternativeLooks(briefID: UUID()))
        router.push(ClosetRoute.itemDetail(itemID: UUID()))
        router.push(ProfileRoute.privacyAndData)

        router.resetForSignOut()

        // The inverse of preservation, and just as important: leaving one
        // user's navigation in place across a sign-out would show the next
        // account someone else's screens.
        #expect(router.homePath.isEmpty)
        #expect(router.closetPath.isEmpty)
        #expect(router.studioPath.isEmpty)
        #expect(router.discoverPath.isEmpty)
        #expect(router.profilePath.isEmpty)
        #expect(router.presentedModal == nil)
    }

    @Test("Any transition to signedOut resets navigation, not just an explicit sign-out call")
    func routeStateTransitionResetsNavigation() {
        let router = AppRouter()
        router.routeState = .main
        router.push(HomeRoute.alternativeLooks(briefID: UUID()))
        router.push(ClosetRoute.itemDetail(itemID: UUID()))

        // Simulates a server-side revocation rather than a button tap: nothing
        // called resetForSignOut(), the state simply changed.
        router.routeState = .signedOut

        #expect(router.homePath.isEmpty)
        #expect(router.closetPath.isEmpty)
        #expect(router.selectedTab == .home)
    }

    @Test("Routing between authenticated states leaves navigation alone")
    func nonSignedOutTransitionsPreserveNavigation() {
        let router = AppRouter()
        router.routeState = .onboarding
        router.push(HomeRoute.alternativeLooks(briefID: UUID()))

        router.routeState = .main

        // Only signing out should clear the stacks. Onboarding completing is
        // not a reason to throw away where the user was.
        #expect(router.homePath.count == 1)
    }

    @Test("startScan opens the scanner when the guest gate is off")
    func startScanPresentsScannerForSignedInUsers() {
        let router = AppRouter()
        router.blocksGuestScan = false

        router.startScan(mode: .batchCloset)

        guard case .scanner(let mode) = router.presentedModal else {
            Issue.record("Expected scanner modal for a signed-in startScan")
            return
        }
        #expect(mode == .batchCloset)
    }

    @Test("startScan opens create-account for guests, never the scanner")
    func startScanGatesGuestsBeforeScanner() {
        let router = AppRouter()
        router.blocksGuestScan = true

        router.startScan()

        guard case .createAccount(let reason) = router.presentedModal else {
            Issue.record("Expected create-account modal for a guest startScan")
            return
        }
        #expect(reason == .scanningRequiresAccount)
        // Inverse of the signed-in path: a guest who reaches a camera (or
        // today's placeholder) has already been sold a dead button.
        if case .scanner = router.presentedModal {
            Issue.record("Guest startScan must not present the scanner modal")
        }
    }
}
