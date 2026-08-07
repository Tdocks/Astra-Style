# 0014. An account is required; guest mode is removed

## Status

Accepted (2026-08-06). **Supersedes [0011](0011-guest-mode-and-account-migration.md).**

Amends spec §6.2 (the "Explore demo" action and the guest-mode restrictions
block) and §7 ("Guest migration to account"). The spec is the source of
truth in this repo, so those two passages are amended in
`docs/00-master-spec.md` by the same change that lands this ADR — not left
to disagree with the code.

## Context

The owner decided on 2026-08-06, in these words:

> "we will just change this to make an account necessary. no guest function."

It came up while scoping photo-first onboarding. That step needs the
scanner, and `GuestClosetRepository` refuses all three scan verbs by
design — ADR 0011's first decision is that guest photo bytes never reach
Supabase Storage. The options were:

1. Camera for signed-in users, typed form for guests. Two different
   onboarding experiences depending on a choice made one screen earlier.
2. An on-device-only analysis path for guests, using the Vision region/OCR/
   colour pass that already exists. Honest and ADR-0011-compatible, but it
   is a second analysis implementation, a second image store, and a second
   set of results to reconcile at migration.
3. Remove guest mode.

He chose 3.

### What guest mode actually delivered

ADR 0011 rejected "no guest mode at all" on the grounds that it "removes a
meaningful low-friction trial path for a premium app that benefits from
letting a skeptical user try scanning before committing to an account."

**That trial path was never reachable.** A guest cannot scan — the verbs
throw. A guest gets `.guestPreview` instead of a Style DNA. A guest's Daily
Brief is built from local state with no outfit in it, because outfit
generation is a server capability. What a guest could actually do was browse
an empty closet and type up to ten garments by hand. The friction guest mode
saved was real; what it bought was not the thing 0011 was defending.

### What it cost

- **Three separate bugs** where a guest session reached Supabase anyway,
  each caught late because the failure mode is a silent 401/403 rather than
  a crash.
- **A fourth, found 2026-08-06 and inverted:** §6.11's "add five pieces"
  empty state was reachable *only* by guests, because the signed-in path
  derived it from data a network call returns. Every real user got an error
  screen where the spec calls for an invitation. Guest mode was carrying the
  correct behaviour, and the branch structure hid that the other path had
  none.
- **A migration surface that was never built.** 0011's own Consequences
  section says onboarding answers — style, body, and lifestyle profiles —
  "must also be captured locally during guest onboarding and migrated, not
  just closet scans, or a user who completes onboarding as a guest and then
  signs in loses their onboarding answers." `LiveGuestMigrationService`
  migrates closet items. It does not migrate any profile table. So the
  documented data-loss bug has been live for as long as the feature has.
- **A permanent tax on every write path.** `GuestAwareClosetRepository` is
  the type `AppContainer` injects everywhere, so every closet call in the
  app routes through a guest check that is about to be false for everyone.

## Decision

1. **Authentication is required before onboarding.** §6.2 offers Sign in
   with Apple and Continue with Email. The third action is removed.
2. **The guest subsystem is deleted, not disabled.** `GuestClosetRepository`,
   `GuestAwareClosetRepository`, `GuestClosetStore` and both its
   implementations, `GuestMigrationService` and `LiveGuestMigrationService`,
   `GuestProfileView`/`GuestProfileViewModel`, `GuestLimits`,
   `AuthSession.isGuest`, `SessionStore.isGuest`, and
   `AppRouter.blocksGuestScan` all go. A feature flag would leave every
   guest branch in place as untested code that still has to compile and
   still has to be reasoned about at each call site.
3. **The tests that pinned guest behaviour are deleted with it.**
   `GuestModeNetworkTests`, `GuestClosetRepositoryTests`,
   `GuestMigrationServiceTests` and the guest halves of
   `HomeBriefProvidingTests` and the onboarding suites exist to assert
   properties of a feature that will not exist. Keeping them disabled would
   make the suite describe an app that isn't there.
4. **Nothing about the free tier changes.** `FreeTierLimits` and
   `FreeTierCappedClosetRepository` are a separate concern — a cap on a
   *signed-in* user's closet — and stay exactly as they are. The two were
   easy to confuse because both capped a closet.

## Consequences

- **Sign-up friction moves to the first screen.** This is the real cost and
  it is not small: a skeptical user now decides about an account before
  seeing anything but the welcome screen. Sign in with Apple is offered
  first and is close to a two-tap account, which is the main thing that
  makes this survivable.
- **App Store review, guideline 5.1.1(v).** Apps may not require
  registration unless account-based features are core to the app. Astra's
  are: the wardrobe is stored server-side, and every AI capability is an
  Edge Function behind a JWT. There is no version of this app that works
  without an account, which is the argument to make if review asks. Worth
  knowing the question is coming rather than being surprised by it.
- **`AppContainer` injects `LiveClosetRepository` (behind the free-tier
  cap) directly.** One fewer wrapper, and every closet call path loses a
  branch.
- **Deleted code is recoverable from git, and this ADR is where to start.**
  If the funnel argues for a trial path later, the thing to build is almost
  certainly not what was deleted — see below.

## Alternatives Considered

- **Keep guest mode and give guests an on-device-only scan.** The most
  interesting option, and genuinely ADR-0011-compatible: the whole device
  Vision pass (`DeviceHintsExtraction`, `DominantColorExtraction`,
  `LiveVisionGarmentRegionDetector`, `LiveVisionLabelTextRecognizer`)
  already exists and could prefill category and colour with zero network
  I/O. Rejected because it needs a local guest image store that does not
  exist, a migration path for those bytes at sign-up, and it leaves two
  analysis implementations whose results have to agree well enough that a
  garment does not visibly change when the user creates an account.
- **Feature-flag guest mode off and keep the code.** Rejected per decision
  2: the branches stay, still compile, still need reasoning about, and are
  now untested. This codebase tracks gaps as named disabled tests rather
  than dead code, and dead *branches* are worse than dead tests.
- **Supabase anonymous auth (`signInAnonymously`).** 0011 considered and
  rejected this, and the reasoning still holds — a server-side identity for
  every guest, including the large majority who never convert. If a trial
  path is ever wanted again, this is the one to revisit, because it makes
  "migration" an identity-link call rather than a re-upload, which is where
  most of guest mode's real complexity lived.
