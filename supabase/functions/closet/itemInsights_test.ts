import { assert, assertEquals } from "jsr:@std/assert@1";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { handleItemInsights } from "./itemInsights.ts";
const owner = "11111111-1111-4111-8111-111111111111";
const target = "22222222-2222-4222-8222-222222222222";
const outfit = "33333333-3333-4333-8333-333333333333";
const row = {
  id: target,
  category: "top",
  primary_color: "navy",
  secondary_colors: [],
  pattern: "solid",
  material: ["cotton"],
  fit: "regular",
  seasonality: ["summer"],
  formality_score: 45,
  warmth_score: 30,
  water_resistance_score: 0,
  laundry_state: "clean",
  availability_state: "available",
  condition: "good",
  archived_at: null,
};
function fixture(
  options: {
    authenticated?: boolean;
    missing?: boolean;
    error?: boolean;
    large?: boolean;
    includeSaved?: boolean;
  } = {},
) {
  const calls: {
    table: string;
    filters: [string, string][];
    range?: [number, number];
  }[] = [];
  const client = {
    from(table: string) {
      const call: {
        table: string;
        filters: [string, string][];
        range?: [number, number];
      } = {
        table,
        filters: [],
      };
      calls.push(call);
      const query = {
        select(_columns: string) {
          return query;
        },
        eq(key: string, value: string) {
          call.filters.push([key, value]);
          return query;
        },
        order(_key: string) {
          return query;
        },
        range(start: number, end: number) {
          call.range = [start, end];
          let data: unknown[] = [];
          if (table === "closet_items" && !options.missing) {
            data = options.large && start === 0
              ? Array.from(
                { length: 500 },
                (_, i) => ({ ...row, id: i === 0 ? target : String(i) }),
              )
              : start === 0
              ? [row]
              : [];
          } else if (
            table === "outfits" && options.includeSaved && start === 0
          ) {
            data = [{ id: outfit, archived_at: null }];
          } else if (
            table === "outfit_items" && options.includeSaved && start === 0
          ) {
            data = [{
              id: "44444444-4444-4444-8444-444444444444",
              outfit_id: outfit,
              closet_item_id: target,
            }];
          }
          return Promise.resolve({
            data,
            error: options.error ? { message: "private database detail" } : null,
          });
        },
        maybeSingle() {
          return Promise.resolve({
            data: { wardrobe_graph: "menswear_3_role" },
            error: null,
          });
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
            data: {
              user: options.authenticated === false ? null : { id: owner },
            },
            error: null,
          });
        },
      },
    },
    rateLimiter: createRateLimiter({ limit: 100, windowMs: 60000 }),
  };
  return { calls, deps };
}
const request = () =>
  new Request(
    "https://example.invalid/closet/items/" + target + "/insights?user_id=peer",
    {
      headers: { Authorization: "Bearer test.payload.signature" },
    },
  );
Deno.test("item insights scopes all reads to verified caller and returns no-store", async () => {
  const f = fixture();
  const response = await handleItemInsights(request(), f.deps, target);
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  const body = (await response.json()).data;
  assertEquals(body.redundancyScore, 0);
  assertEquals(body.savedOutfitIds, []);
  for (const call of f.calls) {
    assert(
      call.filters.some(([key, value]) =>
        key === (call.table === "profiles" ? "id" : "user_id") &&
        value === owner
      ),
    );
  }
});
Deno.test("unauthenticated callers never read tables", async () => {
  const f = fixture({ authenticated: false });
  assertEquals(
    (await handleItemInsights(request(), f.deps, target)).status,
    401,
  );
  assertEquals(f.calls.length, 0);
});
Deno.test("missing or peer-owned item produces unavailable rather than fabricated score", async () => {
  const f = fixture({ missing: true });
  assertEquals(
    (await handleItemInsights(request(), f.deps, target)).status,
    404,
  );
});
Deno.test("query failures use bounded user-facing errors", async () => {
  const f = fixture({ error: true });
  const response = await handleItemInsights(request(), f.deps, target);
  assertEquals(response.status, 500);
  assert(!(await response.text()).includes("private database detail"));
});
Deno.test("full pages fetch next page instead of silently truncating", async () => {
  const f = fixture({ large: true });
  assertEquals(
    (await handleItemInsights(request(), f.deps, target)).status,
    200,
  );
  assertEquals(
    f.calls.filter((c) => c.table === "closet_items").map((c) => c.range),
    [[0, 499], [
      500,
      999,
    ]],
  );
});

Deno.test("saved outfit support count is derived from caller-owned outfit_items", async () => {
  const f = fixture({ includeSaved: true });
  const response = await handleItemInsights(request(), f.deps, target);
  const body = (await response.json()).data;

  assertEquals(response.status, 200);
  assertEquals(body.savedOutfitIds, [outfit]);
  for (
    const call of f.calls.filter((entry) =>
      entry.table === "outfits" || entry.table === "outfit_items"
    )
  ) {
    assert(
      call.filters.some(([key, value]) => key === "user_id" && value === owner),
    );
  }
});

Deno.test("rate-limited insights return the exact Retry-After reset", async () => {
  const f = fixture();
  f.deps.rateLimiter = {
    check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 23 }),
  };
  const response = await handleItemInsights(request(), f.deps, target);
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "23");
});
