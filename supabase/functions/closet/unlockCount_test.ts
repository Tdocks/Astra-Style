import { assert, assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "@supabase/supabase-js";
import { DEFAULT_WEIGHTS } from "../_shared/scoring/compatibility.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { handleScanUnlockCount } from "./unlockCount.ts";

const OWNER = "11111111-1111-4111-8111-111111111111";
const PEER = "22222222-2222-4222-8222-222222222222";
const TARGET = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const BOTTOM = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const SHOES = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

function closetRow(id: string, category: string, owner = OWNER) {
  return {
    id,
    user_id: owner,
    category,
    primary_color: "navy",
    secondary_colors: [],
    pattern: "solid",
    material: ["cotton"],
    fit: "regular",
    seasonality: ["winter"],
    formality_score: 50,
    warmth_score: 50,
    water_resistance_score: 20,
    laundry_state: "laundry",
    availability_state: "unavailable",
    last_worn_at: "2025-01-01T00:00:00Z",
    archived_at: null,
  };
}

function fixture(options: {
  rows?: ReturnType<typeof closetRow>[];
  authenticated?: boolean;
  queryError?: boolean;
} = {}) {
  const calls: { table: string; filters: [string, unknown][]; range?: [number, number] }[] = [];
  const rows = options.rows ?? [
    closetRow(TARGET, "top"),
    closetRow(BOTTOM, "bottom"),
    closetRow(SHOES, "shoes"),
  ];
  const client = {
    from(table: string) {
      const call: { table: string; filters: [string, unknown][]; range?: [number, number] } = {
        table,
        filters: [],
      };
      calls.push(call);
      const query = {
        select(_columns: string) {
          return query;
        },
        eq(key: string, value: unknown) {
          call.filters.push([key, value]);
          return query;
        },
        is(key: string, value: unknown) {
          call.filters.push([key, value]);
          return query;
        },
        order(_key: string, _options?: unknown) {
          return query;
        },
        range(start: number, end: number) {
          call.range = [start, end];
          const data = table === "closet_items" && start === 0 ? rows : [];
          return Promise.resolve({
            data,
            error: options.queryError ? { message: "private" } : null,
          });
        },
        maybeSingle() {
          return Promise.resolve({ data: { wardrobe_graph: "menswear_3_role" }, error: null });
        },
      };
      return query;
    },
  };
  const deps = {
    supabase: client as unknown as SupabaseClient,
    authClient: {
      auth: {
        getUser() {
          return Promise.resolve({
            data: { user: options.authenticated === false ? null : { id: OWNER } },
            error: null,
          });
        },
      },
    },
    rateLimiter: createRateLimiter({ limit: 100, windowMs: 60_000 }),
    now: () => new Date("2026-10-09T12:00:00.000Z"),
    readWeights: () => Promise.resolve(DEFAULT_WEIGHTS),
    readOwnedScoringContext: () => Promise.resolve({}),
  };
  return { calls, deps };
}

function request() {
  return new Request(`https://example.invalid/closet/items/${TARGET}/unlock-count`, {
    method: "GET",
    headers: { Authorization: "Bearer test.payload.signature" },
  });
}

Deno.test("scan unlock count uses the shared scorer and excludes the saved item from its own closet pool", async () => {
  const f = fixture();
  const response = await handleScanUnlockCount(request(), TARGET, f.deps);
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  const body = (await response.json()).data;
  assertEquals(body.status, "available");
  assert(typeof body.outfits_unlocked === "number");
  assert(
    body.outfits_unlocked > 0,
    "The candidate's own saved row must not suppress all results as its own substitute.",
  );
  const itemsCall = f.calls.find((call) => call.table === "closet_items");
  assert(itemsCall?.filters.some(([key, value]) => key === "user_id" && value === OWNER));
  assert(itemsCall?.filters.some(([key, value]) => key === "archived_at" && value === null));
  assert(
    f.calls.some((call) =>
      call.table === "profiles" &&
      call.filters.some(([key, value]) => key === "id" && value === OWNER)
    ),
  );
  assert(!("user_id" in body), "The endpoint should not return owner or closet data.");
});

Deno.test("scan unlock count reports unsupported categories as unmeasurable, not zero", async () => {
  const f = fixture({ rows: [closetRow(TARGET, "fragrance")] });
  const response = await handleScanUnlockCount(request(), TARGET, f.deps);
  assertEquals(response.status, 200);
  assertEquals((await response.json()).data, { status: "unmeasurable", outfits_unlocked: null });
});

Deno.test("missing or peer-owned saved item is unavailable", async () => {
  const missing = fixture({ rows: [closetRow(BOTTOM, "bottom")] });
  assertEquals((await handleScanUnlockCount(request(), TARGET, missing.deps)).status, 404);
  const peer = fixture({ rows: [closetRow(TARGET, "top", PEER)] });
  assertEquals((await handleScanUnlockCount(request(), TARGET, peer.deps)).status, 404);
});

Deno.test("rate-limited scan unlock count returns the exact Retry-After reset", async () => {
  const f = fixture();
  f.deps.rateLimiter = { check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 23 }) };
  const response = await handleScanUnlockCount(request(), TARGET, f.deps);
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "23");
});

Deno.test("unauthenticated callers never read the closet", async () => {
  const f = fixture({ authenticated: false });
  assertEquals((await handleScanUnlockCount(request(), TARGET, f.deps)).status, 401);
  assertEquals(f.calls.length, 0);
});

Deno.test("query failures do not become a fabricated zero", async () => {
  const f = fixture({ queryError: true });
  const response = await handleScanUnlockCount(request(), TARGET, f.deps);
  assertEquals(response.status, 500);
  assert(!(await response.text()).includes("private"));
});
