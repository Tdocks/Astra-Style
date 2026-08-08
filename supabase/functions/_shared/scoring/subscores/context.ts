/**
 * The four components that read the world rather than the pairing:
 * season/weather (§2.5, 0.10), user preference (§2.6, 0.10), historical co-wear
 * (§2.7, 0.10) and occasion relevance (§2.8, 0.05). Plus availability (§2.9,
 * 0.05), which is a filter first and a score second.
 *
 * Together they are 0.40 of the compatibility weight and every one of them has
 * a cold-start prior, because a man on his first morning has no wear history,
 * may not have granted location, and did not say what occasion he is dressing
 * for. The priors are the doc's, and each one is chosen to be neither a
 * punishment nor a promise — see the comment on each.
 */

import {
  type CoWearStat,
  degradedScore,
  measured,
  type ScorableItem,
  type ScoringContext,
  type Subscore,
  unitClamp,
} from "../types.ts";
import { aggregatePairs, rolePairKey } from "../roleWeights.ts";

// ── §2.5 season and weather ─────────────────────────────────────────────────

/** §2.5's prior when no forecast was available. */
export const NO_WEATHER_PRIOR = 0.75;

/** The warmth→ideal-temperature endpoints, on the COLUMN's 0–100 scale. */
const WARMTH_0_IDEAL_C = 30;
const WARMTH_MAX_IDEAL_C = -5;
/** §2.5's tolerance: 20°C away from ideal is a total miss. */
const TEMP_TOLERANCE_C = 20;
/** Below this water resistance, rain hurts. §2.5's "< 3" on the 0–100 column. */
const RAIN_VULNERABLE_BELOW = 30;
const RAIN_LIKELY_ABOVE = 0.4;

/**
 * §2.5's mapping, rescaled to the shipped column.
 *
 * The doc states this on a 0–10 warmth scale; the column is 0–100 (see
 * `types.ts`, note 1). Read on the doc's scale a heavy overcoat at 85 would
 * map to an ideal temperature of −267°C, and every winter garment would score
 * zero against every forecast on earth.
 */
export function idealTemperatureC(warmthScore: number): number {
  const t = unitClamp(warmthScore / 100);
  return WARMTH_0_IDEAL_C + t * (WARMTH_MAX_IDEAL_C - WARMTH_0_IDEAL_C);
}

/**
 * §2.5 — a simple mean across garments, NOT a pairwise aggregate.
 *
 * Weather suits a garment or it does not; it is not a relationship between two
 * of them. A wool overcoat is wrong for 28°C whether or not the trousers agree.
 */
export function seasonWeatherSubscore(
  items: readonly ScorableItem[],
  context: ScoringContext,
): Subscore {
  if (!context.weather) {
    // A mild positive prior, not a penalty. The user did not withhold the
    // forecast; we simply do not have it. Kyra is required to omit every
    // weather sentence when this fires — see docs/06 §6.
    return degradedScore(NO_WEATHER_PRIOR, "today's weather (no forecast available)");
  }
  const scoreable = items.filter((i) => i.warmthScore !== null);
  if (scoreable.length === 0) {
    return degradedScore(NO_WEATHER_PRIOR, "warmth ratings for every garment in this outfit");
  }

  const { temperatureC, precipitationProbability } = context.weather;
  const rainLikely = precipitationProbability > RAIN_LIKELY_ABOVE;

  let total = 0;
  for (const item of scoreable) {
    const ideal = idealTemperatureC(item.warmthScore!);
    let fit = 1 - unitClamp(Math.abs(ideal - temperatureC) / TEMP_TOLERANCE_C);

    // Only the garments that actually meet the rain. A shirt under a coat is
    // not what gets wet.
    const exposed = item.role === "outerwear" || item.role === "shoes";
    if (rainLikely && exposed && (item.waterResistanceScore ?? 0) < RAIN_VULNERABLE_BELOW) {
      fit *= 0.6;
    }
    total += fit;
  }

  const value = total / scoreable.length;
  const unrated = items.length - scoreable.length;
  return unrated === 0
    ? measured(value)
    : degradedScore(value, `warmth ratings for ${unrated} garment(s) in this outfit`);
}

// ── §2.6 user preference ────────────────────────────────────────────────────

/** §2.6's cold-start prior. */
export const NO_PREFERENCE_PRIOR = 0.7;
/** §2.6's override for a colour the user asked never to see. */
const AVOIDED_COLOR_SCORE = 0.1;

/**
 * §2.6 — per garment, then a plain mean.
 *
 * Preference is about a man's relationship to each garment, not to a pairing,
 * so this does not go through §2.1's weights.
 *
 * The cold-start prior is 0.7 and the doc is explicit that it is neither 0.5
 * nor 1.0. Half would read as the app distrusting a brand-new closet; one would
 * claim a personalisation it has not earned and would be a lie the first time
 * it was wrong. 0.7 is "no reason to think otherwise".
 *
 * NOT IMPLEMENTED HERE: the implicit half of §2.6 — embedding-similarity over
 * `style_feedback` with a 90-day recency half-life. `style_feedback` has no
 * rows and closet embeddings are not populated, so there is nothing to average.
 * The doc's own rule for that case is to redistribute the weight to the
 * explicit term, which is what happens: `explicitScore` IS the score. When
 * feedback exists this becomes `0.6 × explicit + 0.4 × implicit`.
 */
export function userPreferenceSubscore(
  items: readonly ScorableItem[],
  context: ScoringContext,
  colorNameOf: (item: ScorableItem) => string | null = () => null,
): Subscore {
  const prefs = context.preferences;
  if (!prefs) {
    return degradedScore(NO_PREFERENCE_PRIOR, "your stated colour, fit and formality preferences");
  }

  const avoided = new Set(prefs.avoidedColors.map((c) => c.toLowerCase()));
  const degraded: string[] = ["what you have worn and rated so far (no feedback history yet)"];

  let total = 0;
  for (const item of items) {
    const name = colorNameOf(item)?.toLowerCase() ?? null;
    if (name !== null && avoided.has(name)) {
      // A hard override, per §2.6: a man who said "never orange" should not be
      // talked into orange by a good silhouette score.
      total += AVOIDED_COLOR_SCORE;
      continue;
    }

    let score = 0.4;
    score += 0.3 * (prefs.preferredFit === null ? 0.6 : item.fit === prefs.preferredFit ? 1 : 0.6);
    if (prefs.formalityPreferenceCenter !== null && item.formalityScore !== null) {
      score += 0.3 * (1 - unitClamp(
        Math.abs(item.formalityScore - prefs.formalityPreferenceCenter) / 100,
      ));
    } else {
      // Neither known: the term contributes its midpoint rather than zero,
      // which would silently punish an unclassified garment.
      score += 0.3 * 0.6;
    }
    total += unitClamp(score);
  }

  const value = items.length === 0 ? NO_PREFERENCE_PRIOR : total / items.length;
  return degradedScore(value, ...degraded);
}

// ── §2.7 historical co-wear ─────────────────────────────────────────────────

/** §2.7's Beta prior. An untested pair starts at 2/3, not 1/2. */
const PRIOR_ALPHA = 2;
const PRIOR_BETA = 1;

export function coWearKey(idA: string, idB: string): string {
  return idA <= idB ? `${idA}|${idB}` : `${idB}|${idA}`;
}

function smoothed(stat: CoWearStat): number {
  return (stat.positiveCoWears + PRIOR_ALPHA) /
    (stat.totalCoWears + PRIOR_ALPHA + PRIOR_BETA);
}

/**
 * §2.7 — Bayesian-smoothed positive rate over prior wears.
 *
 * The optimistic prior is the point. Absence of negative history is not
 * evidence of a bad pairing, and a raw positive rate would structurally
 * disadvantage every new garment against the shirt a man has worn forty times.
 * A brand-new pair opens at 0.667 and moves from there.
 *
 * Falls back from the specific pair to the role pair, so a jacket bought
 * yesterday still inherits how this user's tops and bottoms generally go.
 */
export function coWearSubscore(
  items: readonly ScorableItem[],
  context: ScoringContext,
): Subscore {
  const specific = context.coWear;
  const byRole = context.coWearByRole;
  if (!specific && !byRole) {
    return degradedScore(
      smoothed({ totalCoWears: 0, positiveCoWears: 0 }),
      "what you have worn together before (no wear history yet)",
    );
  }

  let usedRoleFallback = false;
  const aggregate = aggregatePairs(items, (a, b) => {
    const exact = specific?.get(coWearKey(a.id, b.id));
    if (exact && exact.totalCoWears > 0) return smoothed(exact);
    const role = byRole?.get(rolePairKey(a.role, b.role));
    if (role && role.totalCoWears > 0) {
      usedRoleFallback = true;
      return smoothed(role);
    }
    usedRoleFallback = true;
    return smoothed({ totalCoWears: 0, positiveCoWears: 0 });
  });

  if (aggregate === null) {
    return degradedScore(
      smoothed({ totalCoWears: 0, positiveCoWears: 0 }),
      "a second garment to compare wear history against",
    );
  }
  return usedRoleFallback
    ? degradedScore(aggregate, "wear history for these specific garments together")
    : measured(aggregate);
}

// ── §2.8 occasion relevance ─────────────────────────────────────────────────

/** §2.8: no occasion asked about is not a reason to mark anything down. */
export const NO_OCCASION_PRIOR = 0.8;
const UNRELATED_OCCASION = 0.2;

/** §2.8's adjacency table. Unlisted pairs are unrelated. */
const ADJACENCY: ReadonlyMap<string, number> = new Map([
  ["business-casual|business-formal", 0.6],
  ["date-night|smart-casual", 0.7],
  ["athletic|everyday-casual", 0.5],
  ["everyday-casual|smart-casual", 0.6],
  ["business-casual|smart-casual", 0.7],
]);

function adjacencyKey(a: string, b: string): string {
  return a <= b ? `${a}|${b}` : `${b}|${a}`;
}

/**
 * §2.8 — how well the outfit suits the occasion asked about.
 *
 * `closet_items` has no `occasion_tags` column (see `types.ts`, note 4), so
 * item-level tags cannot be read at all today. Rather than score a match it
 * cannot compute, this returns the doc's own unconstrained-request default and
 * says which input is missing.
 */
export function occasionSubscore(
  context: ScoringContext,
  outfitOccasionTags: readonly string[] = [],
): Subscore {
  const target = context.targetOccasion;
  if (!target) {
    // The overwhelmingly common case: "what should I wear today". Marking an
    // outfit down for failing to match an occasion nobody named would be
    // penalising the user for not asking a narrower question.
    return measured(NO_OCCASION_PRIOR);
  }
  if (outfitOccasionTags.length === 0) {
    return degradedScore(
      NO_OCCASION_PRIOR,
      "occasion tags on these garments (no column stores them yet)",
    );
  }

  let best = UNRELATED_OCCASION;
  for (const tag of outfitOccasionTags) {
    if (tag === target) return measured(1);
    best = Math.max(best, ADJACENCY.get(adjacencyKey(tag, target)) ?? UNRELATED_OCCASION);
  }
  return measured(best);
}

// ── §2.9 availability ───────────────────────────────────────────────────────

/**
 * §2.9 — a mild preference for fresher rotation among items that PASSED the
 * wearability filter.
 *
 * `isWearable` in `types.ts` is the hard half and runs during candidate
 * generation: a dirty or unavailable garment is removed, never merely
 * down-weighted, because suggesting an outfit around a shirt in the laundry
 * basket is not a low-quality match, it is a wrong answer.
 *
 * This is the soft half. Everything here is wearable; clean simply beats
 * worn-once, so a man is nudged through his wardrobe rather than back into
 * yesterday's shirt.
 */
export function availabilitySubscore(items: readonly ScorableItem[]): Subscore {
  if (items.length === 0) return measured(1);
  const total = items.reduce(
    (sum, item) => sum + (item.laundryState === "clean" ? 1 : 0.75),
    0,
  );
  return measured(total / items.length);
}
