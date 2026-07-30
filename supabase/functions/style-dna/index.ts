// ============================================================================
// style-dna/index.ts
// ============================================================================
// Deployment entrypoint for the `style-dna` Edge Function — the grouped
// function serving every spec §14 endpoint whose path starts with
// `style-dna/`. Supabase routes `/functions/v1/{slug}/...` by the FIRST path
// segment only, so `POST /style-dna/generate` reaches a function whose slug
// is `style-dna` and which dispatches on `/generate` itself. See
// docs/adr/0013-edge-function-routing.md and `_shared/routing.ts`.
//
// Routes:
//   POST /generate -> handleGenerateStyleDna (handler.ts)
//
// THE PROVIDER SWAP HAPPENS HERE AND NOWHERE ELSE.
//
// `provider` below is the single line that decides which
// `StylistReasoningProvider` (spec §8) backs this endpoint. Today it is
// `DeterministicStylistProvider`; a live GPT-5.6 adapter
// (docs/08-provider-abstraction.md §1.5) replaces this one expression and
// nothing else in the repository — not handler.ts, not the DTO, not
// `AstraEndpoint`, not `ProfileRepository`, not a single Swift file. That is
// ADR 0004's decision 4 ("Provider selection ... is a server-side
// configuration concern, changeable without an app release") expressed as
// code rather than as an intention.
//
// What a live adapter still needs, stated plainly rather than implied:
//   • A vendor account with API-tier terms and training opted out (spec §29
//     is a hard legal gate, docs/08 §1.1), and its key set via
//     `supabase secrets set` — never in the repo, never in the app.
//   • An adapter implementing this protocol that translates
//     StylistCompletionRequest -> the vendor's request and its response ->
//     StylistCompletionResult, keeping every vendor concept inside itself.
//   • The §0.1 retry/circuit-breaker baseline and the escalation router
//     (docs/09 §2), neither of which exists yet in this repo.
//   • The golden-set and guardrail evaluation in docs/06 §7.1-7.2 run before
//     the first prompt version ships. `STYLE_DNA_SYSTEM_PROMPT_VERSION` in
//     handler.ts is what that eval would be pinned to.
//
// NOTE ON SERVICE-ROLE: this function never constructs a service-role client.
// It reads and writes only the caller's own style/body/lifestyle rows, all of
// which `authenticated` may already touch under RLS.
//
// NOTE ON GUESTS (ADR 0011): a guest has no JWT and no server profile, so
// `authenticateRequest` rejects the call before any read happens. Nothing
// client-side calls this for a guest either — the §6.10 result screen is
// reached through `OnboardingViewModel`, which routes guests to the
// local-draft path instead.
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { serverError } from "../_shared/errors.ts";
import { DeterministicStylistProvider } from "./deterministicStylist.ts";
import {
  type GeneratedSummary,
  handleGenerateStyleDna,
  type ProfileRows,
  type StyleProfileRepository,
} from "./handler.ts";

const env = readEdgeEnv();

// Tighter than `outfits` (20/min) and tighter still than `profile` (6/min).
// §6.10 offers a regenerate action, so a handful of runs in a minute is
// legitimate; anything past that is a stuck retry loop, and a live provider
// call costs real money per attempt (docs/09 §5). Same honest caveat as
// everywhere: per-isolate and in-memory, not a security boundary — see
// `_shared/rateLimit.ts`.
const rateLimiter = createRateLimiter({ limit: 5, windowMs: 60_000 });

// Stateless and free to share across requests in this isolate. THIS IS THE
// SWAP POINT — see the header.
const provider = new DeterministicStylistProvider();

function generateStyleDnaRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);

  const profileRepository: StyleProfileRepository = {
    async load(userId: string): Promise<ProfileRows> {
      // `userId` is accepted for interface symmetry and so the handler test
      // can assert the JWT-derived id is what reaches this layer. It is NOT
      // used to filter: Row Level Security (`style_profiles_select_own` and
      // siblings, `user_id = auth.uid()`) scopes these reads, driven by the
      // JWT attached to `supabase` above. Passing a different id here would
      // change nothing, which is the point.
      void userId;

      const [style, body, lifestyle] = await Promise.all([
        supabase.from("style_profiles").select("*").maybeSingle(),
        supabase.from("body_profiles").select("*").maybeSingle(),
        supabase.from("lifestyle_profiles").select("*").maybeSingle(),
      ]);

      // A missing ROW is normal — a user who skipped §6.6 and §6.8 entirely
      // has neither — and produces a sparser Style DNA, which is the
      // documented behaviour. A query ERROR is not normal and must not be
      // silently treated as "no data": that would generate a thin result
      // from a transient failure and then WRITE it over a good one.
      for (const result of [style, body, lifestyle]) {
        if (result.error) {
          throw serverError("Couldn't read your profile.");
        }
      }

      return {
        style: (style.data ?? null) as Record<string, unknown> | null,
        body: (body.data ?? null) as Record<string, unknown> | null,
        lifestyle: (lifestyle.data ?? null) as Record<string, unknown> | null,
      };
    },

    async saveGeneratedSummary(userId: string, summary: GeneratedSummary): Promise<string | null> {
      // These are the columns 20260730180000_style_preference_vector.sql
      // reserves for this endpoint. `preference_vector`, `primary_identity`,
      // `secondary_identities`, `style_goals` and `preferred_fit` are
      // deliberately absent from this write: they are the user's own answers
      // and `POST /profile/complete-onboarding` owns them. A generator that
      // wrote back over its own inputs would make regeneration non-idempotent
      // and would slowly overwrite what the user actually said.
      //
      // `upsert` rather than `update` so a user who reaches the §6.10 screen
      // without a style_profiles row (an interrupted onboarding, a profile
      // created before this table was populated) still gets a result stored
      // rather than a silent no-op. `user_id` is the JWT-derived id and is
      // also what `style_profiles_insert_own`'s WITH CHECK compares against,
      // so RLS rejects any other value outright.
      const { data, error } = await supabase
        .from("style_profiles")
        .upsert({ user_id: userId, ...summary }, { onConflict: "user_id" })
        .select("updated_at")
        .maybeSingle();

      if (error) {
        throw serverError("Couldn't save your Style DNA.");
      }
      const updatedAt = (data as { updated_at?: unknown } | null)?.updated_at;
      return typeof updatedAt === "string" ? updatedAt : null;
    },
  };

  return handleGenerateStyleDna(req, {
    authClient: supabase,
    profileRepository,
    provider,
    rateLimiter,
    now: () => new Date(),
  });
}

Deno.serve(createRouter("style-dna", [
  { method: "POST", pattern: "/generate", handler: generateStyleDnaRoute },
]));
