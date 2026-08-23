import { assertEquals } from "@std/assert";
import { rankByUnlockCount, rankProductCandidates } from "./ranking.ts";

// ─── The P6-SHOP-09 guardrail test ───────────────────────────────────────
// "A non-affiliate identical/higher-scoring alternative is still surfaced
// above a sponsored one" (docs/02-task-breakdown.md P6-SHOP-04's own
// acceptance criterion, and P6-SHOP-09's "write a test that proves a
// non-affiliate alternative scoring higher is still returned above a
// sponsored one").
Deno.test("rankProductCandidates: a higher-scoring organic candidate outranks a lower-scoring sponsored one", () => {
  const ranked = rankProductCandidates([
    { id: "sponsored-a", organicScore: 70, sponsored: true },
    { id: "organic-b", organicScore: 75, sponsored: false },
  ]);
  assertEquals(ranked[0]!.id, "organic-b");
  assertEquals(ranked[0]!.sponsored, false);
  assertEquals(ranked[0]!.rank, 1);
  assertEquals(ranked[1]!.id, "sponsored-a");
  assertEquals(ranked[1]!.sponsored, true);
  assertEquals(ranked[1]!.rank, 2);
});

Deno.test("rankProductCandidates: an EQUAL-scoring sponsored candidate does not jump ahead of an organic one submitted first", () => {
  // Same organicScore — if sponsorship were ever used as a tiebreaker (in
  // either direction) this would be the test that catches it: input order
  // is preserved for a true tie, sponsored or not.
  const ranked = rankProductCandidates([
    { id: "organic-first", organicScore: 80, sponsored: false },
    { id: "sponsored-second", organicScore: 80, sponsored: true },
  ]);
  assertEquals(ranked.map((r) => r.id), ["organic-first", "sponsored-second"]);
});

Deno.test("rankProductCandidates: a lower-scoring sponsored candidate never outranks any higher-scoring organic candidate across a mixed list", () => {
  const ranked = rankProductCandidates([
    { id: "sponsored-high-ish", organicScore: 60, sponsored: true },
    { id: "organic-best", organicScore: 90, sponsored: false },
    { id: "organic-mid", organicScore: 65, sponsored: false },
    { id: "sponsored-low", organicScore: 40, sponsored: true },
  ]);
  const bestOrganicScore = Math.max(
    ...ranked.filter((r) => !r.sponsored).map((r) => r.organicScore),
  );
  for (const entry of ranked) {
    if (entry.sponsored && entry.organicScore < bestOrganicScore) {
      const betterOrganicRank = ranked.find((r) =>
        !r.sponsored && r.organicScore > entry.organicScore
      )!.rank;
      assertEquals(betterOrganicRank < entry.rank, true);
    }
  }
  assertEquals(ranked[0]!.id, "organic-best");
});

Deno.test("rankProductCandidates: every entry carries its sponsored label through unchanged", () => {
  const ranked = rankProductCandidates([
    { id: "a", organicScore: 10, sponsored: true },
    { id: "b", organicScore: 20, sponsored: false },
  ]);
  const byId = new Map(ranked.map((r) => [r.id, r.sponsored]));
  assertEquals(byId.get("a"), true);
  assertEquals(byId.get("b"), false);
});

Deno.test("rankProductCandidates: empty input returns empty output", () => {
  assertEquals(rankProductCandidates([]), []);
});

Deno.test("rankByUnlockCount: higher unlock count ranks first; zeros are omitted", () => {
  const ranked = rankByUnlockCount([
    { id: "zero", unlockCount: 0, sponsored: false },
    { id: "few", unlockCount: 2, sponsored: false },
    { id: "many", unlockCount: 8, sponsored: true },
  ]);
  assertEquals(ranked.map((item) => item.id), ["many", "few"]);
});

Deno.test("rankByUnlockCount: sponsored cannot jump a tie or a lower count", () => {
  const ranked = rankByUnlockCount([
    { id: "organic-8", unlockCount: 8, sponsored: false },
    { id: "sponsored-8", unlockCount: 8, sponsored: true },
    { id: "sponsored-3", unlockCount: 3, sponsored: true },
  ]);
  assertEquals(ranked.map((item) => item.id), ["organic-8", "sponsored-8", "sponsored-3"]);
});
