import { assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { AuthClient } from "../_shared/jwt.ts";
import { handleWardrobeScore } from "./wardrobeScore.ts";

Deno.test("wardrobe score returns exact Retry-After from its limiter", async () => {
  const authClient: AuthClient = {
    auth: { getUser: () => Promise.resolve({ data: { user: { id: "user-a" } }, error: null }) },
  };
  const response = await handleWardrobeScore(
    new Request("https://example.test/closet/wardrobe-score", {
      method: "GET",
      headers: { Authorization: "Bearer test.payload.signature" },
    }),
    {
      authClient,
      supabase: {} as SupabaseClient,
      rateLimiter: {
        check: () => ({ allowed: false, remaining: 0, retryAfterSeconds: 23 }),
      },
      now: () => new Date("2026-10-09T12:00:00.000Z"),
    },
  );
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("Retry-After"), "23");
});
