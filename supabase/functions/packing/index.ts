// ============================================================================
// packing/index.ts
// ============================================================================
// `POST /packing/generate`. Same scorer as daily-brief / outfits.generate.
// JWT-scoped RLS. No service role. Wear This is not gated here.
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { CompatibilityOutfitScorer } from "../_shared/scoring/compatibilityScorer.ts";
import { handleGeneratePacking } from "./handler.ts";
import { createPackingRepository } from "./repository.ts";

const env = readEdgeEnv();
const rateLimiter = createRateLimiter({ limit: 10, windowMs: 60_000 });

function generateRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);

  return handleGeneratePacking(req, {
    authClient: supabase,
    repository: createPackingRepository(supabase),
    scorerForDay: (targetOccasion, wardrobeGraph) =>
      new CompatibilityOutfitScorer({ targetOccasion, wardrobeGraph }),
    rateLimiter,
    now: () => new Date(),
  });
}

Deno.serve(createRouter("packing", [
  { method: "POST", pattern: "/generate", handler: generateRoute },
]));
