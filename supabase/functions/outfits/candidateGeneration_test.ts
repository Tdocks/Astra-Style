import { assert, assertEquals } from "@std/assert";
import { generateCandidateOutfits } from "./candidateGeneration.ts";
import { classifyNeutral, rgbToLCh } from "../_shared/scoring/colorSpace.ts";
import type { AvailabilityState, LaundryState, ScorableItem } from "../_shared/scoring/types.ts";

function hex(value: string) {
  const v = Number.parseInt(value, 16);
  return { r: (v >> 16) & 255, g: (v >> 8) & 255, b: v & 255 };
}

function garment(
  id: string,
  role: ScorableItem["role"],
  over: Partial<ScorableItem> & { colorHex?: string } = {},
): ScorableItem {
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
    formalityScore: 50,
    fit: "regular",
    seasonality: [],
    warmthScore: null,
    waterResistanceScore: null,
    laundryState: "clean",
    availabilityState: "available",
    ...rest,
  };
}

/**
 * A closet with 2 tops, 2 bottoms, 2 pairs of shoes — enough to produce >1
 * distinct outfit. Formality/fit deliberately differ between the two items
 * in each role so the pair does not accidentally land in the same §6.3
 * equivalence class (that collapse is exercised deliberately, and
 * separately, by the near-duplicate test below).
 */
function smallCloset(): ScorableItem[] {
  return [
    garment("top-1", "top", { colorHex: "1F2A44", formalityScore: 70, fit: "tailored" }),
    garment("top-2", "top", { colorHex: "5C4433", formalityScore: 30, fit: "relaxed" }),
    garment("bottom-1", "bottom", { colorHex: "36393D", formalityScore: 70, fit: "tailored" }),
    garment("bottom-2", "bottom", { colorHex: "C8BEA5", formalityScore: 30, fit: "relaxed" }),
    garment("shoes-1", "shoes", { colorHex: "3B2A20", formalityScore: 70, fit: "regular" }),
    garment("shoes-2", "shoes", { colorHex: "F5F3EE", formalityScore: 20, fit: "regular" }),
  ];
}

const NO_LOCKS = new Set<string>();
const NO_EXCLUSIONS = new Set<string>();

Deno.test("returns the requested count when the closet supports it, each with top/bottom/shoes", () => {
  const outfits = generateCandidateOutfits(smallCloset(), {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(outfits.length, 3);
  for (const outfit of outfits) {
    const roles = outfit.items.map((i) => i.role);
    assert(roles.includes("top"));
    assert(roles.includes("bottom"));
    assert(roles.includes("shoes"));
  }
});

Deno.test("outfits are ranked best-score-first", () => {
  const outfits = generateCandidateOutfits(smallCloset(), {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  for (let i = 1; i < outfits.length; i++) {
    assert(outfits[i - 1]!.score.score >= outfits[i]!.score.score);
  }
});

Deno.test("a missing required role produces no outfits", () => {
  const closet = smallCloset().filter((i) => i.role !== "shoes");
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(outfits, []);
});

Deno.test("an empty closet produces no outfits, not an error", () => {
  const outfits = generateCandidateOutfits([], {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(outfits, []);
});

Deno.test("desiredCount of 0 returns nothing", () => {
  const outfits = generateCandidateOutfits(smallCloset(), {
    desiredCount: 0,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(outfits, []);
});

Deno.test("an unwearable item is filtered out before any combination is built", () => {
  const closet = [
    ...smallCloset(),
    garment("dirty-top", "top", { laundryState: "laundry" as LaundryState }),
    garment("lost-shoe", "shoes", { availabilityState: "lost" as AvailabilityState }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 6,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  for (const outfit of outfits) {
    assert(!outfit.items.some((i) => i.id === "dirty-top"));
    assert(!outfit.items.some((i) => i.id === "lost-shoe"));
  }
});

Deno.test("a locked item appears in every returned outfit", () => {
  const outfits = generateCandidateOutfits(smallCloset(), {
    desiredCount: 3,
    lockedItemIds: new Set(["top-2"]),
    excludedItemIds: NO_EXCLUSIONS,
  });
  assert(outfits.length > 0);
  for (const outfit of outfits) {
    assert(outfit.items.some((i) => i.id === "top-2"));
  }
});

Deno.test("an excluded item never appears in any returned outfit", () => {
  const outfits = generateCandidateOutfits(smallCloset(), {
    desiredCount: 6,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: new Set(["shoes-1"]),
  });
  for (const outfit of outfits) {
    assert(!outfit.items.some((i) => i.id === "shoes-1"));
  }
});

Deno.test("locking an item that is also excluded is an unsatisfiable request and returns nothing", () => {
  const outfits = generateCandidateOutfits(smallCloset(), {
    desiredCount: 3,
    lockedItemIds: new Set(["top-1"]),
    excludedItemIds: new Set(["top-1"]),
  });
  assertEquals(outfits, []);
});

Deno.test("locking an unwearable item is unsatisfiable and returns nothing", () => {
  const closet = [
    ...smallCloset(),
    garment("dirty-top", "top", { laundryState: "laundry" as LaundryState }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 3,
    lockedItemIds: new Set(["dirty-top"]),
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(outfits, []);
});

Deno.test("locking a fragrance-category item is unsatisfiable - fragrance has no scoring role", () => {
  const outfits = generateCandidateOutfits(smallCloset(), {
    desiredCount: 3,
    lockedItemIds: new Set(["a-fragrance-id-that-was-never-mapped"]),
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(outfits, []);
});

Deno.test("near-duplicate outfits collapse to one - two functionally identical white tees", () => {
  const closet = [
    garment("navy-shirt", "top", { colorHex: "1F2A44", formalityScore: 70, fit: "tailored" }),
    garment("white-tee-a", "top", { colorHex: "F2F0EB", formalityScore: 20, fit: "regular" }),
    garment("white-tee-b", "top", { colorHex: "F2F0EB", formalityScore: 21, fit: "regular" }),
    garment("chino", "bottom", { colorHex: "C8BEA5", formalityScore: 50, fit: "tailored" }),
    garment("oxford", "shoes", { colorHex: "3B2A20", formalityScore: 70, fit: "regular" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 10,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  const usesWhiteTee = outfits.filter((o) =>
    o.items.some((i) => i.id === "white-tee-a" || i.id === "white-tee-b")
  );
  assertEquals(
    usesWhiteTee.length,
    1,
    "the two white tees should collapse into one counted outfit",
  );
});

Deno.test("every generated outfit carries a non-empty reason and a full breakdown", () => {
  const outfits = generateCandidateOutfits(smallCloset(), {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  for (const outfit of outfits) {
    assert(outfit.reason.length > 0);
    assertEquals(typeof outfit.score.score, "number");
  }
});

Deno.test("generation is deterministic for the same inputs", () => {
  const first = generateCandidateOutfits(smallCloset(), {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  }).map((o) => o.items.map((i) => i.id));
  const second = generateCandidateOutfits(smallCloset(), {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  }).map((o) => o.items.map((i) => i.id));
  assertEquals(first, second);
});

Deno.test("an outerwear item is included only when it earns its place, never forced", () => {
  const closet = [
    ...smallCloset(),
    garment("jacket", "outerwear", { colorHex: "1F2A44" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 6,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  for (const outfit of outfits) {
    const roles = outfit.items.map((i) => i.role);
    assert(roles.includes("top") && roles.includes("bottom") && roles.includes("shoes"));
  }
});

Deno.test("a locked outerwear item appears in every result once outerwear is requested", () => {
  const closet = [
    ...smallCloset(),
    garment("jacket", "outerwear", { colorHex: "1F2A44" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 4,
    lockedItemIds: new Set(["jacket"]),
    excludedItemIds: NO_EXCLUSIONS,
  });
  assert(outfits.length > 0);
  for (const outfit of outfits) {
    assert(outfit.items.some((i) => i.id === "jacket"));
  }
});

Deno.test("at most two accessories are included per outfit", () => {
  const closet = [
    ...smallCloset(),
    garment("belt", "accessory", { colorHex: "5C4433" }),
    garment("watch", "accessory", { colorHex: "111111" }),
    garment("scarf", "accessory", { colorHex: "9B3A2E" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 6,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  for (const outfit of outfits) {
    const accessoryCount = outfit.items.filter((i) => i.role === "accessory").length;
    assert(accessoryCount <= 2);
  }
});

Deno.test("locking multiple accessories guarantees all of them appear together", () => {
  const closet = [
    ...smallCloset(),
    garment("belt", "accessory", { colorHex: "5C4433" }),
    garment("watch", "accessory", { colorHex: "111111" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 3,
    lockedItemIds: new Set(["belt", "watch"]),
    excludedItemIds: NO_EXCLUSIONS,
  });
  assert(outfits.length > 0);
  for (const outfit of outfits) {
    assert(outfit.items.some((i) => i.id === "belt"));
    assert(outfit.items.some((i) => i.id === "watch"));
  }
});

const NOON = new Date("2026-08-22T12:00:00.000Z");
const AN_HOUR_AGO = new Date("2026-08-22T11:00:00.000Z");
const YESTERDAY_MORNING = new Date("2026-08-21T11:00:00.000Z"); // 25h before NOON

Deno.test("a recently worn top is dropped when the role has another", () => {
  const closet = [
    garment("top-1", "top", {
      colorHex: "1F2A44",
      formalityScore: 70,
      fit: "tailored",
      lastWornAt: AN_HOUR_AGO,
    }),
    garment("top-2", "top", { colorHex: "5C4433", formalityScore: 30, fit: "relaxed" }),
    garment("bottom-1", "bottom", { colorHex: "36393D", formalityScore: 70, fit: "tailored" }),
    garment("shoes-1", "shoes", { colorHex: "3B2A20", formalityScore: 70, fit: "regular" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
    now: NOON,
  });
  assert(outfits.length > 0);
  for (const outfit of outfits) {
    assert(outfit.items.some((i) => i.id === "top-2"));
    assert(!outfit.items.some((i) => i.id === "top-1"));
  }
});

Deno.test("the only item in a role stays even if it was worn an hour ago", () => {
  const closet = [
    garment("top-1", "top", { colorHex: "1F2A44", lastWornAt: AN_HOUR_AGO }),
    garment("bottom-1", "bottom", { colorHex: "36393D" }),
    garment("shoes-1", "shoes", { colorHex: "3B2A20" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 1,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
    now: NOON,
  });
  assertEquals(outfits.length, 1);
  assert(outfits[0]!.items.some((i) => i.id === "top-1"));
});

Deno.test("when every item in a role was worn recently, outfits still generate", () => {
  const closet = [
    garment("top-1", "top", {
      colorHex: "1F2A44",
      formalityScore: 70,
      fit: "tailored",
      lastWornAt: AN_HOUR_AGO,
    }),
    garment("top-2", "top", {
      colorHex: "5C4433",
      formalityScore: 30,
      fit: "relaxed",
      lastWornAt: AN_HOUR_AGO,
    }),
    garment("bottom-1", "bottom", { colorHex: "36393D", formalityScore: 70, fit: "tailored" }),
    garment("shoes-1", "shoes", { colorHex: "3B2A20", formalityScore: 70, fit: "regular" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 2,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
    now: NOON,
  });
  assert(outfits.length > 0);
});

Deno.test("a wear older than a day is not rotated out", () => {
  const closet = [
    garment("top-1", "top", {
      colorHex: "1F2A44",
      formalityScore: 70,
      fit: "tailored",
      lastWornAt: YESTERDAY_MORNING,
    }),
    garment("top-2", "top", { colorHex: "5C4433", formalityScore: 30, fit: "relaxed" }),
    garment("bottom-1", "bottom", { colorHex: "36393D", formalityScore: 70, fit: "tailored" }),
    garment("shoes-1", "shoes", { colorHex: "3B2A20", formalityScore: 70, fit: "regular" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 6,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
    now: NOON,
  });
  assert(outfits.some((outfit) => outfit.items.some((i) => i.id === "top-1")));
});

Deno.test("a locked recently-worn item is not rotated out", () => {
  const closet = [
    garment("top-1", "top", {
      colorHex: "1F2A44",
      formalityScore: 70,
      fit: "tailored",
      lastWornAt: AN_HOUR_AGO,
    }),
    garment("top-2", "top", { colorHex: "5C4433", formalityScore: 30, fit: "relaxed" }),
    garment("bottom-1", "bottom", { colorHex: "36393D", formalityScore: 70, fit: "tailored" }),
    garment("shoes-1", "shoes", { colorHex: "3B2A20", formalityScore: 70, fit: "regular" }),
  ];
  const outfits = generateCandidateOutfits(closet, {
    desiredCount: 3,
    lockedItemIds: new Set(["top-1"]),
    excludedItemIds: NO_EXCLUSIONS,
    now: NOON,
  });
  assert(outfits.length > 0);
  for (const outfit of outfits) {
    assert(outfit.items.some((i) => i.id === "top-1"));
  }
});
