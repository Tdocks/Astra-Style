import { assertEquals } from "@std/assert";
import {
  type ClosetItemRow,
  LeastRecentlyWornScorer,
  SLICE_PLACEHOLDER_COMPATIBILITY_SCORE,
} from "./scorer.ts";

function item(
  id: string,
  category: ClosetItemRow["category"],
  lastWornAt: string | null,
): ClosetItemRow {
  return { id, category, last_worn_at: lastWornAt };
}

const NO_LOCKS = new Set<string>();
const NO_EXCLUSIONS = new Set<string>();

Deno.test("returns an empty list when a required role has no eligible items", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [item("top-1", "top", null)]; // no bottom, no shoes
  const result = scorer.generate(items, {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(result, []);
});

Deno.test("picks exactly one top + one bottom + one pair of shoes", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-1", "top", "2026-01-01T00:00:00Z"),
    item("bottom-1", "bottom", "2026-01-01T00:00:00Z"),
    item("shoes-1", "shoes", "2026-01-01T00:00:00Z"),
  ];
  const result = scorer.generate(items, {
    desiredCount: 3,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(result.length, 1);
  assertEquals(result[0]?.itemIds, ["top-1", "bottom-1", "shoes-1"]);
  assertEquals(result[0]?.compatibilityScore, SLICE_PLACEHOLDER_COMPATIBILITY_SCORE);
});

Deno.test("prefers never-worn items over items with any recorded wear", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-recent", "top", "2026-07-27T00:00:00Z"),
    item("top-never-worn", "top", null),
    item("bottom-1", "bottom", null),
    item("shoes-1", "shoes", null),
  ];
  const result = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(result[0]?.itemIds.includes("top-never-worn"), true);
  assertEquals(result[0]?.itemIds.includes("top-recent"), false);
});

Deno.test("prefers the least-recently-worn item over a more recently worn one", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-older", "top", "2020-01-01T00:00:00Z"),
    item("top-newer", "top", "2026-01-01T00:00:00Z"),
    item("bottom-1", "bottom", null),
    item("shoes-1", "shoes", null),
  ];
  const result = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(result[0]?.itemIds.includes("top-older"), true);
});

Deno.test("respects excluded item ids", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-excluded", "top", null),
    item("top-fallback", "top", "2020-01-01T00:00:00Z"),
    item("bottom-1", "bottom", null),
    item("shoes-1", "shoes", null),
  ];
  const result = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: new Set(["top-excluded"]),
  });
  assertEquals(result[0]?.itemIds.includes("top-excluded"), false);
  assertEquals(result[0]?.itemIds.includes("top-fallback"), true);
});

Deno.test("returns an empty list when everything eligible for a role was excluded", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-1", "top", null),
    item("bottom-1", "bottom", null),
    item("shoes-1", "shoes", null),
  ];
  const result = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: new Set(["top-1"]),
  });
  assertEquals(result, []);
});

Deno.test("pins a locked item into every generated outfit", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-locked", "top", "2026-01-01T00:00:00Z"),
    item("top-other", "top", null),
    item("bottom-1", "bottom", null),
    item("bottom-2", "bottom", "2025-01-01T00:00:00Z"),
    item("shoes-1", "shoes", null),
    item("shoes-2", "shoes", "2025-01-01T00:00:00Z"),
  ];
  const result = scorer.generate(items, {
    desiredCount: 2,
    lockedItemIds: new Set(["top-locked"]),
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(result.length, 2);
  for (const outfit of result) {
    assertEquals(outfit.itemIds[0], "top-locked");
  }
});

Deno.test("caps generated outfits at the smallest unlocked role's item count", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-1", "top", null),
    item("top-2", "top", "2025-01-01T00:00:00Z"),
    item("top-3", "top", "2024-01-01T00:00:00Z"),
    item("bottom-1", "bottom", null), // only one bottom available
    item("shoes-1", "shoes", null),
    item("shoes-2", "shoes", "2025-01-01T00:00:00Z"),
  ];
  const result = scorer.generate(items, {
    desiredCount: 5,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(result.length, 1);
});

Deno.test("desiredCount of zero returns an empty list", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-1", "top", null),
    item("bottom-1", "bottom", null),
    item("shoes-1", "shoes", null),
  ];
  const result = scorer.generate(items, {
    desiredCount: 0,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  assertEquals(result, []);
});

Deno.test("the reason string clearly marks this as slice-scope placeholder scoring", () => {
  const scorer = new LeastRecentlyWornScorer();
  const items = [
    item("top-1", "top", null),
    item("bottom-1", "bottom", null),
    item("shoes-1", "shoes", null),
  ];
  const result = scorer.generate(items, {
    desiredCount: 1,
    lockedItemIds: NO_LOCKS,
    excludedItemIds: NO_EXCLUSIONS,
  });
  const reason = result[0]?.reason ?? "";
  assertEquals(reason.toLowerCase().includes("placeholder"), true);
});
