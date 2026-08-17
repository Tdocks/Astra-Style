// ============================================================================
// products/index.ts
// ============================================================================
// Composition root for `POST /products/extract` (P6-SHOP-03) and
// `POST /products/evaluate` (P6-SHOP-04), routed by first-path-segment per
// ADR 0013 exactly as every other deployed function is.
//
// WHY THE HTTP EDGE LIVES HERE RATHER THAN IN `handler.ts`.
// `outfits/handler.ts` takes a `Request` and returns a `Response`; this
// function's handlers take a parsed body and return a DTO. The split is
// deliberate and matches `account/`: everything that decides a VERDICT is
// pure and unit-tested against fixtures, and everything that decides a
// STATUS CODE is here. It costs this file a few lines of envelope handling
// and buys `handler_test.ts` the ability to assert on a verdict without
// constructing a `Request`.
//
// THE EXTRACTION PROVIDER IS ENV-SELECTED, AND DEFAULTS TO THE MOCK.
// Same policy `closet/` uses for vision: a deploy that forgets to set the
// provider gets deterministic fixtures rather than silently making live
// outbound requests to retailers on a user's behalf. `docs/17`'s §11 note
// applies — the live path is written and is not on by default.
//
// EVERY QUERY BELOW IS USER-SCOPED. There is no service-role client in this
// file. `product_candidates` is shared-read by design
// (`20260728100600_commerce.sql`) and `user_product_evaluations` is
// per-user; both are enforced by RLS driven from the caller's own JWT, not
// by a `where user_id = ...` this code could forget to write.
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { authenticateRequest } from "../_shared/jwt.ts";
import { type AppError, errorResponse, jsonResponse, serverError } from "../_shared/errors.ts";
import { rateLimited } from "../_shared/errors.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { MockProductExtractionProvider } from "../_shared/providers/mockProductExtraction.ts";
import { HtmlProductExtractionProvider } from "../_shared/providers/htmlProductExtraction.ts";
import type { ProductExtractionProvider } from "../_shared/providers/productExtraction.ts";
import { mapClosetItemRowToScorableItem } from "../_shared/scoring/closetItemMapper.ts";
import type { ClosetItemMapperRow } from "../_shared/scoring/closetItemMapper.ts";
import {
  handleEvaluateProduct,
  handleExtractProduct,
  type OwnedGarment,
  type ProductsDependencies,
} from "./handler.ts";
import type { ProductCandidateRow } from "./candidateMapper.ts";
import type { LifestyleInputs } from "./evaluation.ts";
import { parseEnvelope } from "./schema.ts";

const env = readEdgeEnv();

// 10/min. Extraction makes an outbound request to a third party and
// evaluation runs anchored generation over the whole closet, so this sits
// between `closet`'s 30 and `daily-brief`'s 10 rather than at `outfits`' 20.
// A man pasting links reads each verdict before pasting the next.
const rateLimiter = createRateLimiter({ limit: 10, windowMs: 60_000 });

function extractionProvider(): ProductExtractionProvider {
  return Deno.env.get("PRODUCT_EXTRACTION_PROVIDER") === "html"
    // `fetchImpl` injected rather than reached for globally: the provider's
    // own header explains why, and it is what keeps its tests off the
    // network. The composition root is the one place a real `fetch` belongs.
    ? new HtmlProductExtractionProvider({ fetchImpl: (url, init) => fetch(url, init) })
    : new MockProductExtractionProvider();
}

const SCORABLE_COLUMNS = [
  "id",
  "category",
  "primary_color",
  "secondary_colors",
  "pattern",
  "material",
  "fit",
  "seasonality",
  "formality_score",
  "warmth_score",
  "water_resistance_score",
  "laundry_state",
  "availability_state",
].join(", ");

const CANDIDATE_COLUMNS = [
  "id",
  "canonical_url",
  "retailer",
  "brand",
  "name",
  "category",
  "price",
  "currency",
  "image_url",
  "affiliate_url",
  "availability",
  "attributes",
  "sponsored",
  "last_checked_at",
].join(", ");

/** How many catalog rows §5.5's alternatives strip may draw from. */
const ALTERNATIVE_POOL_LIMIT = 12;

function buildDependencies(authorizationHeader: string, requestID: string): ProductsDependencies {
  const supabase = createUserScopedClient(env, authorizationHeader);

  return {
    extractionProvider: extractionProvider(),
    requestID,

    async upsertCandidate(row) {
      const { data, error } = await supabase
        .from("product_candidates")
        .upsert(row, { onConflict: "canonical_url" })
        .select(CANDIDATE_COLUMNS)
        .single();
      if (error || !data) throw serverError("Couldn't save that product.");
      return data as unknown as ProductCandidateRow;
    },

    async fetchCandidate(id) {
      const { data, error } = await supabase
        .from("product_candidates")
        .select(CANDIDATE_COLUMNS)
        .eq("id", id)
        .maybeSingle();
      if (error) throw serverError("Couldn't load that product.");
      return (data ?? null) as unknown as ProductCandidateRow | null;
    },

    async fetchCloset(userID) {
      // `userID` is unused on purpose: `closet_items_select_own` scopes this
      // by `auth.uid()` from the JWT already on `supabase`. Filtering here
      // too would be a second, forgettable copy of the same rule.
      void userID;
      const { data, error } = await supabase
        .from("closet_items")
        .select(SCORABLE_COLUMNS)
        .is("archived_at", null);
      if (error) throw serverError("Couldn't load your closet.");

      const rows = (data ?? []) as unknown as ClosetItemMapperRow[];
      return rows.flatMap((row): OwnedGarment[] => {
        const scorable = mapClosetItemRowToScorableItem(row);
        if (scorable === null) return [];
        return [{
          scorable,
          redundancy: {
            id: scorable.id,
            category: scorable.category,
            role: scorable.role,
            primaryColorLab: null,
            formalityScore: scorable.formalityScore,
            fit: scorable.fit,
            materials: scorable.materials,
            seasonality: scorable.seasonality,
          },
        }];
      });
    },

    async fetchLifestyle(userID) {
      void userID;
      const { data, error } = await supabase
        .from("lifestyle_profiles")
        .select("monthly_clothing_budget, primary_dress_code")
        .maybeSingle();
      // A missing lifestyle profile is the normal state for anyone who
      // skipped §6.8, not a failure. Both terms drop out of the verdict and
      // are named in `unmeasured` rather than substituted.
      if (error || !data) return { monthlyBudget: null, dressCode: null };
      const record = data as Record<string, unknown>;
      const budget = record["monthly_clothing_budget"];
      const dressCode = record["primary_dress_code"];
      return {
        monthlyBudget: typeof budget === "number" ? budget : null,
        dressCode: typeof dressCode === "string" ? dressCode : null,
      } satisfies LifestyleInputs;
    },

    async fetchAlternatives(category, excludingID) {
      if (category === null) return [];
      const { data, error } = await supabase
        .from("product_candidates")
        .select(CANDIDATE_COLUMNS)
        .eq("category", category)
        .neq("id", excludingID)
        .limit(ALTERNATIVE_POOL_LIMIT);
      if (error) throw serverError("Couldn't load alternatives.");
      return (data ?? []) as unknown as ProductCandidateRow[];
    },

    async persistEvaluation(row) {
      const { data, error } = await supabase
        .from("user_product_evaluations")
        .insert(row)
        .select("created_at")
        .single();
      if (error || !data) throw serverError("Couldn't save that verdict.");
      return data as { created_at: string };
    },
  };
}

function isAppError(value: unknown): value is AppError {
  return typeof value === "object" && value !== null && "status" in value && "category" in value;
}

/**
 * The one place both routes turn a thrown `AppError` into a response.
 *
 * An unrecognised throw becomes a 500 with a generic message rather than the
 * error's own text: an exception from the Postgrest client can carry column
 * names and constraint names, and those belong in the log, not in a response
 * body a user's device receives.
 */
async function respond(
  req: Request,
  work: (rawBody: unknown, userID: string, requestID: string) => Promise<unknown>,
): Promise<Response> {
  let requestID = resolveRequestId(req, null);
  try {
    const raw = await req.json().catch(() => ({}));
    const { requestId: bodyRequestID, body } = parseEnvelope(raw);
    requestID = resolveRequestId(req, bodyRequestID ?? null);

    const authorizationHeader = req.headers.get("Authorization") ??
      req.headers.get("authorization") ?? "";
    const userID = await authenticateRequest(
      req,
      createUserScopedClient(env, authorizationHeader),
    );

    const limit = rateLimiter.check(userID, Date.now());
    if (!limit.allowed) {
      return errorResponse(rateLimited(), requestID, {
        "Retry-After": String(limit.retryAfterSeconds),
      });
    }

    return jsonResponse(await work(body, userID, requestID), { requestId: requestID });
  } catch (error) {
    if (isAppError(error)) return errorResponse(error, requestID);
    return errorResponse(serverError(), requestID);
  }
}

function extractRoute(req: Request): Promise<Response> {
  return respond(req, (body, userID, requestID) => {
    const authorizationHeader = req.headers.get("Authorization") ??
      req.headers.get("authorization") ?? "";
    return handleExtractProduct(body, userID, buildDependencies(authorizationHeader, requestID));
  });
}

function evaluateRoute(req: Request): Promise<Response> {
  return respond(req, (body, userID, requestID) => {
    const authorizationHeader = req.headers.get("Authorization") ??
      req.headers.get("authorization") ?? "";
    return handleEvaluateProduct(body, userID, buildDependencies(authorizationHeader, requestID));
  });
}

Deno.serve(createRouter("products", [
  { method: "POST", pattern: "/extract", handler: extractRoute },
  { method: "POST", pattern: "/evaluate", handler: evaluateRoute },
]));
