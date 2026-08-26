import { assertEquals } from "@std/assert";
import type { AuthClient } from "../_shared/jwt.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import type {
  OutfitScorer,
  OutfitScorerOptions,
  OutfitScorerRow,
} from "../_shared/scoring/outfitScorer.ts";
import {
  type BriefRow,
  handleGeneratePacking,
  type HandlerDeps,
  type OccasionRow,
  type OutfitDraft,
  type PackingRepository,
} from "./handler.ts";

const VALID_LOOKING_JWT_A =
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLWEifQ.dGhpc19pc19ub3RfYV9yZWFsX3NpZ25hdHVyZQ";
const USER_A_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

function closetRow(id: string, category: string): OutfitScorerRow {
  return {
    id,
    category,
    last_worn_at: null,
    primary_color: category === "top" ? "navy" : "stone",
    secondary_colors: [],
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

const TWO_LOOKS: OutfitScorerRow[] = [
  closetRow("top-1", "top"),
  closetRow("top-2", "top"),
  closetRow("bottom-1", "bottom"),
  closetRow("bottom-2", "bottom"),
  closetRow("shoes-1", "shoes"),
  closetRow("shoes-2", "shoes"),
];

/** Picks the first unused top/bottom/shoes. Empty when a role is exhausted. */
class RotationStubScorer implements OutfitScorer {
  generate(items: readonly OutfitScorerRow[], options: OutfitScorerOptions) {
    const available = items.filter((item) => !options.excludedItemIds.has(item.id));
    const top = available.find((item) => item.category === "top");
    const bottom = available.find((item) => item.category === "bottom");
    const shoes = available.find((item) => item.category === "shoes");
    if (!top || !bottom || !shoes) return [];
    return [{
      itemIds: [top.id, bottom.id, shoes.id],
      compatibilityScore: 0.8,
      reason: "Navy and Stone work together.",
    }];
  }
}

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

interface MemoryRepository extends PackingRepository {
  readonly briefs: Map<string, BriefRow>;
  readonly created: OutfitDraft[];
}

function memoryRepository(
  closet: OutfitScorerRow[],
  occasions: OccasionRow[] = [],
): MemoryRepository {
  const briefs = new Map<string, BriefRow>();
  const created: OutfitDraft[] = [];
  const itemsByOutfit = new Map<string, string[]>();
  let sequence = 0;

  return {
    briefs,
    created,
    listCandidateItems() {
      return Promise.resolve(closet);
    },
    readWardrobeGraph() {
      return Promise.resolve("menswear_3_role" as const);
    },
    listOccasions() {
      return Promise.resolve(occasions);
    },
    findBriefs(_userId, dates) {
      return Promise.resolve(
        dates.flatMap((day) => {
          const row = briefs.get(day);
          return row ? [row] : [];
        }),
      );
    },
    createOutfits(_userId, drafts) {
      const ids = drafts.map((draft) => {
        created.push(draft);
        const id = `outfit-${++sequence}`;
        itemsByOutfit.set(id, [...draft.itemIds]);
        return id;
      });
      return Promise.resolve(ids);
    },
    upsertBrief(input) {
      const row: BriefRow = {
        id: `brief-${input.briefDate}`,
        user_id: input.userId,
        brief_date: input.briefDate,
        primary_outfit_id: input.primaryOutfitId,
        alternative_outfit_ids: [...input.alternativeOutfitIds],
        schedule_snapshot: input.scheduleSnapshot,
      };
      briefs.set(input.briefDate, row);
      return Promise.resolve(row);
    },
    listOutfitItemIds(outfitIds) {
      const ids = outfitIds.flatMap((id) => itemsByOutfit.get(id) ?? []);
      return Promise.resolve([...new Set(ids)]);
    },
  };
}

function buildDeps(overrides: Partial<HandlerDeps> = {}): HandlerDeps {
  return {
    authClient: tokenMappedAuthClient(),
    repository: memoryRepository(TWO_LOOKS),
    scorerForDay: () => new RotationStubScorer(),
    rateLimiter: createRateLimiter({ limit: 1000, windowMs: 60_000 }),
    now: () => new Date("2026-08-24T12:00:00Z"),
    ...overrides,
  };
}

function requestFor(body: unknown): Request {
  return new Request("https://example.com/packing/generate", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${VALID_LOOKING_JWT_A}`,
    },
    body: JSON.stringify(body),
  });
}

function packingBody(overrides: Record<string, unknown> = {}) {
  return {
    request_id: "req-1",
    body: {
      destination: "",
      start_date: "2026-08-24",
      end_date: "2026-08-25",
      activities: [],
      dress_codes: [],
      luggage_constraint: "no_constraint",
      has_laundry_access: true,
      ...overrides,
    },
  };
}

async function jsonOf(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

Deno.test("rejects a missing JWT", async () => {
  const response = await handleGeneratePacking(
    new Request("https://example.com/packing/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(packingBody()),
    }),
    buildDeps(),
  );
  assertEquals(response.status, 401);
});

Deno.test("two days with two looks rotate instead of repeating the same hoodie", async () => {
  const repo = memoryRepository(TWO_LOOKS);
  const response = await handleGeneratePacking(
    requestFor(packingBody()),
    buildDeps({ repository: repo }),
  );
  assertEquals(response.status, 200);
  const payload = await jsonOf(response);
  const data = payload["data"] as Record<string, unknown>;
  const days = data["daily_outfit_plan"] as Array<Record<string, unknown>>;
  assertEquals(days.length, 2);
  assertEquals(days[0]!["is_rewear"], false);
  assertEquals(days[1]!["is_rewear"], false);
  assertEquals(repo.created[0]!.itemIds[0], "top-1");
  assertEquals(repo.created[1]!.itemIds[0], "top-2");
});

Deno.test("a third day rewears rather than inventing a look from the wash", async () => {
  const response = await handleGeneratePacking(
    requestFor(
      packingBody({ start_date: "2026-08-24", end_date: "2026-08-26", has_laundry_access: false }),
    ),
    buildDeps(),
  );
  assertEquals(response.status, 200);
  const payload = await jsonOf(response);
  const data = payload["data"] as Record<string, unknown>;
  const days = data["daily_outfit_plan"] as Array<Record<string, unknown>>;
  assertEquals(days.length, 3);
  assertEquals(days[2]!["is_rewear"], true);
  const missing = data["missing_essentials"] as string[];
  assertEquals(missing.some((line) => line.includes("No laundry")), true);
});

Deno.test("a second call the same range returns the stored plan, not a rebuild", async () => {
  const repo = memoryRepository(TWO_LOOKS);
  const deps = buildDeps({ repository: repo });
  await handleGeneratePacking(requestFor(packingBody()), deps);
  const created = repo.created.length;
  const second = await handleGeneratePacking(requestFor(packingBody()), deps);
  assertEquals(second.status, 200);
  assertEquals(repo.created.length, created);
});

Deno.test("regenerate rebuilds even when briefs exist", async () => {
  const repo = memoryRepository(TWO_LOOKS);
  const deps = buildDeps({ repository: repo });
  await handleGeneratePacking(requestFor(packingBody()), deps);
  const created = repo.created.length;
  const second = await handleGeneratePacking(
    requestFor(packingBody({ regenerate: true })),
    deps,
  );
  assertEquals(second.status, 200);
  assertEquals(repo.created.length > created, true);
});

Deno.test("an occasion titles the day's look", async () => {
  const repo = memoryRepository(TWO_LOOKS, [{
    starts_at: "2026-08-24T18:00:00.000Z",
    title: "Dinner with Sam",
    dress_code: "smart_casual",
  }]);
  const response = await handleGeneratePacking(
    requestFor(packingBody({ end_date: "2026-08-24" })),
    buildDeps({ repository: repo }),
  );
  assertEquals(response.status, 200);
  assertEquals(repo.created[0]!.name, "Dinner with Sam");
  assertEquals(repo.briefs.get("2026-08-24")?.schedule_snapshot["headline"], "Dinner with Sam");
});

Deno.test("more than 14 days is refused", async () => {
  const response = await handleGeneratePacking(
    requestFor(packingBody({ start_date: "2026-08-01", end_date: "2026-08-20" })),
    buildDeps(),
  );
  assertEquals(response.status, 400);
});
