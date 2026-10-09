import { assertEquals } from "@std/assert";
import {
  coWearContext,
  dressCodeCenter,
  formalityCenter,
  inferRequestFormality,
  resolveTargetFormality,
} from "./scoringContext.ts";
import { coWearKey } from "../_shared/scoring/subscores/context.ts";
import { rolePairKey } from "../_shared/scoring/roleWeights.ts";

Deno.test("scoring context maps quiz and occasion formality to scorer scale", () => {
  assertEquals(formalityCenter("very_casual"), 0);
  assertEquals(formalityCenter("balanced"), 50);
  assertEquals(formalityCenter("very_formal"), 100);
  assertEquals(dressCodeCenter("business_casual"), 50);
  assertEquals(dressCodeCenter("black_tie"), 100);
  assertEquals(dressCodeCenter("unknown"), null);
  assertEquals(resolveTargetFormality("formal", "gym workout"), 75);
  assertEquals(resolveTargetFormality(null, "gym workout"), 0);
});

Deno.test("natural language request uses deterministic event formality vocabulary", () => {
  assertEquals(inferRequestFormality("black tie gala tonight"), 100);
  assertEquals(inferRequestFormality("a formal dinner"), 75);
  assertEquals(inferRequestFormality("client meeting"), 75);
  assertEquals(inferRequestFormality("make it dressy"), 75);
  assertEquals(inferRequestFormality("conference at work"), 50);
  assertEquals(inferRequestFormality("smart casual for the office"), 50);
  assertEquals(inferRequestFormality("dinner at a restaurant"), 25);
  assertEquals(inferRequestFormality("make it more casual"), 25);
  assertEquals(inferRequestFormality("not formal, just casual"), 25);
  assertEquals(inferRequestFormality("not formal"), null);
  assertEquals(inferRequestFormality("gym workout"), 0);
  assertEquals(inferRequestFormality("no gym, a work outfit"), 50);
  assertEquals(inferRequestFormality("What should I wear? Date: today; Style: formal"), null);
  assertEquals(inferRequestFormality("something comfortable"), null);
});

Deno.test("co-wear context counts positive history, role fallback, and ignores null/product slots", () => {
  const result = coWearContext(
    new Set(["top-a", "bottom-a"]),
    [{ outfitId: "worn", rating: 5 }, { outfitId: "worn-bad", rating: 1 }],
    [
      { outfitId: "worn", closetItemId: "top-a", category: "top" },
      { outfitId: "worn", closetItemId: "bottom-a", category: "bottom" },
      { outfitId: "worn", closetItemId: null, category: "shoes" },
      { outfitId: "worn-bad", closetItemId: "top-a", category: "top" },
      { outfitId: "worn-bad", closetItemId: "bottom-a", category: "bottom" },
      { outfitId: "not-worn", closetItemId: "top-a", category: "top" },
      { outfitId: "not-worn", closetItemId: "bottom-a", category: "bottom" },
    ],
  );
  assertEquals(result.coWear?.get(coWearKey("top-a", "bottom-a")), {
    totalCoWears: 2,
    positiveCoWears: 1,
  });
  assertEquals(result.coWearByRole?.get(rolePairKey("top", "bottom")), {
    totalCoWears: 2,
    positiveCoWears: 1,
  });
});
