import { assert, assertEquals } from "@std/assert";
import type { ProductExtractionProvider } from "../_shared/providers/productExtraction.ts";
import { resolveColorName } from "../_shared/scoring/colorVocabulary.ts";
import type { RedundancyItem } from "../_shared/scoring/redundancy.ts";
import type { ScorableItem } from "../_shared/scoring/types.ts";
import { roleFor } from "../_shared/scoring/types.ts";
import type { ProductCandidateRow } from "./candidateMapper.ts";
import {
  handleListUnlocks,
  type OwnedGarment,
  type ProductsDependencies,
  UNLOCKS_CANDIDATE_CAP,
} from "./handler.ts";

const USER = "aaaaaaaa-0000-4000-8000-000000000001";
const resolvedBlack = resolveColorName("black");
if (resolvedBlack === null) throw new Error("expected black in the colour vocabulary");
const BLACK = resolvedBlack;

function scorable(
  id: string,
  category: ScorableItem["category"],
  over: Partial<ScorableItem> = {},
): ScorableItem {
  const role = roleFor(category);
  return {
    id,
    category,
    role: role ?? "top",
    primaryColor: BLACK.lch,
    isNeutral: BLACK.isNeutral,
    secondaryColors: [],
    pattern: "solid",
    patternScale: null,
    materials: ["cotton"],
    formalityScore: 40,
    fit: "regular",
    seasonality: [],
    warmthScore: 30,
    waterResistanceScore: 0,
    laundryState: "clean",
    availabilityState: "available",
    ...over,
  };
}

function owned(item: ScorableItem): OwnedGarment {
  const redundancy: RedundancyItem = {
    id: item.id,
    category: item.category,
    role: item.role,
    primaryColorLab: null,
    formalityScore: item.formalityScore,
    fit: item.fit,
    materials: item.materials,
    seasonality: item.seasonality,
  };
  return { scorable: item, redundancy };
}

function candidateRow(
  id: string,
  over: Partial<ProductCandidateRow> & { color?: string; fit?: string } = {},
): ProductCandidateRow {
  const { color, fit, attributes, ...rest } = over;
  return {
    id,
    canonical_url: `https://example.com/products/${id}`,
    retailer: "Example",
    brand: null,
    name: id,
    category: "shoes",
    price: 120,
    currency: "USD",
    image_url: null,
    affiliate_url: null,
    availability: {},
    attributes: {
      color: color ?? "black",
      fit: fit ?? "slim",
      formality_score: 40,
      ...(typeof attributes === "object" && attributes !== null
        ? attributes as Record<string, unknown>
        : {}),
    },
    sponsored: false,
    last_checked_at: null,
    ...rest,
  };
}

function deps(
  candidates: readonly ProductCandidateRow[],
  closet: readonly OwnedGarment[],
): ProductsDependencies {
  return {
    extractionProvider: {
      extractProduct: () => Promise.reject(new Error("unused")),
    } as ProductExtractionProvider,
    upsertCandidate: () => Promise.reject(new Error("unused")),
    fetchCandidate: () => Promise.resolve(null),
    fetchCloset: () => Promise.resolve([...closet]),
    fetchLifestyle: () => Promise.resolve({ monthlyBudget: null, dressCode: null }),
    fetchAlternatives: () => Promise.resolve([]),
    persistEvaluation: () => Promise.resolve({ created_at: "2026-08-22T00:00:00Z" }),
    fetchLatestEvaluatedCandidates: (_userID, limit) => Promise.resolve(candidates.slice(0, limit)),
    requestID: "req-unlocks",
  };
}

const TOP = owned(scorable("top-1", "top"));
const BOTTOM = owned(scorable("bottom-1", "bottom"));
const OWNED_SHOE = owned(scorable("shoe-owned", "shoes", {
  fit: "regular",
  formalityScore: 40,
}));

Deno.test("a novel shoe he already asked about is on the rail; a zero-unlock copy is not", async () => {
  const novel = candidateRow("shoe-novel", { color: "black", fit: "slim" });
  const duplicate = candidateRow("shoe-dup", { color: "black", fit: "regular" });
  const result = await handleListUnlocks(
    USER,
    deps([duplicate, novel], [TOP, BOTTOM, OWNED_SHOE]),
  );
  const ids = result.items.map((item) => item.candidate.id);
  assertEquals(ids.includes("shoe-dup"), false);
  assertEquals(ids.includes("shoe-novel"), true);
  assert(result.items[0]!.outfits_unlocked > 0);
});

Deno.test("sponsored is a label only: zeros drop, remaining rows sort by unlock count", async () => {
  const sponsoredZero = candidateRow("sponsored-zero", {
    color: "black",
    fit: "regular",
    sponsored: true,
  });
  const organicGap = candidateRow("organic-gap", { color: "black", fit: "slim" });
  const sponsoredGap = candidateRow("sponsored-gap", {
    color: "navy",
    fit: "oversized",
    sponsored: true,
  });
  const result = await handleListUnlocks(
    USER,
    deps([sponsoredZero, sponsoredGap, organicGap], [TOP, BOTTOM, OWNED_SHOE]),
  );
  const ids = result.items.map((item) => item.candidate.id);
  assertEquals(ids.includes("sponsored-zero"), false);
  const counts = result.items.map((item) => item.outfits_unlocked);
  assertEquals(counts, [...counts].sort((a, b) => b - a));
  for (let index = 1; index < result.items.length; index++) {
    const previous = result.items[index - 1]!;
    const current = result.items[index]!;
    if (current.candidate.sponsored && !previous.candidate.sponsored) {
      assert(previous.outfits_unlocked >= current.outfits_unlocked);
    }
  }
});

Deno.test("fragrance and scoring failures are dropped, never invented", async () => {
  const fragrance = candidateRow("cologne", { category: "fragrance" });
  const result = await handleListUnlocks(
    USER,
    deps([fragrance], [TOP, BOTTOM]),
  );
  assertEquals(result.items, []);
});

Deno.test("empty evaluations is an empty list, not a catalog dump", async () => {
  const result = await handleListUnlocks(USER, deps([], [TOP, BOTTOM]));
  assertEquals(result.items, []);
});

Deno.test("the rail is capped at the alternatives-pool budget", async () => {
  const many = Array.from(
    { length: UNLOCKS_CANDIDATE_CAP + 5 },
    (_, index) => candidateRow(`shoe-${index}`, { color: "navy", fit: "slim" }),
  );
  let requested = 0;
  const limited: ProductsDependencies = {
    ...deps(many, [TOP, BOTTOM]),
    fetchLatestEvaluatedCandidates: (_userID, limit) => {
      requested = limit;
      return Promise.resolve(many.slice(0, limit + 5));
    },
  };
  const result = await handleListUnlocks(USER, limited);
  assertEquals(requested, UNLOCKS_CANDIDATE_CAP);
  assertEquals(result.items.length <= UNLOCKS_CANDIDATE_CAP, true);
});
