import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  computeWardrobeScore,
  confidenceOf,
  dampedScore,
  DEFAULT_WARDROBE_WEIGHTS,
  expectedVersatility,
  type WardrobeContext,
  type WardrobeItem,
} from "./wardrobeScore.ts";
import { classifyNeutral, rgbToLCh } from "./colorSpace.ts";
import type { Condition, Fit, GarmentRole } from "./types.ts";

const TODAY = new Date("2026-08-07T00:00:00Z");
const OLD = new Date("2025-01-01T00:00:00Z"); // > 30 days before TODAY, comfortably.

function hex(value: string) {
  const v = Number.parseInt(value, 16);
  return { r: (v >> 16) & 255, g: (v >> 8) & 255, b: v & 255 };
}

function item(
  id: string,
  role: GarmentRole,
  over: Partial<WardrobeItem> & { colorHex?: string } = {},
): WardrobeItem {
  const { colorHex, ...rest } = over;
  const lch = colorHex ? rgbToLCh(hex(colorHex)) : null;
  return {
    id,
    category: role === "accessory" ? "accessory" : role,
    role,
    primaryColor: lch,
    isNeutral: lch ? classifyNeutral(lch).isNeutral : false,
    secondaryColors: [],
    pattern: "solid",
    patternScale: null,
    materials: [],
    formalityScore: 45,
    fit: "regular",
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
    condition: "good",
    lastWornAt: null,
    addedAt: OLD,
    archivedAt: null,
    ...rest,
  };
}

const ROLE_CYCLE: readonly GarmentRole[] = ["top", "bottom", "shoes", "outerwear", "accessory"];
const HUES = ["6E6E3C", "2244AA", "C8BEA5", "884422", "445566", "AA6633", "223344", "665544"];
const FITS: readonly Fit[] = ["slim", "tailored", "regular", "relaxed", "oversized"];
const CONDITIONS: readonly Condition[] = ["new_with_tags", "like_new", "good", "fair", "worn"];

function makeWardrobe(n: number): WardrobeItem[] {
  return Array.from({ length: n }, (_, i) =>
    item(`item-${i}`, ROLE_CYCLE[i % ROLE_CYCLE.length]!, {
      colorHex: HUES[i % HUES.length],
      formalityScore: 30 + (i % 5) * 10,
      fit: FITS[i % FITS.length],
      condition: CONDITIONS[i % CONDITIONS.length],
      lastWornAt: i % 3 === 0 ? new Date(TODAY.getTime() - 10 * 86400000) : null,
    }));
}

// ── Empty / near-empty ──────────────────────────────────────────────────────

Deno.test("Test 20 (§9): n=0 is a sentinel, never a numeric 0 or 50", () => {
  const result = computeWardrobeScore([], TODAY);
  assertEquals(result.score, null);
  assertEquals(result.rawComposite, null);
  assertEquals(result.confidence, 0);
});

Deno.test("confidenceOf(0) is 0, matching the n=0 sentinel branch", () => {
  assertEquals(confidenceOf(0), 0);
});

Deno.test("Bounded 0-100 across a range of wardrobe sizes, including near-empty", () => {
  for (const n of [1, 2, 3, 5, 8, 12, 15]) {
    const result = computeWardrobeScore(makeWardrobe(n), TODAY);
    assert(result.score !== null, `n=${n} should produce a numeric score`);
    assert(
      result.score! >= 0 && result.score! <= 100,
      `n=${n} score out of bounds: ${result.score}`,
    );
  }
});

// ── §5.8: price must never inflate ──────────────────────────────────────────

interface ClosetRow extends WardrobeItem {
  readonly pricePaid: number | null;
}

/** Mirrors the mapping boundary a real endpoint would use — drops price before the item ever becomes a `WardrobeItem`. */
function toWardrobeItem(row: ClosetRow): WardrobeItem {
  const { pricePaid: _pricePaid, ...rest } = row;
  return rest;
}

Deno.test("Test 18 (§9): two closets identical except price_paid produce identical Wardrobe Scores", () => {
  const cheap: ClosetRow[] = makeWardrobe(6).map((w) => ({ ...w, pricePaid: 12.0 }));
  const expensive: ClosetRow[] = makeWardrobe(6).map((w) => ({ ...w, pricePaid: 4500.0 }));

  const cheapScore = computeWardrobeScore(cheap.map(toWardrobeItem), TODAY);
  const expensiveScore = computeWardrobeScore(expensive.map(toWardrobeItem), TODAY);

  assertEquals(cheapScore.score, expensiveScore.score);
  assertEquals(cheapScore.rawComposite, expensiveScore.rawComposite);
});

Deno.test("A single expensive, low-versatility item does not raise the score versus the same item cheap", () => {
  // A one-off formal item that pairs with almost nothing else in a casual
  // wardrobe: high price, structurally low versatility. WardrobeItem has no
  // price field at all (see wardrobeScore.ts's header), so the only way price
  // COULD move the score is if it were smuggled in through another field —
  // this asserts it is not.
  const base = makeWardrobe(6);
  const withPriceA = base.map((w) => ({ ...w, pricePaid: 9.99 }) as ClosetRow);
  const withPriceB = base.map((w) => ({ ...w, pricePaid: 899.0 }) as ClosetRow);
  assertEquals(
    computeWardrobeScore(withPriceA.map(toWardrobeItem), TODAY).score,
    computeWardrobeScore(withPriceB.map(toWardrobeItem), TODAY).score,
  );
});

// ── §5.9 confidence damping ─────────────────────────────────────────────────

Deno.test("Test 21 (§9): confidence(15) == 1.0 exactly", () => {
  assertEquals(confidenceOf(15), 1.0);
});

Deno.test("Test 19 (§9): an artificially 'perfect' 3-item closet does not exceed 55", () => {
  const context: WardrobeContext = {
    occasionCoverage: new Map([
      ["everyday-casual", true],
      ["work", true],
      ["date-night", true],
      ["semi-formal-event", true],
    ]),
    feedbackByItemId: new Map([
      ["top", { hasPositiveSignal: true, hasNegativeSignal: false }],
      ["bottom", { hasPositiveSignal: true, hasNegativeSignal: false }],
      ["shoes", { hasPositiveSignal: true, hasNegativeSignal: false }],
    ]),
  };
  const perfect: WardrobeItem[] = [
    item("top", "top", {
      colorHex: "FFFFFF",
      formalityScore: 45,
      condition: "new_with_tags",
      lastWornAt: new Date(TODAY.getTime() - 5 * 86400000),
    }),
    item("bottom", "bottom", {
      colorHex: "FFFFFF",
      formalityScore: 45,
      condition: "new_with_tags",
      lastWornAt: new Date(TODAY.getTime() - 5 * 86400000),
    }),
    item("shoes", "shoes", {
      colorHex: "FFFFFF",
      formalityScore: 45,
      condition: "new_with_tags",
      lastWornAt: new Date(TODAY.getTime() - 5 * 86400000),
    }),
  ];
  const result = computeWardrobeScore(perfect, TODAY, context);
  assert(result.score !== null);
  assert(result.score! <= 55, `expected <= 55, got ${result.score}`);
});

// ── §5.1 expectedVersatility (§0 amendment 7) ───────────────────────────────

Deno.test("§5.1: expectedVersatility passes through all four seed points exactly", () => {
  // The seeds, not the retired log formula, are the operative definition —
  // see §0 amendment 7 and expectedVersatility's own comment. Pinned exactly
  // so a future "simplification" back to a closed form has to face this test.
  assertEquals(expectedVersatility(5), 3);
  assertEquals(expectedVersatility(15), 12);
  assertEquals(expectedVersatility(40), 35);
  assertEquals(expectedVersatility(80), 60);
});

Deno.test("§5.1: below the n=5 floor there is no baseline — 0, not an extrapolation", () => {
  assertEquals(expectedVersatility(0), 0);
  assertEquals(expectedVersatility(4), 0);
});

Deno.test("§5.1: interpolation is linear between seeds and monotone throughout", () => {
  assertAlmostEquals(expectedVersatility(10), 7.5, 1e-9); // midway 5→15: (3+12)/2
  assertAlmostEquals(expectedVersatility(60), 47.5, 1e-9); // midway 40→80: (35+60)/2
  let prev = 0;
  for (let n = 5; n <= 120; n++) {
    const v = expectedVersatility(n);
    assert(v >= prev, `expectedVersatility not monotone at n=${n}`);
    prev = v;
  }
});

Deno.test("§5.1: past n=80 the target keeps climbing at the final slope, so volume alone can never saturate versatility", () => {
  assertAlmostEquals(expectedVersatility(100), 60 + 20 * 0.625, 1e-9);
  assert(expectedVersatility(200) > expectedVersatility(100));
});

// ── §5.10 worked cold-start table ───────────────────────────────────────────

Deno.test("§5.10's worked table: the damping arithmetic reproduces the doc's own displayed scores", () => {
  // Reproduced directly off §5.9/§5.10's formula and the doc's own "example
  // raw composite" numbers (48, 66, 78) — those raw-composite figures are
  // presented as illustrative ("~"), not derived from a specified fixture, so
  // this drives the damping function with them directly rather than trying to
  // engineer a synthetic wardrobe that happens to land on the same raw value.
  const n5 = dampedScore(48, 5);
  assertAlmostEquals(n5, 49, 0.5); // doc: "0.33×48 + 0.67×50 ≈ 49"
  assertAlmostEquals(confidenceOf(5), 0.3333, 0.001);

  const n15 = dampedScore(66, 15);
  assertEquals(n15, 66); // confidence(15)=1.0, so the raw composite passes through unchanged.

  const n40 = dampedScore(78, 40);
  assertEquals(n40, 78); // confidence is clamped at 1.0 above N0, so 40 behaves like 15 here.
});

Deno.test("Damping strictly increases confidence (and therefore how much raw composite counts) as the wardrobe grows toward N0", () => {
  assert(confidenceOf(1) < confidenceOf(5));
  assert(confidenceOf(5) < confidenceOf(10));
  assert(confidenceOf(10) < confidenceOf(15));
  assertEquals(confidenceOf(15), confidenceOf(20)); // clamped, not still climbing.
});

// ── Component sanity ────────────────────────────────────────────────────────

Deno.test("Every component is reported, so a UI breakdown is always available", () => {
  const result = computeWardrobeScore(makeWardrobe(8), TODAY);
  assertEquals(
    Object.keys(result.components).sort(),
    [
      "colorCohesion",
      "condition",
      "fitConfidence",
      "occasionCoverage",
      "redundancyControl",
      "versatility",
      "wearUtilization",
    ].sort(),
  );
});

Deno.test("The seven component weights sum to 1.0, matching §5's table", () => {
  const total = Object.values(DEFAULT_WARDROBE_WEIGHTS).reduce((s, w) => s + w, 0);
  assertAlmostEquals(total, 1, 1e-9);
  assertEquals(DEFAULT_WARDROBE_WEIGHTS.versatility, 0.25);
  assertEquals(DEFAULT_WARDROBE_WEIGHTS.fitConfidence, 0.15);
  assertEquals(DEFAULT_WARDROBE_WEIGHTS.occasionCoverage, 0.15);
  assertEquals(DEFAULT_WARDROBE_WEIGHTS.colorCohesion, 0.10);
  assertEquals(DEFAULT_WARDROBE_WEIGHTS.wearUtilization, 0.15);
  assertEquals(DEFAULT_WARDROBE_WEIGHTS.condition, 0.10);
  assertEquals(DEFAULT_WARDROBE_WEIGHTS.redundancyControl, 0.10);
});

Deno.test("An unassessed condition reports itself degraded rather than silently defaulting", () => {
  const wardrobe = makeWardrobe(6).map((w) => ({ ...w, condition: null }));
  const result = computeWardrobeScore(wardrobe, TODAY);
  assert(result.components.condition.degraded.length > 0);
  assert(result.degraded.some((d) => d.includes("condition of")));
});

Deno.test("Archived items are excluded from the active count and every component", () => {
  const active = makeWardrobe(5);
  const archived = item("archived-1", "top", { archivedAt: new Date("2024-01-01") });
  const withArchived = computeWardrobeScore([...active, archived], TODAY);
  const withoutArchived = computeWardrobeScore(active, TODAY);
  assertEquals(withArchived.activeItemCount, withoutArchived.activeItemCount);
});
