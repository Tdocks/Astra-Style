/**
 * §5 — the Wardrobe Score: seven weighted components, 0–100, damped for
 * sparse wardrobes (§5.9). `P4-OUTFIT-10`.
 *
 * Every component is a `Subscore` (`types.ts`), same as `compatibility.ts`'s
 * eight — a value AND what it could not measure, never a bare number standing
 * in for a fact nobody has. The composite carries the union of every
 * component's `degraded` list for the same reason `CompatibilityScore` does.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * WHY THIS TYPE HAS NO `price_paid` FIELD.
 *
 * §5.8 is explicit that price must never inflate the score, and the master
 * spec calls it out by name ("do not equate expensive clothing with a higher
 * score"). The strongest way to keep that promise is not a rule the code
 * follows — it's a fact the type makes true. `WardrobeItem` simply has
 * nowhere to put a price, so no component in this file can read one even by
 * accident; there is no `pricePaid` to reach for. `wardrobeScore_test.ts`
 * still asserts the outcome (two closets differing only in a field this type
 * drops score identically), because the promise a caller cares about is "the
 * number doesn't change," not "the field doesn't exist" — but the field not
 * existing is *why* the assertion can never fail by omission later.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * THE SCHEMA GAP §5.1 SITS ON TOP OF, AND THE CHOICE MADE HERE.
 *
 * itemVersatility_i ("how many distinct outfits can this item join") is not
 * something the doc gives a bounded algorithm for — §6.2's K-pruned
 * generation is scoped to ONE anchor (a purchase candidate), not "run this
 * for every owned item." Reusing it here anyway (`generateAnchoredOutfits`,
 * self-anchored on each active item in turn) is the only reading that keeps
 * §5.1's own cross-reference to §6.3's dedup rule true — that rule only
 * exists inside the pruned-generation machinery. The cost is real: it turns
 * an O(K^slots) computation into O(n · K^slots). `WARDROBE_SCAN_OPTIONS`
 * below prunes tighter than §6.2's own K=10/top-4 (sized for a single
 * synchronous product-page call) specifically to keep that multiplication by
 * `n` affordable; see its comment for the actual numbers and what they cost.
 */

import {
  type Condition,
  degradedScore,
  measured,
  type ScorableItem,
  type Subscore,
  unitClamp,
} from "./types.ts";
import { colorClusterId } from "./equivalence.ts";
import { bodyMultiplier, type FitNote } from "./subscores/silhouette.ts";
import {
  DEFAULT_GENERATION_OPTIONS,
  generateAnchoredOutfits,
  type PrunedGenerationOptions,
} from "./outfitGeneration.ts";
import { labFromLCh, type RedundancyItem, redundancyScore } from "./redundancy.ts";
import type { ComponentWeights } from "./compatibility.ts";

/**
 * One owned garment as §5's components need it: everything `ScorableItem`
 * already carries (§2's inputs — versatility scoring runs full outfit
 * compatibility under the hood), plus the four fields §5 alone reads.
 *
 * No `price_paid`. See the module header.
 */
export interface WardrobeItem extends ScorableItem {
  /** §5.6. Nullable in the schema — a garment the condition classifier has not seen. */
  readonly condition: Condition | null;
  readonly lastWornAt: Date | null;
  /**
   * §5.5's `age_in_closet` proxy. Mapped from `closet_items.created_at`, NOT
   * `purchase_date` — `purchase_date` is nullable (gifted items, no receipt,
   * §7.2's own edge case) and answers "when was this bought," not "how long
   * has it been in THIS closet." A transferred or long-delayed-entry garment
   * can have a purchase_date years before its row exists; `created_at` is the
   * only column that actually measures wardrobe tenure.
   */
  readonly addedAt: Date;
  /** `closet_items.archived_at`. Null = active. Archived items are excluded before any component runs. */
  readonly archivedAt: Date | null;
}

/** §5.6's value scale, remapped — see the type's own doc comment on `Condition` in `types.ts`. */
const CONDITION_VALUE: Record<Condition, number> = {
  // §5.6 has no rung above "excellent" (1.0). The shipped enum has two:
  // `new_with_tags` is unambiguously at least as good as "excellent" (unworn,
  // tags on), so it takes the doc's top value. `like_new` sits between that
  // and `good` (0.8) rather than colliding with either.
  new_with_tags: 1.0,
  like_new: 0.9,
  good: 0.8,
  fair: 0.5,
  worn: 0.25,
  // No enum value maps to the doc's `damaged` (0.0) — the shipped scale has
  // no rung for a garment too damaged to wear. That is a real product gap
  // (a damaged item currently has no way to score below "worn"), not
  // something this file can paper over by inventing a value nothing sets.
};

/** Neutral prior for a garment whose condition was never assessed. Between `good` and `fair`, matching the "least-wrong midpoint" reasoning `formality.ts` uses for its own category defaults. */
export const UNKNOWN_CONDITION_PRIOR = 0.65;

/** §5.3's fixed minimum, always present regardless of what the user's lifestyle profile supplies. */
export const FIXED_MINIMUM_OCCASIONS: readonly string[] = [
  "everyday-casual",
  "work",
  "date-night",
  "semi-formal-event",
];

/** §5.5. */
const WEAR_WINDOW_DAYS = 180;
const MIN_AGE_FOR_UTILIZATION_DAYS = 30;

/** §5.9. */
const DEFAULT_N0 = 15;
const DEFAULT_DAMPING_ANCHOR = 50;

export interface WardrobeComponentWeights {
  readonly versatility: number;
  readonly fitConfidence: number;
  readonly occasionCoverage: number;
  readonly colorCohesion: number;
  readonly wearUtilization: number;
  readonly condition: number;
  readonly redundancyControl: number;
}

/** §5's table, verbatim. Sums to 1.0. */
export const DEFAULT_WARDROBE_WEIGHTS: WardrobeComponentWeights = {
  versatility: 0.25,
  fitConfidence: 0.15,
  occasionCoverage: 0.15,
  colorCohesion: 0.10,
  wearUtilization: 0.15,
  condition: 0.10,
  redundancyControl: 0.10,
};

export type WardrobeComponentName = keyof WardrobeComponentWeights;

/** Pre-joined per-item feedback — see `perItemFitConfidence`'s comment for why this is caller-assembled. */
export interface ItemFeedback {
  /** `style_feedback.signal ∈ {like}` OR a joined `outfit_wears.rating ≥ 4` wear of an outfit containing this item. */
  readonly hasPositiveSignal: boolean;
  /** `style_feedback.signal ∈ {bad_fit, dislike}`. */
  readonly hasNegativeSignal: boolean;
}

export interface WardrobeContext {
  readonly feedbackByItemId?: ReadonlyMap<string, ItemFeedback>;
  /** `body_profiles.fit_notes`, same enum §4.3 reads. */
  readonly fitNotes?: readonly FitNote[];
  /** `lifestyle_profiles.common_occasions` ∪ whatever the caller infers from `dress_code`. The fixed four are unioned in automatically — do not repeat them here. */
  readonly additionalTargetOccasions?: readonly string[];
  /** Per-occasion "does ≥1 outfit at compatibility ≥0.7 already cover this," computed by the caller from real/generated outfits. Absent (not `false`) means "not checked." */
  readonly occasionCoverage?: ReadonlyMap<string, boolean>;
  readonly weights?: Partial<WardrobeComponentWeights>;
  /** §2's weights, passed through to every internal outfit-compatibility call the versatility scan makes. */
  readonly compatibilityWeights?: ComponentWeights;
  readonly n0?: number;
  readonly dampingAnchor?: number;
}

export interface WardrobeScoreResult {
  /** 0–100, or `null` for an empty wardrobe (§8: "not shown," not a `0`). */
  readonly score: number | null;
  readonly rawComposite: number | null;
  /** §5.9's `confidence(n)`. 0 for `n=0`. */
  readonly confidence: number;
  readonly components: Readonly<Record<WardrobeComponentName, Subscore>>;
  readonly degraded: readonly string[];
  readonly activeItemCount: number;
}

function normaliseWeights(
  weights: Partial<WardrobeComponentWeights> | undefined,
): WardrobeComponentWeights {
  const merged: WardrobeComponentWeights = { ...DEFAULT_WARDROBE_WEIGHTS, ...weights };
  const total = Object.values(merged).reduce((s, w) => s + w, 0);
  if (total <= 0 || !Number.isFinite(total)) return DEFAULT_WARDROBE_WEIGHTS;
  if (Math.abs(total - 1) < 1e-9) return merged;
  const scaled = {} as Record<WardrobeComponentName, number>;
  for (const [name, value] of Object.entries(merged) as [WardrobeComponentName, number][]) {
    scaled[name] = value / total;
  }
  return scaled as unknown as WardrobeComponentWeights;
}

function daysBetween(earlier: Date, later: Date): number {
  return (later.getTime() - earlier.getTime()) / (1000 * 60 * 60 * 24);
}

/**
 * §5.1's interpolation formula, implemented exactly as written.
 *
 * IT DOES NOT REPRODUCE ITS OWN SEED TABLE. §5.1 states both "empirically
 * seeded at n=5→3, n=15→12, n=40→35, n=80→60" AND the closed form
 * `3 + 9.2 × ln(n/5+1)`. That formula evaluates to 9.38 at n=5, 15.75 at
 * n=15, 23.2 at n=40, and 29.1 at n=80 — nowhere near the seed values, and no
 * curve of this shape passes through all four (checked by least-squares
 * fitting two of the points and testing the other two). This is reported as
 * a doc-internal inconsistency, not resolved by inventing a coefficient that
 * hits the seed table instead: the formula is the operative definition (the
 * seed points are described as what it was fit AGAINST, not exact
 * checkpoints), so it is implemented literally. Nothing in this file depends
 * on hitting the seed table's exact numbers — `wardrobeScore_test.ts`'s
 * cold-start reproduction instead drives §5.9's damping arithmetic directly
 * off the doc's own worked example numbers, which is the part of §5.10 that
 * IS internally consistent.
 */
export function expectedVersatility(activeItemCount: number): number {
  if (activeItemCount < 5) return 0;
  return 3 + 9.2 * Math.log(activeItemCount / 5 + 1);
}

/**
 * §5.9. `N0=15` is "fully earned"; below it, the composite is pulled toward
 * `dampingAnchor` (50, "unknown," not "bad" — see §5.9's own reasoning).
 */
export function confidenceOf(activeItemCount: number, n0: number = DEFAULT_N0): number {
  if (n0 <= 0) return 1;
  return unitClamp(activeItemCount / n0);
}

export function dampedScore(
  rawComposite: number,
  activeItemCount: number,
  n0: number = DEFAULT_N0,
  dampingAnchor: number = DEFAULT_DAMPING_ANCHOR,
): number {
  const confidence = confidenceOf(activeItemCount, n0);
  return confidence * rawComposite + (1 - confidence) * dampingAnchor;
}

/**
 * The versatility scan's own generation options — deliberately tighter than
 * §6.2's K=10/accessory-top-4/1-slot, which were sized for ONE anchor per
 * synchronous call. This scan runs one anchored generation PER ACTIVE ITEM,
 * so the same K multiplies by wardrobe size: at K=10 a 40-item wardrobe with
 * several accessories can push past 10^5 scored combinations, which is fine
 * once but not forty times. K=6/outerwear-6/accessory-top-3 keeps the same
 * O(K^slots) shape at roughly an eighth of the per-anchor cost, at the price
 * of pruning a same-role candidate this scan would have kept at K=10 — an
 * acceptable trade for a wardrobe-health number that is not the synchronous
 * product-decision path §6.6's budget was written for.
 */
export const WARDROBE_SCAN_OPTIONS: Partial<PrunedGenerationOptions> = {
  ...DEFAULT_GENERATION_OPTIONS,
  slotK: 6,
  outerwearK: 6,
  accessoryTopK: 3,
};

interface VersatilityResult {
  readonly component: Subscore;
  /** Raw (not normalised) counts, reused by §5.6's condition weighting. */
  readonly rawByItemId: ReadonlyMap<string, number>;
}

function computeVersatility(
  active: readonly WardrobeItem[],
  weights: ComponentWeights | undefined,
): VersatilityResult {
  const n = active.length;
  const expected = expectedVersatility(n);
  const rawByItemId = new Map<string, number>();

  for (const item of active) {
    const pool = active.filter((i) => i.id !== item.id);
    const result = generateAnchoredOutfits(item, pool, {
      ...WARDROBE_SCAN_OPTIONS,
      weights,
    });
    rawByItemId.set(item.id, result.qualifying.length);
  }

  if (expected === 0) {
    // Below the curve's floor (n<5): there is no baseline to normalise
    // against, so every item's normalised versatility is honestly 0 rather
    // than a divide-by-zero standing in for "undefined." §5.9's damping is
    // what keeps a 3-item closet from scoring well on the strength of other
    // components alone — this component is not asked to do that job too.
    return { component: measured(0), rawByItemId };
  }

  const normalised = active.map((item) => unitClamp((rawByItemId.get(item.id) ?? 0) / expected));
  const value = normalised.length === 0
    ? 0
    : normalised.reduce((s, v) => s + v, 0) / normalised.length;
  return { component: measured(value), rawByItemId };
}

/**
 * §5.2. `style_feedback` carries a `wore` signal but NO rating column — the
 * 1–5 star rating §5.2's "wore+rating≥4" needs lives on `outfit_wears`,
 * reachable only by joining through `outfit_items.closet_item_id`. That join
 * is not something a pure function can perform (no database, per this
 * package's rule), so `WardrobeContext.feedbackByItemId` takes the ALREADY
 * -joined answer — the caller resolves "does this item have a like, or a
 * wore-together outfit rated ≥4, and no negative signal" via one query, and
 * this function just reads the two booleans that formula collapses to.
 */
function perItemFitConfidence(
  item: WardrobeItem,
  feedback: ItemFeedback | undefined,
  fitNotes: readonly FitNote[],
): { value: number; unavailableNotes: readonly FitNote[]; fitUnrecorded: boolean } {
  let adjustment = 0;
  if (feedback?.hasNegativeSignal) adjustment = -0.5;
  else if (feedback?.hasPositiveSignal) adjustment = 0.4;

  // §5.2's formula, literally: base 0.6, PLUS 0.4× the adjustment above (the
  // adjustment is already ±0.4/±0.5, so this is a second, deliberate
  // dampening — a positive signal moves the score 0.6→0.76, not 0.6→1.0).
  let value = unitClamp(0.6 + 0.4 * adjustment);

  const mod = bodyMultiplier(item, fitNotes);
  value = unitClamp(value * mod.multiplier);

  return { value, unavailableNotes: mod.unavailable, fitUnrecorded: item.fit === null };
}

function computeFitConfidence(active: readonly WardrobeItem[], context: WardrobeContext): Subscore {
  if (active.length === 0) return degradedScore(0.6, "any garments to judge fit confidence for");

  const fitNotes = context.fitNotes ?? [];
  const unavailable = new Set<FitNote>();
  let unrecordedCount = 0;
  let total = 0;

  for (const item of active) {
    const result = perItemFitConfidence(item, context.feedbackByItemId?.get(item.id), fitNotes);
    total += result.value;
    for (const note of result.unavailableNotes) unavailable.add(note);
    if (result.fitUnrecorded) unrecordedCount++;
  }

  const value = total / active.length;
  const degraded: string[] = [];
  if (!context.feedbackByItemId) {
    degraded.push("style feedback and wear ratings (no history supplied)");
  }
  if (unrecordedCount > 0) {
    degraded.push(
      `fit of ${unrecordedCount} garment(s) (unrecorded, so a structural fit-note conflict cannot be checked)`,
    );
  }
  for (const note of unavailable) {
    degraded.push(
      `the "${note}" fit adjustment (no garment length or break is stored, so it cannot be applied)`,
    );
  }
  return degraded.length === 0 ? measured(value) : degradedScore(value, ...degraded);
}

function targetOccasionSet(additional: readonly string[]): readonly string[] {
  return [...new Set([...FIXED_MINIMUM_OCCASIONS, ...additional])];
}

function computeOccasionCoverage(context: WardrobeContext): Subscore {
  const targets = targetOccasionSet(context.additionalTargetOccasions ?? []);
  const coverage = context.occasionCoverage;
  if (!coverage) {
    return degradedScore(
      0,
      `outfit coverage data for ${targets.length} target occasion(s) (none supplied)`,
    );
  }
  let covered = 0;
  const unmeasured: string[] = [];
  for (const occasion of targets) {
    if (!coverage.has(occasion)) {
      unmeasured.push(occasion);
      continue;
    }
    if (coverage.get(occasion)) covered++;
  }
  const value = covered / targets.length;
  return unmeasured.length === 0
    ? measured(value)
    : degradedScore(value, `coverage data for: ${unmeasured.join(", ")}`);
}

/**
 * §5.4. Reuses `equivalence.ts`'s `colorClusterId` — the same "which of 12
 * hue bins, or neutral" question §6.3's near-duplicate check asks, because a
 * wardrobe that is cohesive by one reading is cohesive by the other.
 */
function computeColorCohesion(active: readonly WardrobeItem[]): Subscore {
  const withColor = active.filter((i) => i.primaryColor !== null);
  const missing = active.length - withColor.length;

  const chromaticCount = withColor.filter((i) => !i.isNeutral).length;
  if (chromaticCount < 4) {
    // §5.4's own edge case: a neutrals-heavy wardrobe is a valid capsule
    // strategy, not incoherence, so entropy over a near-empty chromatic set
    // is skipped rather than computed and misread.
    return missing === 0
      ? measured(0.8)
      : degradedScore(0.8, `colour of ${missing} garment(s) (never analysed)`);
  }

  const counts = new Map<string, number>();
  for (const item of withColor) {
    const cluster = colorClusterId(item);
    counts.set(cluster, (counts.get(cluster) ?? 0) + 1);
  }
  const total = withColor.length;
  const nonEmptyClusters = counts.size;

  let value: number;
  if (nonEmptyClusters <= 1) {
    // Every classified item shares one bucket — maximally cohesive, and
    // Shannon entropy of a one-outcome distribution is 0 by definition, not
    // a 0/0 this branch needs to guess at.
    value = 1;
  } else {
    let entropy = 0;
    for (const count of counts.values()) {
      const p = count / total;
      entropy -= p * Math.log2(p);
    }
    const normalisedEntropy = entropy / Math.log2(nonEmptyClusters);
    value = unitClamp(1 - normalisedEntropy);
  }

  return missing === 0
    ? measured(value)
    : degradedScore(value, `colour of ${missing} garment(s) (never analysed)`);
}

function computeWearUtilization(active: readonly WardrobeItem[], today: Date): Subscore {
  const eligible = active.filter((i) =>
    daysBetween(i.addedAt, today) >= MIN_AGE_FOR_UTILIZATION_DAYS
  );
  if (eligible.length === 0) {
    // §5.5 excludes items under 30 days from the denominator "because they
    // haven't had a fair chance to be worn yet" — a wardrobe that is ENTIRELY
    // under 30 days old (a brand-new closet import) gets that same benefit of
    // the doubt rather than an empty-mean 0, which would read as "you never
    // wear anything" about a wardrobe nobody has had time to wear yet.
    return degradedScore(0.5, "wear history (every active item is under 30 days old)");
  }
  const wornRecently =
    eligible.filter((i) =>
      i.lastWornAt !== null && daysBetween(i.lastWornAt, today) <= WEAR_WINDOW_DAYS
    ).length;
  const value = wornRecently / eligible.length;
  return active.length === eligible.length ? measured(value) : degradedScore(
    value,
    `${active.length - eligible.length} garment(s) too new to judge rotation (<30 days)`,
  );
}

/** §5.6: weighted by `itemVersatility_i`, per the doc's own reasoning — a damaged workhorse should count for more than a damaged rarely-worn accessory. */
function computeCondition(
  active: readonly WardrobeItem[],
  rawVersatilityByItemId: ReadonlyMap<string, number>,
): Subscore {
  if (active.length === 0) return degradedScore(1, "any garments to assess condition for");

  let weightedSum = 0;
  let weightTotal = 0;
  let plainSum = 0;
  let unassessedCount = 0;

  for (const item of active) {
    const value = item.condition === null
      ? UNKNOWN_CONDITION_PRIOR
      : CONDITION_VALUE[item.condition];
    if (item.condition === null) unassessedCount++;
    const weight = rawVersatilityByItemId.get(item.id) ?? 0;
    weightedSum += weight * value;
    weightTotal += weight;
    plainSum += value;
  }

  // No item has any measured versatility (e.g. a wardrobe too sparse for any
  // outfit to clear §5.1's threshold at all) — weighting by an all-zero
  // vector is undefined, not zero, so fall back to an unweighted mean rather
  // than silently returning 0 for a wardrobe whose garments might all be
  // brand new.
  const value = weightTotal > 0 ? weightedSum / weightTotal : plainSum / active.length;

  return unassessedCount === 0
    ? measured(value)
    : degradedScore(value, `condition of ${unassessedCount} garment(s) (never assessed)`);
}

function toRedundancyItem(item: WardrobeItem): RedundancyItem {
  return {
    id: item.id,
    category: item.category,
    role: item.role,
    primaryColorLab: item.primaryColor ? labFromLCh(item.primaryColor) : null,
    formalityScore: item.formalityScore,
    fit: item.fit,
    materials: item.materials,
    seasonality: item.seasonality,
  };
}

/** §5.7 — inverted §7.1: low redundancy is good wardrobe health. */
function computeRedundancyControl(active: readonly WardrobeItem[]): Subscore {
  if (active.length === 0) return measured(1);
  const asRedundancyItems = active.map(toRedundancyItem);
  const scores = asRedundancyItems.map((item) => redundancyScore(item, asRedundancyItems));
  const meanRedundancy = scores.reduce((s, v) => s + v, 0) / scores.length;
  return measured(unitClamp(1 - meanRedundancy));
}

/**
 * §5's composite: the seven weighted components above, confidence-damped.
 *
 * `today` is a parameter, not `new Date()` — every scoring function in this
 * package is a pure function of its inputs (this file's own header line one
 * rule), and §5.5/§5.9 are the two components that would otherwise reach for
 * a clock.
 */
export function computeWardrobeScore(
  items: readonly WardrobeItem[],
  today: Date,
  context: WardrobeContext = {},
): WardrobeScoreResult {
  const active = items.filter((i) => i.archivedAt === null);
  const n = active.length;

  const emptyComponents: Record<WardrobeComponentName, Subscore> = {
    versatility: degradedScore(0, "any garments (empty wardrobe)"),
    fitConfidence: degradedScore(0, "any garments (empty wardrobe)"),
    occasionCoverage: degradedScore(0, "any garments (empty wardrobe)"),
    colorCohesion: degradedScore(0, "any garments (empty wardrobe)"),
    wearUtilization: degradedScore(0, "any garments (empty wardrobe)"),
    condition: degradedScore(0, "any garments (empty wardrobe)"),
    redundancyControl: degradedScore(0, "any garments (empty wardrobe)"),
  };

  if (n === 0) {
    // §8's "0 items" row and §5.9's own text: a 0 here would read as "your
    // wardrobe is bad," which is false — there is no wardrobe yet. `null` is
    // the UI's signal to show the empty-state CTA instead of a number.
    return {
      score: null,
      rawComposite: null,
      confidence: 0,
      components: emptyComponents,
      degraded: ["any garments (empty wardrobe)"],
      activeItemCount: 0,
    };
  }

  const weights = normaliseWeights(context.weights);

  const versatility = computeVersatility(active, context.compatibilityWeights);
  const fitConfidence = computeFitConfidence(active, context);
  const occasionCoverage = computeOccasionCoverage(context);
  const colorCohesion = computeColorCohesion(active);
  const wearUtilization = computeWearUtilization(active, today);
  const condition = computeCondition(active, versatility.rawByItemId);
  const redundancyControl = computeRedundancyControl(active);

  const components: Record<WardrobeComponentName, Subscore> = {
    versatility: versatility.component,
    fitConfidence,
    occasionCoverage,
    colorCohesion,
    wearUtilization,
    condition,
    redundancyControl,
  };

  let rawComposite = 0;
  for (const [name, weight] of Object.entries(weights) as [WardrobeComponentName, number][]) {
    rawComposite += weight * unitClamp(components[name].value);
  }
  rawComposite *= 100;

  const n0 = context.n0 ?? DEFAULT_N0;
  const dampingAnchor = context.dampingAnchor ?? DEFAULT_DAMPING_ANCHOR;
  const confidence = confidenceOf(n, n0);
  const score = Math.round(dampedScore(rawComposite, n, n0, dampingAnchor));

  const degraded = [...new Set(Object.values(components).flatMap((c) => c.degraded))];

  return {
    score: Math.min(100, Math.max(0, score)),
    rawComposite,
    confidence,
    components,
    degraded,
    activeItemCount: n,
  };
}
