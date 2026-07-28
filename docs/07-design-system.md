# 07 — Design System

Implementation of spec §3 (Design System) as Swift/SwiftUI code under
`ios/AstraStyle/Core/DesignSystem/`. This document covers the token → Swift mapping, usage
rules, a WCAG contrast analysis, and a component inventory.

**Verification status:** no Swift toolchain (`swift`/`swiftc`/`xcodebuild`) is available in this
environment, so none of this code has been compiled. Every file was re-read carefully for
syntax and iOS 18 API correctness instead. See the bottom of this document for a list of the
non-obvious API choices made to keep things compiling under Swift 6 strict concurrency.

---

## 1. Token → Swift mapping

| Spec token (§3) | Swift symbol | Dark hex | Light hex |
|---|---|---|---|
| `backgroundPrimary` | `AstraColor.backgroundPrimary` | `#0D0D0D` | `#F8F5EF` |
| `backgroundSecondary` | `AstraColor.backgroundSecondary` | `#151515` | `#EFEAE1` |
| `surfaceElevated` | `AstraColor.surfaceElevated` | `#1B1B1B` | `#FFFFFF` |
| `surfaceMarble` | `AstraColor.surfaceMarble` | asset-based (placeholder: `backgroundPrimary`) | same |
| `textPrimary` | `AstraColor.textPrimary` | `#F7F3EA` | `#111111` |
| `textSecondary` | `AstraColor.textSecondary` | `#B9B3A8` | `#56514B` |
| `textMuted` | `AstraColor.textMuted` | `#77736C` | `#8C867D` |
| `accentChampagne` | `AstraColor.accentChampagne` | `#D7B46A` | `#B8914E` |
| `accentChampagnePressed` | `AstraColor.accentChampagnePressed` | `#B8944D` | `#9C7B42`* |
| — (new, not in spec) | `AstraColor.accentChampagneAccessible` | `#D7B46A` | `#8A6A2E`* |
| — (new, not in spec) | `AstraColor.textOnAccent` | `#14110A` (fixed) | `#14110A` (fixed) |
| `divider` | `AstraColor.divider` | `#2A2927` | `#DDD6CB` |
| `successOlive` | `AstraColor.successOlive` | `#69745D` | `#4E5744`* |
| `warningAmber` | `AstraColor.warningAmber` | `#A98652` | `#7E6339`* |
| `destructive` | `AstraColor.destructive` | `#B65F59` | `#9B4F4A`* |

`*` = value not given by spec §3 (light mode only lists `backgroundPrimary`, `backgroundSecondary`,
`surfaceElevated`, `textPrimary`, `textSecondary`, `textMuted`, `accentChampagne`, `divider`).
These are design decisions made to fill the gap — see §4 below.

Every token is backed by `AstraColorToken`, a light/dark hex pair resolved to a single `Color`
via a `UIColor` dynamic provider keyed off `UITraitCollection.userInterfaceStyle`. This means
**a single token name works correctly in both light and dark mode automatically** — no
`@Environment(\.colorScheme)` check needed at call sites.

| Spec text style (§3) | Swift symbol | Size | Design | Weight | Dynamic Type anchor |
|---|---|---|---|---|---|
| `displayXL` | `.astraText(.displayXL)` | 42 | serif | semibold | `.largeTitle` |
| `displayL` | `.astraText(.displayL)` | 34 | serif | semibold | `.largeTitle` |
| `title1` | `.astraText(.title1)` | 28 | serif | regular* | `.title` |
| `title2` | `.astraText(.title2)` | 22 | serif | regular* | `.title2` |
| `headline` | `.astraText(.headline)` | 17 | sans | semibold | `.headline` |
| `body` | `.astraText(.body)` | 16 | sans | regular | `.body` |
| `callout` | `.astraText(.callout)` | 15 | sans | regular | `.callout` |
| `caption` | `.astraText(.caption)` | 12 | sans | regular | `.caption` |
| `micro` | `.astraText(.micro)` | 10 | sans | semibold*, **uppercase, tracking 1.5** | `.caption2` |

`*` = weight not specified by spec §3 for `title1`/`title2`/`micro`; filled in as a design
decision (§4).

Serif styles use `.system(size:weight:design:.serif)`, which resolves to **New York** on iOS.
Sans styles use `.system(size:weight:design:.default)`, i.e. **SF Pro**.

**Dynamic Type:** `Font.system(size:)` alone does not scale with the user's text size setting.
`AstraTextStyleModifier` drives the point size through `@ScaledMetric(wrappedValue: baseSize,
relativeTo: relativeTextStyle)`, so every style grows/shrinks along the same curve iOS uses for
its closest built-in text style, satisfying spec §19 ("Full Dynamic Type support").

| Spec layout constant (§3) | Swift symbol | Value |
|---|---|---|
| Base spacing unit | `AstraSpacing.unit` | 4 pt |
| — | `AstraSpacing.xxs` … `.xxxl` | 4, 8, 12, 16, 20, 24, 32, 40 pt |
| Standard page padding | `AstraSpacing.pagePadding` (`= .lg`) | 20 pt |
| Card corner radius | `AstraRadius.card` | 18 pt |
| Button corner radius | `AstraRadius.button` | 14 pt |
| Compact chip radius | `AstraRadius.chip` | capsule |
| Minimum tap target | `AstraSize.minTapTarget` | 44 × 44 pt |

| Spec motion (§3) | Swift symbol |
|---|---|
| Standard transition, 220 ms ease-in-out | `AstraMotion.standard` |
| Outfit alternatives spring paging | `AstraMotion.outfitPaging` |
| Kyra orb breathing animation | `AstraMotion.breathing` |
| Reduce Motion wrapper | `AstraMotion.aware(_:reduceMotion:)`, `View.astraAnimation(_:value:)` |
| Haptics: selection / success / warning | `AstraHaptics.selection() / .success() / .warning()` |

---

## 2. Usage rules

### Marble

Per spec §3, marble is **a brand texture, not a universal background**. `AstraColor.surfaceMarble`
exists so call sites can reference it now, but it currently **degrades to `backgroundPrimary`**
until the real marble asset (see `/tmp/astra/brand/assets/app-icon-marble.jpg`) is added to the
asset catalog. When it ships, swap the token's implementation for an image-backed fill —
do not repoint call sites.

Sanctioned marble surfaces (do not expand this list without a design review):

- Splash screen.
- App icon.
- Paywall hero.
- Select premium cards (e.g. a Style Journey milestone card).
- Kyra transition surfaces (e.g. a full-screen Kyra "thinking" transition).

**Never place marble behind dense text** — its high-frequency veining destroys legibility for
anything beyond a short headline/wordmark treatment. Splash/paywall copy should sit on a solid
scrim or a clear zone of the texture, not directly on veined marble.

### Champagne (`accentChampagne` vs. `accentChampagneAccessible`)

Two champagne tokens exist on purpose — see the contrast analysis in §3 for why. The rule:

- **`accentChampagne`** — decorative/non-text use only: fills that sit *behind* `textOnAccent`
  (primary button, selected chip), icon tints paired with a visible text label, thin rules and
  dividers, dark-mode text (where it already has strong contrast).
- **`accentChampagneAccessible`** — anywhere champagne *meaning* is conveyed through text or a
  stroke/border read against the page background: links, secondary/tertiary button labels and
  borders, chip borders, eyebrow labels, the "Strong" score tier.

If you're unsure which to reach for: if the color is the thing being read as text (or as a
border with meaning), use the accessible variant.

### Color-alone

Spec §19 ("Do not encode meaning by color alone") is enforced structurally in two components:

- `AstraScoreMeter` always renders the numeral and a text descriptor (`"Excellent"`, `"Strong"`,
  `"Fair"`, `"Needs Attention"`) alongside the tier color, and its accessibility label spells out
  all three (`"Compatibility: 92 out of 100, Excellent."`).
- `AstraChip`'s selected state changes fill-vs-outline treatment and adds a checkmark glyph, not
  just a color swap, and sets the `.isSelected` accessibility trait.

### Generated imagery

Spec §6.17 and §11 require every Style Studio generated image to be labeled as an estimate.
`GeneratedImageBadge` is the visual badge; `GeneratedImageContainer` is the component feature
code should actually reach for, because it *requires* an accessibility description at
construction time (spec §19: "Generated images require editable alt descriptions") and always
overlays the badge. `View.astraGeneratedImageBadge()` exists only for retrofitting an existing
view hierarchy — new Style Studio/Daily Brief/lookbook surfaces should use the container.

---

## 3. Accessibility contrast analysis

Ratios below are computed directly from the spec's sRGB hex values using the standard WCAG 2.x
relative luminance formula (`L = 0.2126R + 0.7152G + 0.0722B` in linearized sRGB) and contrast
ratio (`(L1 + 0.05) / (L2 + 0.05)`), not estimated.

WCAG 2.x AA thresholds: **4.5:1** for normal text, **3:1** for large text (≥18pt regular or
≥14pt bold) and for non-text UI component contrast (borders, icons that carry meaning).

### `accentChampagne` — dark mode (`#D7B46A`)

| Background | Ratio | AA text (4.5:1) | AA large/UI (3:1) | AAA text (7:1) |
|---|---|---|---|---|
| `backgroundPrimary` `#0D0D0D` | **9.83:1** | Pass | Pass | Pass |
| `backgroundSecondary` `#151515` | **9.24:1** | Pass | Pass | Pass |
| `surfaceElevated` `#1B1B1B` | **8.71:1** | Pass | Pass | Pass |

**Dark-mode champagne text is safe as-is** — it clears even the stricter AAA (7:1) threshold
against every dark surface in the palette. This is why `accentChampagneAccessible` simply reuses
`accentChampagne` in dark mode.

### `accentChampagne` — light mode (`#B8914E`)

| Background | Ratio | AA text (4.5:1) | AA large/UI (3:1) |
|---|---|---|---|
| `backgroundPrimary` `#F8F5EF` | **2.68:1** | **Fail** | **Fail** |
| `surfaceElevated` `#FFFFFF` | **2.92:1** | **Fail** | **Fail** |

**This fails outright — spec §19's own callout ("High-contrast alternative for champagne text")
is not optional in light mode.** Light-mode champagne is too pale to pass AA even as large text
or as a non-text UI border/icon (both need 3:1; it tops out at 2.92:1 on white). It must not be
used as a light-mode text or border color.

### The high-contrast alternative: `accentChampagneAccessible` — light mode (`#8A6A2E`)

A darkened gold was chosen so it clears AA normal-text contrast (4.5:1) against both light
backgrounds in the palette, while still reading unambiguously as "champagne/gold":

| Background | Ratio | AA text (4.5:1) |
|---|---|---|
| `backgroundPrimary` `#F8F5EF` | **4.62:1** | Pass |
| `surfaceElevated` `#FFFFFF` | **5.02:1** | Pass |

This is the token every light-mode text/border use of "champagne" routes through
(`AstraSecondaryButtonStyle`, `AstraTertiaryButtonStyle`, `AstraSectionHeader`'s eyebrow, the
"Strong" score tier). Dark-mode text keeps the brand's true `#D7B46A` since it already passes
comfortably.

### Other semantic tokens — dark mode, on `backgroundPrimary` (`#0D0D0D`)

Computed for completeness, since these are also used as text/descriptor colors in
`AstraScoreMeter`:

| Token | Hex | Ratio on `#0D0D0D` | AA text (4.5:1) | AA large/UI (3:1) |
|---|---|---|---|---|
| `successOlive` | `#69745D` | **3.94:1** | Fail | Pass |
| `warningAmber` | `#A98652` | **5.76:1** | Pass | Pass |
| `destructive` | `#B65F59` | **4.42:1** | Borderline fail (needs 4.5) | Pass |

**Known gap, flagged rather than hidden:** in dark mode, `successOlive` and `destructive` do not
clear 4.5:1 for normal-size text against `backgroundPrimary` (3.94:1 and 4.42:1 respectively).
Both comfortably clear the 3:1 large-text/non-text-UI threshold. Today `AstraScoreMeter` renders
its tier descriptor at `callout` (15pt regular), which is *not* large text by the WCAG
definition, so the "Fair"/"Needs Attention" descriptor text is technically short of AA in dark
mode. Recommended follow-up (not applied here, since it changes brand-specified hex values):
either bump the descriptor to a 17pt+/semibold treatment (crossing into "large text") or
introduce darkened `successOlive`/`destructive` "accessible" variants analogous to
`accentChampagneAccessible`. Light-mode variants of these three tokens are not specified by spec
§3 at all; the ones shipped here (`#4E5744`, `#7E6339`, `#9B4F4A`) are derived, not verified
against every surface combination — treat them as a starting point, not a final accessibility
sign-off.

---

## 4. Design decisions made where the spec was underspecified

The spec (§3) leaves several things unstated. Decisions made, so they can be revisited:

1. **`accentChampagnePressed` in light mode** — spec only gives a dark-mode value (`#B8944D`).
   Light mode (`#9C7B42`) is derived by darkening light-mode `accentChampagne` ~15%.
2. **`successOlive` / `warningAmber` / `destructive` in light mode** — spec's light-mode token
   list omits these entirely. Derived by darkening the dark-mode value ~15–20% for legibility on
   light backgrounds (see §3 for why this still isn't a fully verified accessibility sign-off).
3. **`accentChampagneAccessible`** — not a spec token at all. Added specifically to satisfy spec
   §19's requirement for "a high-contrast alternative for champagne text," since the spec names
   the requirement but doesn't supply the color.
4. **Font weights for `title1`, `title2`, `micro`** — spec gives no weight for these three.
   `title1`/`title2` use `.regular` (the plain editorial-serif default); `micro` uses
   `.semibold` for legibility at 10pt uppercase tracked text.
5. **`AstraScoreMeter` tier thresholds** (85 / 70 / 50) — spec defines the 0–100 *scale* (§10)
   but not display tiers/bands. Chosen to give four legible, evenly-spaced bands.
6. **Marble asset** — not yet in the asset catalog (spec references it as "asset-based"; no file
   was supplied to the design system layer). `surfaceMarble` is a documented placeholder.

---

## 5. Component inventory

| Component | File | When to use |
|---|---|---|
| `AstraPrimaryButtonStyle` (`.astraPrimary`) | `Components/AstraButton.swift` | The single strongest call to action on a screen (e.g. "Wear This", "Continue"). Solid champagne fill, dark on-accent text. Only one per screen/section. |
| `AstraSecondaryButtonStyle` (`.astraSecondary`) | `Components/AstraButton.swift` | A clearly available but non-primary action alongside a primary button (e.g. "Alternatives", "Visualize"). Bordered, champagne-accessible. |
| `AstraTertiaryButtonStyle` (`.astraTertiary`) | `Components/AstraButton.swift` | Low-emphasis actions (e.g. "Edit", "See all", "Skip"). Text-only, still 44pt tall. |
| `AstraCard` | `Components/AstraCard.swift` | The default elevated surface for grouped content (outfit summary, Wardrobe Score module, Kyra's Insight). Handles the light/dark shadow-vs-border asymmetry automatically. |
| `AstraChip` | `Components/AstraChip.swift` | Filter and tag selection (Closet filters, Style Studio prompt presets, occasion tags). Not for primary navigation. |
| `AstraScoreMeter` (`.compact` / `.hero`) | `Components/AstraScoreMeter.swift` | Any 0–100 score: compatibility score (§6.19), Wardrobe Score (§6.11/§6.22), Style Studio confidence. `.compact` inline in a card/list row; `.hero` as a screen's focal element. |
| `AstraSectionHeader` | `Components/AstraSectionHeader.swift` | Editorial section headers throughout Home/Closet/Discover — optional eyebrow + serif title + optional trailing action. |
| `GeneratedImageBadge` / `GeneratedImageContainer` | `Components/GeneratedImageBadge.swift` | Any Style Studio generated image, anywhere in the app (Studio, Daily Brief hero if generated, lookbook). Use the container, not the bare badge, for new code. |
| `AstraTheme` | `AstraTheme.swift` | Inject once near the app root (`.astraTheme(theme)`) if a feature needs an in-app appearance override or a single `@Observable` environment object; otherwise use the token namespaces directly. |
| `DesignSystemGallery` | `Previews/DesignSystemGallery.swift` | Not shipped — internal preview surface for eyeballing every token/component across color scheme and Dynamic Type size. |

---

## 6. Cross-agent integration note

`App/RootView.swift` and `App/MainTabView.swift` (owned by another agent, outside this layer's
scope) were already on disk when this design system was built, and reference a few APIs by
guessed names. Two were reconciled additively, without touching those files:

- `AstraSpacing.buttonRadius` / `.cardRadius` / `.minTapTarget` — added as forwarding aliases to
  `AstraRadius.button` / `.card` and `AstraSize.minTapTarget`, since the spec groups all of these
  under one "Layout" bullet and the consumer guessed they'd live directly on `AstraSpacing`.
- `AstraButton(title:action:)` — added as a convenience `View` wrapper around
  `Button(title, action:).buttonStyle(.astraPrimary)`, alongside the `ButtonStyle` conformances
  this task specified.

**One mismatch was intentionally left unfixed and needs a follow-up edit in those two files:**
both call `.font(AstraTypography.displayL)` / `.title2` / `.body` / `.callout` / `.caption`,
treating `AstraTypography` cases as if they were `Font` values directly. This design system
implements `AstraTypography` as an enum consumed through `.astraText(_:)` (or
`Text.astra(_:style:)`) specifically so point sizes can be driven through `@ScaledMetric` for
real Dynamic Type support (spec §19) — a bare `static var: Font` cannot do that. Changing
`AstraTypography` to satisfy `.font(AstraTypography.displayL)` would mean giving up Dynamic Type
scaling, which was an explicit, critical requirement for this layer, so it was not done. The
correct fix is on the consumer side: replace `.font(AstraTypography.displayL)` with
`.astraText(.displayL)` (and the equivalent for `.title2`, `.body`, `.callout`, `.caption`) in
`RootView.swift` and `MainTabView.swift`.

---

## 7. Notable Swift 6 / iOS 18 implementation choices

- **Color resolution** — `AstraColorToken` wraps a `UIColor { traits in ... }` dynamic provider
  rather than reading `@Environment(\.colorScheme)` per call site, so tokens are declared once
  and "just work" in both appearances anywhere in the view tree, including in contexts (like
  `ShapeStyle` fills) where reading an environment value is awkward.
- **`@Entry` macro** — `AstraTheme`'s environment key uses the iOS 18 `@Entry` macro
  (`extension EnvironmentValues { @Entry var astraTheme: AstraTheme = AstraTheme() }`) instead of
  the older manual `EnvironmentKey` struct boilerplate.
- **Dynamic Type via `@ScaledMetric`** — see §1; this is the part of spec §19 that's easiest to
  silently violate by using `.system(size:)` directly, so it's centralized in one modifier.
- **Haptics on the main actor** — `AstraHaptics` is `@MainActor`-isolated because
  `UIFeedbackGenerator` subclasses are UIKit types that must be prepared/triggered on the main
  thread.

---

## Addendum: `AstraIcon` (added during integration reconciliation)

`Core/DesignSystem/Tokens/AstraIcon.swift` was added after the initial design-system pass, when an
audit found eleven call sites in `App/` and `Features/Home/` sizing SF Symbols with raw
`.font(.system(size: 40))` and `.font(.caption)` literals.

Two problems with the original form:

1. **CLAUDE.md violation.** A glyph size is a design value like any other and must come from a token.
2. **Dynamic Type gap.** `.font(.system(size:))` does not scale with the user's content size setting.
   A 40pt glyph stayed 40pt at AX5 while the text beside it tripled — the same failure mode
   `AstraTypography` was built to avoid, and a direct violation of spec §19's "Full Dynamic Type
   support." (`.font(.caption)` did scale, but was still an untokenised literal.)

`AstraIcon` mirrors `AstraTypography`'s structure exactly: a semantic enum, a `@ScaledMetric`-backed
`ViewModifier`, and a `.astraIcon(_:weight:)` `View` extension. Sizes are semantic rather than
numeric so the symbol's role drives the choice.

| Case | Base size | Dynamic Type anchor | Use for |
|---|---|---|---|
| `.disclosure` | 13 pt | `.caption` | Trailing chevron on a tappable row |
| `.inline` | 16 pt | `.body` | Metadata rows, list affordances |
| `.control` | 20 pt | `.headline` | Nav bar buttons, the Kyra avatar button |
| `.emphasis` | 24 pt | `.title3` | Card and carousel tile affordances |
| `.feature` | 32 pt | `.title2` | Feature-level glyph inside a card |
| `.display` | 40 pt | `.largeTitle` | Full-screen empty, error, and permission states |

**Rule:** never size an SF Symbol with a literal. `Image(systemName:).astraIcon(.control)`, never
`Image(systemName:).font(.system(size: 20))`.
