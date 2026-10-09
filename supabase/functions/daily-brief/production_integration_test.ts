import { assert, assertEquals, assertExists, assertNotEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { CompatibilityOutfitScorer } from "../_shared/scoring/compatibilityScorer.ts";
import type {
  OutfitScorer,
  OutfitScorerOptions,
  OutfitScorerRow,
  ScoredOutfit,
} from "../_shared/scoring/outfitScorer.ts";
import type { ScoringContext } from "../_shared/scoring/types.ts";
import {
  type BriefRepository,
  handleGenerateDailyBrief,
  type HandlerDeps,
  type OutfitDraft,
  type UpsertBriefInput,
} from "./handler.ts";
import type { DailyBriefRow } from "./schema.ts";

const OWNER_ID = "a1111111-1111-4111-8111-111111111111";
const PEER_ID = "b2222222-2222-4222-8222-222222222222";
const BRIEF_DATE = "2026-10-09";
const OWNER_TOKEN =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";

interface OwnedClosetRow extends OutfitScorerRow {
  readonly ownerId: string;
  readonly archivedAt: string | null;
}
interface PersistedOutfit {
  readonly id: string;
  readonly ownerId: string;
  readonly itemIds: readonly string[];
  readonly score: number;
  readonly reason: string;
}

function closetRow(
  ownerId: string,
  id: string,
  category: string,
  color: string,
  formality: number,
  options: Partial<Pick<OwnedClosetRow, "laundry_state" | "availability_state" | "archivedAt">> =
    {},
): OwnedClosetRow {
  return {
    ownerId,
    id,
    category,
    primary_color: color,
    secondary_colors: [],
    pattern: "solid",
    material: [{ fiber: "cotton", percentage: 100 }],
    fit: "regular",
    seasonality: ["fall", "winter"],
    formality_score: formality,
    warmth_score: 75,
    water_resistance_score: 60,
    laundry_state: options.laundry_state ?? "clean",
    availability_state: options.availability_state ?? "available",
    archivedAt: options.archivedAt ?? null,
    last_worn_at: null,
  };
}

const OWNED_ROWS: OwnedClosetRow[] = [
  closetRow(OWNER_ID, "owner-top-navy", "top", "navy", 60),
  closetRow(OWNER_ID, "owner-top-white", "top", "white", 40),
  closetRow(OWNER_ID, "owner-bottom-charcoal", "bottom", "charcoal", 60),
  closetRow(OWNER_ID, "owner-bottom-khaki", "bottom", "khaki", 40),
  closetRow(OWNER_ID, "owner-shoes-black", "shoes", "black", 60),
  closetRow(OWNER_ID, "owner-shoes-brown", "shoes", "brown", 40),
  closetRow(OWNER_ID, "owner-top-laundry", "top", "red", 90, { laundry_state: "laundry" }),
  closetRow(OWNER_ID, "owner-bottom-unavailable", "bottom", "green", 90, {
    availability_state: "unavailable",
  }),
  closetRow(OWNER_ID, "owner-shoes-archived", "shoes", "purple", 90, {
    archivedAt: "2026-10-08T00:00:00Z",
  }),
  // High-scoring peer rows make owner filtering consequential.
  closetRow(PEER_ID, "peer-top-red", "top", "red", 90),
  closetRow(PEER_ID, "peer-bottom-green", "bottom", "green", 90),
  closetRow(PEER_ID, "peer-shoes-purple", "shoes", "purple", 90),
];

class ScratchOwnedRepository implements BriefRepository {
  readonly outfits = new Map<string, PersistedOutfit>();
  readonly outfitItems: Array<{ ownerId: string; outfitId: string; closetItemId: string }> = [];
  readonly briefs = new Map<string, DailyBriefRow>();
  readonly candidateReads: string[] = [];
  private sequence = 0;

  findBrief(userId: string, briefDate: string): Promise<DailyBriefRow | null> {
    return Promise.resolve(this.briefs.get(userId + ":" + briefDate) ?? null);
  }

  listCandidateItems(userId: string): Promise<OutfitScorerRow[]> {
    this.candidateReads.push(userId);
    // Mirrors the production JWT/RLS owner scope and wearable filters.
    return Promise.resolve(
      OWNED_ROWS.filter((row) =>
        row.ownerId === userId && row.archivedAt === null &&
        row.availability_state === "available" &&
        (row.laundry_state === "clean" || row.laundry_state === "worn_once")
      ),
    );
  }

  readWardrobeGraph(): Promise<"menswear_3_role"> {
    return Promise.resolve("menswear_3_role");
  }
  countOccasions(): Promise<number> {
    return Promise.resolve(2);
  }

  createOutfits(userId: string, drafts: readonly OutfitDraft[]): Promise<string[]> {
    const ownedIds = new Set(
      OWNED_ROWS.filter((row) => row.ownerId === userId).map((row) => row.id),
    );
    const outfitIds: string[] = [];
    for (const draft of drafts) {
      assert(draft.itemIds.length >= 3, "generated outfit must have a full top/bottom/shoes set");
      for (const closetItemId of draft.itemIds) {
        assert(ownedIds.has(closetItemId), "scorer selected a foreign closet item");
      }
      const id = "persisted-outfit-" + (++this.sequence);
      this.outfits.set(id, {
        id,
        ownerId: userId,
        itemIds: [...draft.itemIds],
        score: draft.compatibilityScore,
        reason: draft.reason,
      });
      for (const closetItemId of draft.itemIds) {
        this.outfitItems.push({ ownerId: userId, outfitId: id, closetItemId });
      }
      outfitIds.push(id);
    }
    return Promise.resolve(outfitIds);
  }

  upsertBrief(input: UpsertBriefInput): Promise<DailyBriefRow> {
    const key = input.userId + ":" + input.briefDate;
    const prior = this.briefs.get(key);
    const row: DailyBriefRow = {
      id: prior?.id ?? "persisted-brief-" + input.userId + "-" + input.briefDate,
      user_id: input.userId,
      brief_date: input.briefDate,
      primary_outfit_id: input.primaryOutfitId,
      alternative_outfit_ids: [...input.alternativeOutfitIds],
      weather_snapshot: input.weatherSnapshot ?? {},
      schedule_snapshot: input.scheduleSnapshot,
      kyra_message: null,
    };
    this.briefs.set(key, row);
    return Promise.resolve(row);
  }
}

class CapturingProductionScorer implements OutfitScorer {
  readonly contexts: ScoringContext[] = [];
  private readonly scorer = new CompatibilityOutfitScorer();
  generate(items: readonly OutfitScorerRow[], options: OutfitScorerOptions): ScoredOutfit[] {
    this.contexts.push(options.context ?? {});
    return this.scorer.generate(items, options);
  }
}

const authClient: AuthClient = {
  auth: {
    getUser(token?: string) {
      return Promise.resolve(
        token === OWNER_TOKEN
          ? { data: { user: { id: OWNER_ID } }, error: null }
          : { data: { user: null }, error: { message: "invalid test token" } },
      );
    },
  },
};

function request(regenerate = false): Request {
  return new Request("https://test.invalid/functions/v1/daily-brief/generate", {
    method: "POST",
    headers: {
      authorization: "Bearer " + OWNER_TOKEN,
      "content-type": "application/json",
      "x-request-id": crypto.randomUUID(),
    },
    body: JSON.stringify({
      request_id: crypto.randomUUID(),
      client_version: "P4-TEST-03-production-path",
      body: {
        date: BRIEF_DATE,
        regenerate,
        weather_snapshot: {
          temperature_high: 40,
          temperature_low: 35,
          apparent_temperature: 32,
          condition: "rain",
          precipitation_chance: 0.8,
          season: "winter",
        },
        schedule_snapshot: { event_count: 2, earliest_formality_level: "formal" },
      },
    }),
  });
}

function dependencies(
  repository: ScratchOwnedRepository,
  scorer: CapturingProductionScorer,
): HandlerDeps {
  return {
    authClient,
    repository,
    scorer,
    rateLimiter: createRateLimiter({ limit: 10, windowMs: 60_000 }),
    now: () => new Date("2026-10-09T12:00:00Z"),
    hasActivePremiumSubscription: () => Promise.resolve(true),
    countBriefs: () => Promise.resolve(0),
  };
}

interface Envelope<T> {
  readonly data: T | null;
  readonly error: { readonly message: string } | null;
}

async function briefResponse(response: Response): Promise<DailyBriefRow> {
  if (response.status !== 200) {
    throw new Error("Daily Brief returned HTTP " + response.status + ": " + await response.text());
  }
  const envelope = await response.json() as Envelope<DailyBriefRow>;
  assertEquals(envelope.error, null);
  assertExists(envelope.data);
  return envelope.data;
}

Deno.test("production Daily Brief handler and scorer persist weather-ranked owned looks idempotently", async () => {
  const repository = new ScratchOwnedRepository();
  const scorer = new CapturingProductionScorer();
  const deps = dependencies(repository, scorer);

  const first = await briefResponse(await handleGenerateDailyBrief(request(), deps));
  assertEquals(first.user_id, OWNER_ID);
  assertExists(first.primary_outfit_id);
  assert(Array.isArray(first.alternative_outfit_ids));
  assert(first.alternative_outfit_ids.length >= 1, "populated closet must yield an alternative");
  const weather = first.weather_snapshot as Record<string, unknown>;
  const schedule = first.schedule_snapshot as Record<string, unknown>;
  assertEquals(weather["apparent_temperature"], 32);
  assertEquals(weather["season"], "winter");
  assertEquals(schedule["event_count"], 2);
  assertEquals(scorer.contexts.length, 1);
  assertEquals(scorer.contexts[0]?.weather?.temperatureC, 0);
  assertEquals(scorer.contexts[0]?.weather?.precipitationProbability, 0.8);
  assertEquals(scorer.contexts[0]?.weather?.season, "winter");
  assertEquals(scorer.contexts[0]?.targetFormalityScore, 70);

  const referencedOutfitIds = [first.primary_outfit_id, ...first.alternative_outfit_ids];
  const ownerClosetIds = new Set(
    OWNED_ROWS.filter((row) => row.ownerId === OWNER_ID).map((row) => row.id),
  );
  for (const outfitId of referencedOutfitIds) {
    const outfit = repository.outfits.get(outfitId);
    assertExists(outfit, "brief must reference an outfit persisted before the brief row");
    assertEquals(outfit.ownerId, OWNER_ID);
    assert(outfit.itemIds.every((itemId) => ownerClosetIds.has(itemId)));
  }
  const referencedItems = repository.outfitItems.filter((row) =>
    referencedOutfitIds.includes(row.outfitId)
  );
  assert(referencedItems.length >= 9);
  assert(
    referencedItems.every((row) =>
      row.ownerId === OWNER_ID && ownerClosetIds.has(row.closetItemId)
    ),
  );
  assert(!referencedItems.some((row) => row.closetItemId.startsWith("peer-")));
  assert(!referencedItems.some((row) => row.closetItemId.includes("laundry")));
  assert(!referencedItems.some((row) => row.closetItemId.includes("unavailable")));
  assert(!referencedItems.some((row) => row.closetItemId.includes("archived")));
  assert(repository.candidateReads.every((ownerId) => ownerId === OWNER_ID));

  const writesAfterFirst = repository.outfits.size;
  const repeated = await briefResponse(await handleGenerateDailyBrief(request(), deps));
  assertEquals(repeated.id, first.id);
  assertEquals(
    repository.outfits.size,
    writesAfterFirst,
    "same-day retry should not create outfits",
  );
  assertEquals(scorer.contexts.length, 1, "same measured context should return stored brief");

  const regenerated = await briefResponse(await handleGenerateDailyBrief(request(true), deps));
  assertEquals(regenerated.id, first.id, "regeneration updates the same daily brief row");
  assertNotEquals(regenerated.primary_outfit_id, first.primary_outfit_id);
  assert(repository.outfits.size > writesAfterFirst);
});
