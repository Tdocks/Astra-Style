import { assertEquals } from "@std/assert";
import { coWearKey } from "./subscores/context.ts";
import {
  coWearContext,
  loadOwnedPreferenceCoWearContext,
  preferenceContextFromRow,
} from "./ownedScoringContext.ts";
import { rolePairKey } from "./roleWeights.ts";

Deno.test("owned context loader passes the caller through and combines preference and rated wear data", async () => {
  const calls: string[] = [];
  const result = await loadOwnedPreferenceCoWearContext(
    {
      readPreferences: (userId) => {
        calls.push(`preferences:${userId}`);
        return Promise.resolve({
          preferredColors: ["navy"],
          avoidedColors: [],
          preferredFit: "regular",
          formalityPreferenceCenter: 50,
        });
      },
      listWearHistory: (userId) => {
        calls.push(`wears:${userId}`);
        return Promise.resolve([
          { outfitId: "good-outfit", rating: 5 },
          { outfitId: "bad-outfit", rating: 1 },
        ]);
      },
      listWornOutfitItems: (userId, outfitIds) => {
        calls.push(`items:${userId}:${outfitIds.join(",")}`);
        return Promise.resolve([
          { outfitId: "good-outfit", closetItemId: "top-1", category: "top" },
          { outfitId: "good-outfit", closetItemId: "bottom-1", category: "bottom" },
          { outfitId: "bad-outfit", closetItemId: "top-1", category: "top" },
          { outfitId: "bad-outfit", closetItemId: "bottom-1", category: "bottom" },
        ]);
      },
    },
    "caller-1",
    new Set(["top-1", "bottom-1"]),
  );

  assertEquals(calls.slice(0, 2).sort(), ["preferences:caller-1", "wears:caller-1"]);
  assertEquals(calls[2], "items:caller-1:good-outfit,bad-outfit");
  assertEquals(result.preferences?.preferredColors, ["navy"]);
  assertEquals(result.coWear?.get(coWearKey("top-1", "bottom-1")), {
    totalCoWears: 2,
    positiveCoWears: 1,
  });
  assertEquals(result.coWearByRole?.get(rolePairKey("top", "bottom")), {
    totalCoWears: 2,
    positiveCoWears: 1,
  });
  assertEquals("weather" in result, false);
  assertEquals("targetFormalityScore" in result, false);
});

Deno.test("owned context loader avoids querying outfit items when there is no wear history", async () => {
  let itemReads = 0;
  const result = await loadOwnedPreferenceCoWearContext(
    {
      readPreferences: () => Promise.resolve(undefined),
      listWearHistory: () => Promise.resolve([]),
      listWornOutfitItems: () => {
        itemReads++;
        return Promise.resolve([]);
      },
    },
    "caller-1",
    new Set(),
  );
  assertEquals(itemReads, 0);
  assertEquals(result.preferences, undefined);
  assertEquals(result.coWear?.size, 0);
  assertEquals(result.coWearByRole?.size, 0);
});

Deno.test("preference parser rejects malformed values while preserving supported quiz fields", () => {
  assertEquals(
    preferenceContextFromRow({
      preferred_colors: ["navy", 42],
      avoided_colors: ["orange"],
      preferred_fit: "relaxed",
      formality_preference: "formal",
    }),
    {
      preferredColors: ["navy"],
      avoidedColors: ["orange"],
      preferredFit: "relaxed",
      formalityPreferenceCenter: 75,
    },
  );
});

Deno.test("co-wear ignores unworn outfits and null garment slots", () => {
  const result = coWearContext(
    new Set(["top-1", "bottom-1"]),
    [{ outfitId: "worn", rating: 5 }],
    [
      { outfitId: "worn", closetItemId: "top-1", category: "top" },
      { outfitId: "worn", closetItemId: "bottom-1", category: "bottom" },
      { outfitId: "worn", closetItemId: null, category: "shoes" },
      { outfitId: "unworn", closetItemId: "top-1", category: "top" },
      { outfitId: "unworn", closetItemId: "bottom-1", category: "bottom" },
    ],
  );
  assertEquals(result.coWear?.get(coWearKey("top-1", "bottom-1")), {
    totalCoWears: 1,
    positiveCoWears: 1,
  });
});
