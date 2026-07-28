# 0001. Native SwiftUI (iOS-only) over React Native / Flutter

## Status

Accepted

## Context

Astra Style's core loop depends on a cluster of iOS-native capabilities:

- **Camera + Vision framework** for closet scanning: blur/exposure detection, garment
  segmentation, OCR of care labels, dominant-color extraction (§12).
- **StoreKit 2** for subscriptions with server-side reconciliation (§16).
- **WeatherKit** (or a server proxy) for the Daily Brief's weather context (§6.11).
- **EventKit** for occasion-aware recommendations (§6.8, §7).
- **AuthenticationServices** for Sign in with Apple, which is effectively mandatory
  given Apple's guideline requiring it alongside any other third-party login.
- A visual language (§3) built on system-safe serif/SF Pro pairing, matched-geometry
  hero transitions, and haptics that are cheapest to get right natively.

The team is building a single flagship platform first (iOS), with no committed
Android timeline. The question is whether to build on a cross-platform framework
(React Native, Flutter, KMP) now to keep an Android door open, or commit to native
Swift/SwiftUI.

## Decision

Build Astra Style as a native iOS app in Swift 6 / SwiftUI, targeting iOS 18+, with
no cross-platform abstraction layer. Every capability in §8's iOS stack (Vision,
AVFoundation, StoreKit 2, WeatherKit, EventKit, PhotosUI, UserNotifications) is used
directly, not through a bridge or plugin.

## Consequences

### Positive

- Direct access to Vision, AVFoundation, and StoreKit 2 without bridge latency,
  bridge bugs, or waiting on a third-party wrapper to catch up to a new OS release.
- `@Observable` + structured concurrency (ADR 0006) map cleanly onto SwiftUI with no
  interop shims.
- Full control over 120fps ProMotion animation, matched geometry, and haptics — the
  editorial feel in §3 is difficult to reproduce faithfully through a cross-platform
  rendering layer.
- Smaller binary, no JS engine or Flutter engine bundled, faster cold launch — makes
  the §20 "under 2.5s cold launch" target easier to hit.
- One platform's worth of App Store review surface and human-interface guidelines to
  reason about, not two.

### Negative (real costs, named)

- **No Android whatsoever at launch.** This is a real, permanent limitation, not a
  deferred nice-to-have: any Android-owning prospective user is simply unaddressable
  until a second codebase exists. That is a real ceiling on total addressable market.
- **A second codebase is the likely eventual cost.** If Android is ever pursued, nearly
  none of the SwiftUI view layer, the Vision-based scanning pipeline, or the StoreKit
  integration is reusable. Only the Supabase schema, Edge Functions, and prompt/data
  contracts (§14) survive platform-neutral. Expect a near-full rewrite of the client,
  not a port.
- Native-only means the iOS team cannot share UI engineers with a hypothetical web or
  Android team; hiring is narrower (Swift/SwiftUI specialists vs. generalist
  JS/TS engineers).
- Some features that cross-platform frameworks get "for free" via community plugins
  (e.g. certain camera UX libraries) must be hand-built here.

## Alternatives Considered

- **React Native.** Rejected because Vision framework segmentation, StoreKit 2's
  transaction API, and WeatherKit have no first-class RN bridges; the team would be
  maintaining native modules for exactly the capabilities that matter most, at which
  point RN adds indirection without removing native work. RN's bridge overhead also
  works against the matched-geometry, marble-texture, breathing-orb motion language
  in §3.
- **Flutter.** Rejected for the same reason: Flutter's platform channels would still
  require hand-written Swift for Vision/StoreKit/WeatherKit, and Flutter's custom
  renderer fights rather than uses UIKit/SwiftUI accessibility and Dynamic Type
  support, which §19 requires in full.
- **Kotlin Multiplatform (logic-sharing only, native UI per platform).** Deferred,
  not rejected outright — this is the most credible path *if* Android is ever
  greenlit, since it would let the compatibility-scoring and data-model logic be
  shared while keeping SwiftUI/Jetpack Compose UIs native. Not adopted now because
  there is no Android target to share it with yet, and introducing KMP's build
  tooling into a solo-platform project would be pure overhead today.
- **Web wrapper / PWA.** Rejected outright per §31 ("Do not substitute a generic
  template, web wrapper, or mock-only prototype") — camera-driven scanning and
  StoreKit subscriptions are not credible in a WebView.
