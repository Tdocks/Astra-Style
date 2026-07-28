# 12 — Design Critique: Astra Style Design Language v1.0

A senior product-design read of `/tmp/astra/design/astra-design-system.html` against the master
spec (§2, §3, §6), the design-system rationale (doc 07), and the owner's brand references. This
judges design decisions, not CSS fidelity.

---

## Verdict

The foundations are genuinely good — the warm bone-and-charcoal palette, the honest WCAG audit,
the marble discipline, and above all Kyra's copy voice are real assets that most "premium" apps
never achieve. But the screens built on those foundations keep breaking the product's own
promise: the app calls itself a stylist's editorial notebook and then behaves like a dashboard —
numeric scores on taste, progress bars on clothing, gold spent like a growth app spends its
accent color, and the outfit itself shrunk into a bordered card. Right now this lands above the
median dark-mode subscription app and clearly below Mr Porter, Aesop, or Hodinkee. The gap is
not craft; it is nerve — the design doesn't yet trust the outfit, the voice, or the whitespace
to carry a screen without a number backing them up.

The three changes below are the difference between the two tiers. Everything after them is
refinement.

---

## The three highest-impact changes

### 1. Take the numbers out of taste

**The problem.** Quantification appears everywhere judgment should be: `92 COMPATIBILITY`
stamped on the Daily Brief hero image, a `68 / Developing` Wardrobe Score bar on the home
screen, `94 compatibility` inside a chat card, a 66pt gold "hero score" numeral in the component
library, three stat tiles of gold serif numerals heading the Closet. A stylist never says "this
outfit is a 92." The moment the interface says it, Kyra stops being a stylist and becomes
software — the exact "technology becomes visible" failure the spec's visual principle forbids.
Worse, the daily `68 Developing` grade tells a paying customer every single morning that his
wardrobe is a C+. That is emotionally backwards for a luxury service.

**The fix, precisely:**
- **Daily Brief:** delete the compatibility score from the hero label. Replace
  `SMART CASUAL · 92 COMPATIBILITY` with `Smart casual · Rain after four` (occasion +
  condition — the two things a stylist would actually annotate).
- **Home:** remove the Wardrobe Score module from the Daily Brief entirely. Wardrobe Score
  lives in the Monthly Review and Profile, framed as progression over time ("up 6 this month"),
  never as a static daily grade. Spec §6.11 lists it as a home module — the spec is wrong here.
- **Kyra chat cards:** `4 items · 94 compatibility` becomes `4 items · from your closet`.
- **Component library:** delete the `hero-score` component (the 66pt gold numeral). It is a
  credit score. No screen in a taste product should need it.
- **Keep numbers in exactly one place:** the Product Decision screen, where the user has asked
  for an evaluation and quantified evidence supports a verdict — and even there, subordinate
  them (see change 3).

This is the single change I'd make if I could make only one. It touches every screen, and it is
the line between "stylist" and "app about clothes."

### 2. Give the outfit the screen

**The problem.** The owner's own reference (`ui-reference-daily-brief.jpg`) devotes roughly 70%
of the viewport to a full-bleed flat lay — the outfit is treated like a plate in a monograph.
The mockup shrinks it to a 212px-tall image inside a bordered, rounded card: barely a third of
the screen, framed like a feed item. Meanwhile "Why this works" — the product's actual
differentiator, the thing no competitor ships — is set at 12.5px secondary-gray, i.e. caption
furniture. The screen that must earn a daily open currently gives its two best assets the least
room.

**The fix, precisely:**
- The hero image runs **full-bleed, edge to edge, no border, no radius**, from under the status
  bar to roughly 55–60% of screen height. The scrim gradient carries `Today's Look` (title2,
  22pt serif) and the occasion line. The brand wordmark comes off the top of this screen — the
  notebook belongs to the user, not the logo; first light of day should be his name, not ours.
- Restructure the top: micro eyebrow with the date (`TUESDAY, JULY 28` — a notebook entry is
  dated), then `Good morning, Tyler.` at **displayL, 34pt serif** as the spec's own scale
  intends (the mockup quietly under-sets it at 26px — a sign the scale isn't being trusted),
  then the weather/meetings line at caption. The condensed
  `62° Partly cloudy · Rain after 4 · 2 meetings` line is already excellent — keep it exactly.
- "Why this works" is promoted to Kyra's voice: micro eyebrow `WHY THIS WORKS`, then the
  reasoning set in **serif, 16–17pt, textPrimary** — not sans, not 12.5px, not gray. This is
  the stylist's annotation on the plate; it should read like one. Drop the inline bolded
  `Why this works.` lead — the eyebrow does that job.
- `Wear This` / `Alternatives` stay as-is below. They're correctly weighted.

### 3. Redesign the Product Decision as counsel, not a rejection notice

**The problem.** "Skip" — the app's most distinctive, most trust-building moment — is currently
rendered as a red-tinted alert box with red serif type, followed by three progress bars, and
only *then* Kyra's reasoning. Red box + red type is the visual grammar of a declined card
payment. The meters make it worse: `Redundancy Risk 88 · High` on a red bar is an actuarial
table, and `New Outfits Unlocked: 3` drawn as a 14%-filled bar is a unit error (a count on a
0–100 track). The screen's best line — Kyra's "It's a good jacket. It just isn't a good jacket
*for you*" — is buried fourth.

**The fix, precisely — reorder as verdict → reasoning → evidence → path forward:**
1. **Verdict:** `Skip.` in bone serif (title1, 28pt), on the page background — no box, no red.
   `destructive` red is reserved for destructive actions (delete item), never for advice.
   One supporting line beneath in textSecondary.
2. **Kyra's reasoning immediately under it**, serif, full width — the current quote copy is
   already the best writing in the document; it earns the second position, not the fourth.
3. **Evidence instead of meters:** replace `Redundancy Risk 88` with the actual redundancy —
   thumbnails of the two black outer layers he already owns, labeled `Already in your closet`.
   A man who is shown his own Barbour and navy bomber doesn't need a bar chart to agree.
   Keep at most one quantified line, as text not meter: `Adds 3 outfits — all near-duplicates
   of looks you already own.`
4. **The path forward:** the `Instead, consider` module is the best idea on this screen —
   `Stone Harrington · Unlocks 14 outfits · $310` against the bomber's 3 is genuinely
   persuasive. Give it more room and a small image, and retitle it `The gap in your closet`.
   That reframing is what makes Skip feel like service: Kyra isn't saying no, she's redirecting
   the same money at a real gap.
- Copy rewrite for the verdict block:
  > **Skip.**
  > It's a good jacket. It just isn't a good jacket for you — the Barbour and the navy bomber
  > already do this job. If you want a third layer, your gap is mid-weight and lighter in color.

---

## Detailed critique

### 1. Does it clear the bar?

**Genuinely premium, today:**
- **The palette's warmth.** Bone `#F7F3EA` instead of white, warm-gray muted text, olive and
  brick as semantic colors. Most dark modes are blue-gray and cold; this one is candlelit. This
  is the single most load-bearing craft decision in the system and it's right.
- **Kyra's copy.** "It reads considered without trying, and the derby handles wet pavement
  better than your sneakers." "Skip the suede chukkas tonight — they'll mark." This is the
  voice of an actual stylist and it is worth more than any visual token. Protect it above all.
- **The honesty layer.** The `Visual Estimate` badge, the WCAG audit that flags its own
  failures, the two-champagne token system with a written rule for which to use — this is the
  invisible rigor real luxury products have and clones don't.
- **Marble discipline.** "A brand texture, not a background," with a sanctioned-surfaces list.
  Correct, and rare restraint.
- **The motion philosophy.** "Motion confirms, it never performs" is the right sentence; the
  220ms/matched-geometry/breathing set is the right vocabulary.

**Reads as a competent dark-mode app wearing premium clothes:**
- Progress bars with rounded tracks — the single most "dashboard" component in existence — used
  for taste judgments.
- Stat tile rows with gold numerals (Closet header). This is a fitness app's grammar.
- Gold spent on: active tab, selected chip fill, stat numerals, FAB, score numerals, prices,
  send button, badge, orb. When everything is gold, gold means "interactive," not "precious."
- Everything boxed. The Daily Brief and Product Decision are stacks of bordered rounded cards.
  Editorial layout builds hierarchy from whitespace, rules, and type scale; boxes are how apps
  do it. Aesop's product pages have almost no containers at all.
- The chat screen is a generic messenger with gold user-bubbles. Nothing about it says stylist.

Against the reference set: the color and copy would not embarrass themselves next to Mr Porter.
The screens' *structure* — meters, stats, boxes, badge-density — sits closer to a well-made
banking app. That structural layer is where all three high-impact changes aim.

### 2. The Daily Brief

Covered in change 1 and 2 above; remaining notes:

- **The greeting** is the right instinct and the wrong size. At 26px with the brand wordmark
  above it, it's one module among several. At 34pt serif with the wordmark gone and a dated
  eyebrow above it, it becomes the notebook's daily entry heading. The difference between
  "every app's greeting" and this one is not the words — it's whether anything competes with it.
- **What a stylist's notebook does that a recommendation feed doesn't:** it is dated, it is
  annotated in the stylist's hand (serif), it shows one look with conviction before
  alternatives, and it never grades. The current screen gets "one look first" right (good —
  and it matches the voice spec's "one strong recommendation before alternatives") and misses
  the other three.
- **Kyra's Insight** is good content in the wrong container. Take it out of the bordered box:
  set it as a pull-quote — thin 1px champagne rule on the left, serif roman text, her name-mark
  below. A boxed card says "module"; a pull-quote says "margin note."
- **The emotional beat** should be: *date → name → sky → the look (long, quiet) → why → act →
  one thought from Kyra.* The current order is close; it's the volume of each beat that's wrong.

### 3. Kyra's presence

- **The orb is the wrong object.** A glowing gold gradient sphere with a breathing animation is
  the universal iconography of a generic AI assistant — it is the single most
  "technology visible" element in the product, on a spec that demands technology stay
  invisible. Meanwhile the brand already owns an elegant mark: the A's swoosh and star. Give
  Kyra the **star + arc fragment** of the monogram as her mark — a small gold asterisk-star
  that can settle, pulse subtly while thinking, and sign her notes like a stylist's initial.
  Same animation budget, but it's *brand*, not *bot*.
- **Her typographic voice is currently split three ways:** italic serif in quotes on Home,
  plain sans bubbles in chat, bold-led sans in "Why this works." Pick one register: **serif
  roman, no quotation marks, everywhere she speaks.** Quotation marks frame her as being
  quoted by the app; dropping them makes her present in it. Reserve italic for emphasis within
  her sentences (the current "for you" italic is exactly right) — full-time italics are a
  costume, and they cost legibility at 14.5px.
- **The chat screen** deserves the one structural risk in the app: drop the bubble for Kyra.
  Her responses set flush-left on the page background, serif, with her star-mark; only the
  user's messages sit in bubbles (and not gold ones — `surfaceElevated` with a 1px divider;
  gold user-bubbles spend the accent on the wrong speaker ~20 times per conversation). The
  asymmetry — he sends messages, she writes back — is precisely the stylist-correspondence
  feeling, and no competitor's chat looks like it.
- What's already right: her insight copy never flatters, per the voice spec. "Skip the suede
  chukkas tonight — they'll mark" is the whole brand in eight words.

### 4. The Product Decision screen

Covered in change 3. Two additions:

- **Spec §6.19 is over-specified and should be trimmed.** Seven scores (compatibility, outfits
  unlocked, redundancy, color fit, lifestyle fit, budget fit, cost per wear) is a due-diligence
  memo. The verdict plus reasoning plus visual evidence carries the decision; keep the full
  breakdown behind a single quiet `See the full assessment` tertiary link for the user who
  wants it. Default view: zero meters.
- **The header is good** — `Kyra's Verdict` eyebrow, item in serif, brand · price in muted.
  Keep it exactly; it already reads like a notebook entry heading.

### 5. Restraint audit

- **Gold budget.** Adopt a hard rule: per screen, gold may appear on (a) the single primary
  action, (b) the active tab glyph, (c) Kyra's mark, (d) at most one accent rule/eyebrow.
  Everything else currently gold reverts: stat numerals → bone serif; selected chip → bone
  text on `surfaceElevated` fill with 1px champagne border (a gold-filled chip and a
  gold-filled primary button on the same screen makes the chip lie about its importance);
  Closet `+` FAB → bone glyph, hairline border (it's also 32px — below the spec's own 44pt
  tap minimum); prices → textPrimary. The paywall may keep its gold generosity; it's the one
  ceremonial screen.
- **Score meters** — see change 1. The component itself (numeral + word, never color alone) is
  well built; the accessibility structure of `AstraScoreMeter` is genuinely good work. The
  problem is deployment surface, not construction. Demote it to the "full assessment"
  disclosure and the Monthly Review.
- **Stat rows.** `84 items · $6.2k value · $7.40 cost/wear` as the Closet's opening statement
  frames the wardrobe as a portfolio. Move value and cost-per-wear into Profile/Monthly Review;
  if the Closet needs a header line at all, one quiet caption: `84 pieces · 61 in rotation`.
  Spec §6.14's metrics list is a data inventory, not a screen design — it belongs in a report,
  and the spec should say so.
- **Where it's not trying hard enough:** the Closet grid (see 6), the paywall feature list
  (sparkle bullets ✦ at 12.5px line-height 2.15 is App Store template grammar), and the chat
  screen. And two disclaimers on one Style Studio screen (badge + footnote) — the badge is the
  system; show the long-form sentence once, on first use, then trust the badge.
- **Where the notebook promise breaks completely:** any screen where two or more bordered boxes
  containing numbers stack vertically. Daily Brief bottom half and Product Decision middle both
  do this today; both fixes above dissolve it.

### 6. Type and space

- **The serif/sans split is correct and well-reasoned** — serif for what the stylist says,
  sans for what the interface needs. This rule is stated in the type section and then violated
  by "Why this works" (Kyra content in sans caption). Enforce the rule as written; it's a good
  rule.
- **The scale has a hole and the mockups prove it.** Between title2 (22) and headline (17)
  there is nothing, so the mockups invent 26, 24, 20, 19, and 16px serif ad hoc — five
  off-token sizes across seven screens. Add `title3: 19pt serif` and re-set the mockups
  strictly on tokens. A type scale that its own reference mockups can't live inside will not
  survive contact with SwiftUI. (Doc 07's token work is solid; this is a spec §3 gap.)
- **Weights are inconsistent between artifacts:** spec/doc-07 set title1/title2 at regular; the
  HTML sets every serif at 600. Regular is the more editorial choice — semibold serif
  everywhere reads like a theme, not typesetting. Reserve semibold for displayL/XL.
- **Spacing has no rhythm.** The spec declares a 4pt base unit; the mockups run on 9, 11, 13,
  15, and 17px. Snap to 12/16/20/24. More importantly, the vertical rhythm between modules is
  uniform (~11–15px everywhere), which flattens hierarchy — the gap between the hero block and
  what follows should be roughly twice the gap between minor modules (32 vs 16). Uniform
  spacing is how dashboards breathe; varied spacing is how pages do.
- **The wordmark treatment is strong** — the .30em tracked serif with flanking gold rules
  matches the brand asset well. Its in-app *ubiquity* is the issue (see change 2). Splash,
  paywall, about: yes. Home header, daily: no.
- **Closet grid:** 2-up with 104px images and 9.5px muted metadata is commerce-grid default,
  and 9.5px is below the legible floor. For an "editorial grid": images at 4:5 (taller than
  wide — garments are portrait objects), item name in serif `title3`-adjacent size, brand in
  micro caps, and consistent metadata grammar (`12 wears` vs bare `9` currently alternate).
  Consider a periodic full-width row (most-worn item as a plate) to break the grid — that's
  the editorial move.

### 7. What's missing

Ordered by how much each would matter:

1. **The empty closet.** Spec §6.11 gives it one line ("prompt to add 5 items"). This is the
   first real screen every user sees and the purest notebook moment: a blank dated page, Kyra's
   line in serif — *"Your notebook starts with five garments. Scan the things you reach for
   most — I'll take it from there."* — one primary action. If the empty state is generic, the
   premium claim dies on day one.
2. **The scan reward.** Doc says success haptic is "the one moment worth celebrating," but
   nothing is designed. The reward for the fifteenth garment shouldn't be a checkmark — it
   should be capability: *"Fifteen pieces in. Your closet can now make 38 outfits I'd stand
   behind."* Watching the outfit count climb as you scan is the retention loop made visible,
   and it's the moment a man shows a friend.
3. **The wait states.** Style Studio generation (spec lists queued/generating/failed; nothing
   designed) and Kyra thinking. A 15–30 second generation wait is where the illusion either
   dies (spinner) or deepens (the marble transition surface the spec already sanctions, her
   star-mark slowly settling, one line of her voice). This is the highest-leverage use of the
   marble asset in the whole app.
4. **Time of day.** The Brief is designed for 6am only. At 7pm the same screen should turn the
   page: "Tomorrow" prep, tonight's dinner look if the calendar shows one, laundry state. A
   notebook has morning and evening entries; an app has one home screen. Even greeting logic
   (`Good evening` + tomorrow's hero) would be a start.
5. **The shareable artifact.** No designed export. A flat-lay outfit card with the date, the
   look name, and one line of Kyra's reasoning — wordmark small at the foot — is free
   distribution among exactly the right audience.
6. **Light mode.** Tokens exist (and doc 07 did honest work on them); zero screens are
   designed. Given "dark is the default," fine to defer — but decide *when*, or light mode
   will ship as an inverted afterthought and undo the a11y work.
7. **The tagline.** "Your style. Your journey. Your best self." is wellness-app copy under a
   luxury monogram. The spec's own Kyra introduction contains the better line: **"Dress with
   intention."** Owner's asset, owner's call — but the splash would be stronger carrying the
   monogram alone, or that single line.

---

## Prioritized backlog (after the three changes above)

**P1 — structural**
1. Unify Kyra's voice: serif roman, no quote marks, star-mark not orb (§3 of critique).
2. Chat redesign: unbubbled Kyra, neutral user bubbles, gold off the user side.
3. Empty-closet state + scan milestone moment (copy above).
4. Add `title3 19pt serif` to spec §3; re-set all mockups on-token; regular-weight title1/title2.
5. Gold budget rule written into doc 07 as a hard per-screen constraint (a/b/c/d list above).
6. Closet: stat row out, editorial grid in (4:5 images, serif names, metadata grammar fixed).

**P2 — surface**
7. Spacing pass: 4pt grid, 32/16 major/minor vertical rhythm.
8. Paywall feature list: cut five sparkle bullets to three benefit lines —
   *"A brief every morning, built around your day." / "A verdict before you buy anything." /
   "One stylist for your whole wardrobe."* Keep the marble hero — it's the best paywall element.
9. Style Studio: single disclaimer (badge only after first use); design the before/after
   interaction (the mock shows only "After").
10. Closet FAB to 44pt; de-gold per budget rule.
11. Wardrobe Score reframed as delta-over-time in Monthly Review/Profile only.
12. Fix `New Outfits Unlocked` unit treatment anywhere counts appear — counts are text, never
    bars.

**P3 — polish**
13. Evening variant of the Brief.
14. Shareable outfit card.
15. Replace the approximated monogram SVG with the true vector before any implementation reuse.
16. Dark-mode `successOlive`/`destructive` AA gap: adopt doc 07's recommendation (bump
    descriptor to large-text treatment) rather than shifting brand hexes.
17. Decide the light-mode milestone.

---

## Copy rewrites, collected

- **Hero label:** `Today's Look` / `Smart casual · Rain after four`
- **Brief header:** `TUESDAY, JULY 28` → `Good morning, Tyler.` → `62° Partly cloudy · Rain after 4 · 2 meetings`
- **Skip verdict:** `Skip.` / *"It's a good jacket. It just isn't a good jacket for you — the
  Barbour and the navy bomber already do this job. If you want a third layer, your gap is
  mid-weight and lighter in color."* / evidence row: `Already in your closet` /
  `Adds 3 outfits — all near-duplicates of looks you already own.` / `The gap in your closet:
  Stone Harrington · Unlocks 14 outfits · $310`
- **Empty closet:** *"Your notebook starts with five garments. Scan the things you reach for
  most — I'll take it from there."*
- **Scan milestone:** *"Fifteen pieces in. Your closet can now make 38 outfits I'd stand
  behind."*
- **Chat card metadata:** `4 items · from your closet`
- **Paywall:** three lines as in backlog item 8.
- **Splash tagline (owner's call):** `Dress with intention.`

---

*What is already excellent and must be protected through every revision above: the warm
palette, Kyra's writing, the Visual Estimate honesty system, the marble discipline, the
two-champagne accessibility architecture, and the "one strong look before alternatives"
structure. None of the changes in this document touch those; they exist to let them be seen.*
