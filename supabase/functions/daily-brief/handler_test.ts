// ============================================================================
// daily-brief/handler_test.ts
// ============================================================================
// P4-HOME-02's two acceptance criteria, plus the auth/schema floor every
// §14 endpoint shares:
//   - a populated closet yields a primary outfit AND at least one alternative
//   - a second call the same day returns the SAME brief, unless regenerate
//   - outfits are persisted before the brief references them (the FK)
//   - an empty closet yields a real brief with a null primary, not an error
//   - `{}` snapshots go out as null, because the client cannot decode `{}`
//
// Every dependency is injected; no network, no live database, no real JWT.
// ============================================================================

import { assertEquals, assertNotEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { CompatibilityOutfitScorer } from "../_shared/scoring/compatibilityScorer.ts";
import { LeastRecentlyWornScorer } from "../_shared/scoring/leastRecentlyWorn.ts";
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

const VALID_LOOKING_JWT_A =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";
const USER_A_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const BRIEF_DATE = "2026-08-06";

/**
 * A closet row carrying only the columns these tests care about.
 *
 * `OutfitScorerRow` widened to the real closet table when the compatibility
 * engine replaced the least-recently-worn placeholder (`outfitScorer.ts`).
 * These tests are about the HANDLER — write ordering, ownership, empty
 * closets — and drive it through a stub scorer, so the eleven scoring columns
 * are noise here. Padded once, in one place.
 */
function closetRow(id: string, category: string, lastWornAt: string | null): OutfitScorerRow {
  return {
    id,
    category,
    last_worn_at: lastWornAt,
    primary_color: null,
    secondary_colors: null,
    pattern: null,
    material: null,
    fit: null,
    seasonality: null,
    formality_score: null,
    warmth_score: null,
    water_resistance_score: null,
    laundry_state: "clean",
    availability_state: "available",
  };
}

/** Enough for the scorer to build more than one distinct outfit. */
const POPULATED_CLOSET: OutfitScorerRow[] = [
  closetRow("top-1", "top", null),
  closetRow("top-2", "top", "2026-01-01T00:00:00Z"),
  closetRow("bottom-1", "bottom", null),
  closetRow("bottom-2", "bottom", "2026-01-01T00:00:00Z"),
  closetRow("shoes-1", "shoes", null),
  closetRow("shoes-2", "shoes", "2026-01-01T00:00:00Z"),
];

function tokenMappedAuthClient(): AuthClient {
  return {
    auth: {
      getUser(jwt?: string) {
        if (jwt === VALID_LOOKING_JWT_A) {
          return Promise.resolve({ data: { user: { id: USER_A_ID } }, error: null });
        }
        return Promise.resolve({ data: { user: null }, error: { message: "invalid token" } });
      },
    },
  };
}

interface MemoryRepository extends BriefRepository {
  readonly briefs: Map<string, DailyBriefRow>;
  readonly createdOutfits: OutfitDraft[][];
  /** Order of persistence, so a test can prove outfits precede the brief. */
  readonly writeLog: string[];
}

function memoryRepository(closet: OutfitScorerRow[], occasions = 0): MemoryRepository {
  const briefs = new Map<string, DailyBriefRow>();
  const createdOutfits: OutfitDraft[][] = [];
  const writeLog: string[] = [];
  let outfitSequence = 0;

  return {
    briefs,
    createdOutfits,
    writeLog,
    findBrief(_userId: string, briefDate: string) {
      return Promise.resolve(briefs.get(briefDate) ?? null);
    },
    listCandidateItems() {
      return Promise.resolve(closet);
    },
    readWardrobeGraph() {
      return Promise.resolve("menswear_3_role" as const);
    },
    countOccasions() {
      return Promise.resolve(occasions);
    },
    createOutfits(_userId: string, drafts: readonly OutfitDraft[]) {
      writeLog.push("outfits");
      createdOutfits.push([...drafts]);
      return Promise.resolve(drafts.map(() => `outfit-${++outfitSequence}`));
    },
    upsertBrief(input: UpsertBriefInput) {
      writeLog.push("brief");
      const row: DailyBriefRow = {
        id: `brief-${input.briefDate}`,
        user_id: input.userId,
        brief_date: input.briefDate,
        primary_outfit_id: input.primaryOutfitId,
        alternative_outfit_ids: [...input.alternativeOutfitIds],
        // Mirrors the live `upsertBrief`'s own `?? {}` (P4-HOME-05): the
        // column default when nothing was measured, not a fabricated one.
        weather_snapshot: input.weatherSnapshot ?? {},
        schedule_snapshot: input.scheduleSnapshot,
        kyra_message: null,
      };
      briefs.set(input.briefDate, row);
      return Promise.resolve(row);
    },
  };
}

function buildDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  return {
    authClient: tokenMappedAuthClient(),
    repository: memoryRepository(POPULATED_CLOSET),
    scorer: new LeastRecentlyWornScorer(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-08-06T12:00:00Z"),
    ...overrides,
  };
}

class RecordingContextScorer implements OutfitScorer {
  readonly contexts: Array<ScoringContext | undefined> = [];
  private readonly fallback = new LeastRecentlyWornScorer();

  generate(
    items: readonly OutfitScorerRow[],
    options: OutfitScorerOptions,
  ): ScoredOutfit[] {
    this.contexts.push(options.context);
    return this.fallback.generate(items, options);
  }
}

function requestFor(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://example.com/daily-brief/generate", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function generateBody(overrides: Record<string, unknown> = {}) {
  return {
    request_id: "test-request-id",
    client_version: "ios/1.0.0",
    body: { date: BRIEF_DATE, ...overrides },
  };
}

Deno.test("rejects a request with no Authorization header", async () => {
  const req = new Request("https://example.com/daily-brief/generate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(generateBody()),
  });
  const response = await handleGenerateDailyBrief(req, buildDeps());
  assertEquals(response.status, 401);
});

Deno.test("rejects a malformed JWT", async () => {
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody(), { Authorization: "Bearer not-a-jwt" }),
    buildDeps(),
  );
  assertEquals(response.status, 401);
});

Deno.test("rejects a date that is not a calendar day", async () => {
  for (const bad of ["2026-8-6", "2026-02-31", "today", "2026-08-06T00:00:00Z"]) {
    const response = await handleGenerateDailyBrief(
      requestFor(generateBody({ date: bad })),
      buildDeps(),
    );
    assertEquals(response.status, 400, `expected 400 for ${bad}`);
  }
});

// P4-HOME-02, criterion 1.
Deno.test("a populated closet yields a primary outfit and at least one alternative", async () => {
  const response = await handleGenerateDailyBrief(requestFor(generateBody()), buildDeps());
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.error, null);
  assertNotEquals(json.data.primary_outfit_id, null);
  assertEquals(json.data.alternative_outfit_ids.length >= 1, true);
});

// P4-HOME-02, criterion 2.
Deno.test("a second call the same day returns the same brief", async () => {
  const repository = memoryRepository(POPULATED_CLOSET);
  const deps = buildDeps({ repository });

  const first = await (await handleGenerateDailyBrief(requestFor(generateBody()), deps)).json();
  const second = await (await handleGenerateDailyBrief(requestFor(generateBody()), deps)).json();

  assertEquals(second.data.id, first.data.id);
  assertEquals(second.data.primary_outfit_id, first.data.primary_outfit_id);
  // The expensive half did not run again — no second set of outfits was
  // written. Asserting on the id alone would pass even if the handler had
  // rebuilt everything and happened to store it under the same key.
  assertEquals(repository.createdOutfits.length, 1);
});

Deno.test("regenerate rebuilds the day's brief", async () => {
  const repository = memoryRepository(POPULATED_CLOSET);
  const deps = buildDeps({ repository });

  await handleGenerateDailyBrief(requestFor(generateBody()), deps);
  const again = await handleGenerateDailyBrief(
    requestFor(generateBody({ regenerate: true })),
    deps,
  );

  assertEquals(again.status, 200);
  assertEquals(repository.createdOutfits.length, 2);
});

/// `daily_briefs.primary_outfit_id` is a foreign key into `outfits`, so a
/// brief written before its outfits exist is rejected by the database. The
/// order is the requirement, not an implementation detail.
Deno.test("outfits are persisted before the brief that references them", async () => {
  const repository = memoryRepository(POPULATED_CLOSET);
  await handleGenerateDailyBrief(requestFor(generateBody()), buildDeps({ repository }));
  assertEquals(repository.writeLog, ["outfits", "brief"]);
});

/// Every persisted `outfit_items` row needs a real `role`, and the scorer
/// returns bare item ids — so the handler has to carry each item's category
/// across. Defaulting a missing one to "top" would file a pair of shoes as
/// a top in the outfit builder.
Deno.test("each outfit draft carries the category of every item it contains", async () => {
  const repository = memoryRepository(POPULATED_CLOSET);
  await handleGenerateDailyBrief(requestFor(generateBody()), buildDeps({ repository }));

  const drafts = repository.createdOutfits[0] ?? [];
  assertEquals(drafts.length > 0, true);
  for (const draft of drafts) {
    for (const itemId of draft.itemIds) {
      const expected = POPULATED_CLOSET.find((item) => item.id === itemId)?.category;
      assertEquals(draft.rolesByItemId.get(itemId), expected);
    }
  }
});

/// An empty closet is not an error. `DailyBrief.hasPrimaryOutfit` is what
/// drives §6.11's "add five pieces" state, so "nothing to wear yet" has to
/// arrive as a brief the client can hold.
Deno.test("an empty closet yields a brief with a null primary outfit, not an error", async () => {
  const repository = memoryRepository([]);
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody()),
    buildDeps({ repository }),
  );

  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.data.primary_outfit_id, null);
  assertEquals(json.data.alternative_outfit_ids, []);
  // And nothing was written to `outfits` for a closet that cannot dress him.
  assertEquals(repository.createdOutfits.length, 0);
});

/// The column is `jsonb NOT NULL DEFAULT '{}'`, but the client decodes it
/// into `WeatherSnapshot?`, whose fields cannot be built from `{}` — a
/// present-but-empty object makes the whole `DailyBrief` decode THROW on
/// the device rather than degrade to nil. Mapping it to null is what stops
/// that, and there is no weather provider to fill it with (P4-HOME-05).
Deno.test("an empty weather snapshot goes out as null, not as {}", async () => {
  const response = await handleGenerateDailyBrief(requestFor(generateBody()), buildDeps());
  const json = await response.json();
  assertEquals(json.data.weather_snapshot, null);
});

/// The mirror image: a snapshot with real content must survive untouched.
Deno.test("a populated schedule snapshot is preserved", async () => {
  const repository = memoryRepository(POPULATED_CLOSET, 3);
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody()),
    buildDeps({ repository }),
  );
  const json = await response.json();
  assertEquals(json.data.schedule_snapshot, { event_count: 3 });
});

// P4-HOME-05: the client's own `WeatherService` reading is the only source
// `weather_snapshot` can have, since there is still no server-side
// provider. These pin that it actually reaches the stored row, that its
// absence stays honestly null rather than becoming an error, and that a
// malformed one is rejected rather than silently stored or dropped.

const VALID_WEATHER_SNAPSHOT = {
  temperature_high: 68,
  temperature_low: 54,
  condition: "partly_cloudy",
};

Deno.test("a client-supplied weather snapshot is persisted onto the brief", async () => {
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody({ weather_snapshot: VALID_WEATHER_SNAPSHOT })),
    buildDeps(),
  );
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.data.weather_snapshot, VALID_WEATHER_SNAPSHOT);
});

Deno.test("the device forecast reaches scoring in Celsius, not display Fahrenheit", async () => {
  const scorer = new RecordingContextScorer();
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody({
      weather_snapshot: {
        temperature_high: 95,
        temperature_low: 72,
        apparent_temperature: 86,
        precipitation_chance: 0.7,
        condition: "rain",
      },
    })),
    buildDeps({ scorer }),
  );

  assertEquals(response.status, 200);
  assertEquals(scorer.contexts.length, 1);
  assertEquals(scorer.contexts[0]?.weather, {
    temperatureC: 30,
    precipitationProbability: 0.7,
  });
});

Deno.test("no forecast gives the scorer no weather claim", async () => {
  const scorer = new RecordingContextScorer();
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody()),
    buildDeps({ scorer }),
  );

  assertEquals(response.status, 200);
  assertEquals(scorer.contexts[0]?.weather, undefined);
});

Deno.test("the caller's wardrobe graph reaches the scorer", async () => {
  const scorer = new RecordingContextScorer();
  const repository = memoryRepository(POPULATED_CLOSET);
  repository.readWardrobeGraph = () => Promise.resolve("womenswear");
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody()),
    buildDeps({ scorer, repository }),
  );
  assertEquals(response.status, 200);
  assertEquals(scorer.contexts[0]?.wardrobeGraph, "womenswear");
});

Deno.test("adding weather refreshes an existing no-weather brief exactly once", async () => {
  const repository = memoryRepository(POPULATED_CLOSET);
  const first = await handleGenerateDailyBrief(
    requestFor(generateBody()),
    buildDeps({ repository }),
  );
  assertEquals(first.status, 200);
  assertEquals(repository.createdOutfits.length, 1);

  // Context backfill is not a fourth free Daily Brief. It updates the same
  // day's row so the header and ranking cannot contradict each other.
  const withWeather = await handleGenerateDailyBrief(
    requestFor(generateBody({ weather_snapshot: VALID_WEATHER_SNAPSHOT })),
    buildDeps({
      repository,
      hasActivePremiumSubscription: () => Promise.resolve(false),
      countBriefs: () => Promise.resolve(3),
    }),
  );
  assertEquals(withWeather.status, 200);
  assertEquals(repository.createdOutfits.length, 2);
  const refreshed = await withWeather.json();
  assertEquals(refreshed.data.weather_snapshot, VALID_WEATHER_SNAPSHOT);

  const repeated = await handleGenerateDailyBrief(
    requestFor(generateBody({ weather_snapshot: VALID_WEATHER_SNAPSHOT })),
    buildDeps({ repository }),
  );
  assertEquals(repeated.status, 200);
  assertEquals(repository.createdOutfits.length, 2);
});

Deno.test("hot and cold forecasts choose different warmth from the same closet", async () => {
  const climateCloset: OutfitScorerRow[] = [
    { ...closetRow("light-top", "top", null), warmth_score: 0 },
    { ...closetRow("warm-top", "top", null), warmth_score: 100 },
    { ...closetRow("bottom", "bottom", null), warmth_score: 50 },
    { ...closetRow("shoes", "shoes", null), warmth_score: 50 },
  ];

  async function primaryItems(apparentTemperatureF: number): Promise<readonly string[]> {
    const repository = memoryRepository(climateCloset);
    const response = await handleGenerateDailyBrief(
      requestFor(generateBody({
        weather_snapshot: {
          temperature_high: apparentTemperatureF,
          temperature_low: apparentTemperatureF,
          apparent_temperature: apparentTemperatureF,
          precipitation_chance: 0,
          condition: "clear",
        },
      })),
      buildDeps({ repository, scorer: new CompatibilityOutfitScorer() }),
    );
    assertEquals(response.status, 200);
    return repository.createdOutfits[0]?.[0]?.itemIds ?? [];
  }

  const hotPrimary = await primaryItems(95);
  const coldPrimary = await primaryItems(20);
  assertEquals(hotPrimary.includes("light-top"), true);
  assertEquals(hotPrimary.includes("warm-top"), false);
  assertEquals(coldPrimary.includes("warm-top"), true);
  assertEquals(coldPrimary.includes("light-top"), false);
});

Deno.test("no weather_snapshot in the request stays honestly null, not an error", async () => {
  const response = await handleGenerateDailyBrief(requestFor(generateBody()), buildDeps());
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.error, null);
  assertEquals(json.data.weather_snapshot, null);
});

Deno.test("a weather_snapshot missing required fields is rejected, not stored", async () => {
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody({ weather_snapshot: { condition: "clear" } })),
    buildDeps(),
  );
  assertEquals(response.status, 400);
});

Deno.test("a weather_snapshot with an unknown condition is rejected", async () => {
  const response = await handleGenerateDailyBrief(
    requestFor(generateBody({
      weather_snapshot: { temperature_high: 70, temperature_low: 55, condition: "tornado" },
    })),
    buildDeps(),
  );
  assertEquals(response.status, 400);
});

Deno.test("a fourth free generate is 429; returning today's existing brief is not", async () => {
  const gated = buildDeps({
    hasActivePremiumSubscription: () => Promise.resolve(false),
    countBriefs: () => Promise.resolve(3),
  });
  const blocked = await handleGenerateDailyBrief(requestFor(generateBody()), gated);
  assertEquals(blocked.status, 429);

  const existing = memoryRepository(POPULATED_CLOSET);
  await handleGenerateDailyBrief(
    requestFor(generateBody()),
    buildDeps({ repository: existing }),
  );
  const again = await handleGenerateDailyBrief(
    requestFor(generateBody()),
    buildDeps({
      repository: existing,
      hasActivePremiumSubscription: () => Promise.resolve(false),
      countBriefs: () => Promise.resolve(3),
    }),
  );
  assertEquals(again.status, 200);
});
