// ============================================================================
// closet/index.ts
// ============================================================================
// Deployment entrypoint for the `closet` Edge Function — the grouped
// function serving every spec §14 endpoint whose path starts with
// `closet/`. Supabase routes `/functions/v1/{slug}/...` by the FIRST path
// segment only, so analyze-item, batch-analyze and batch-status must be
// one deployed function (slug `closet`) that dispatches on the path
// remainder itself — see docs/adr/0013-edge-function-routing.md.
//
// Routes:
//   POST /analyze-item          -> handleAnalyzeItem
//   POST /batch-analyze         -> handleBatchAnalyze (enqueue only)
//   GET  /batch-status/:id      -> handleBatchStatus (advance + poll)
//
// THE PROVIDER SWAP HAPPENS HERE AND NOWHERE ELSE.
//
// `provider` below is the single line that decides which
// `VisionAnalysisProvider` (spec §8 / docs/08 §2) backs these endpoints.
// Default: `MockVisionAnalysisProvider`. Live OpenAI adapter when
// `VISION_ANALYSIS_PROVIDER=openai` and `OPENAI_API_KEY` are set. A vendor
// swap changes this file only — not handler.ts, not the DTO, not
// `AstraEndpoint`, not `ClosetRepository`, not a single Swift file.
//
// NOTE ON SERVICE-ROLE: this function never constructs a service-role
// client. Job rows and idempotency rows are owned by the caller; RLS with
// the caller's JWT is sufficient.
// ============================================================================

import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { serverError } from "../_shared/errors.ts";
import { MockVisionAnalysisProvider } from "../_shared/providers/mockVisionAnalysis.ts";
import { OpenAIVisionAnalysisProvider } from "../_shared/providers/openaiVisionAnalysis.ts";
import type { VisionAnalysisProvider } from "../_shared/providers/visionAnalysis.ts";
import {
  type AnalysisJobRow,
  type AnalysisJobStore,
  handleAnalyzeItem,
  handleBatchAnalyze,
  handleBatchStatus,
  type IdempotencyStore,
  type JobStatus,
} from "./handler.ts";
import type {
  AnalyzeItemElement,
  ClosetItemAnalysisBatchItemDTO,
  ClosetItemAnalysisResultDTO,
} from "./schema.ts";

const env = readEdgeEnv();

// Shared across every route in this function on purpose: the limit protects
// the isolate (and the user's provider budget), not any one endpoint. Batch
// work must stay job+poll so it cannot monopolise this budget.
const rateLimiter = createRateLimiter({ limit: 30, windowMs: 60_000 });

function buildProvider(authorizationHeader: string): VisionAnalysisProvider {
  const mode = (Deno.env.get("VISION_ANALYSIS_PROVIDER") ?? "mock").toLowerCase();
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (mode === "openai" && apiKey) {
    const supabase = createUserScopedClient(env, authorizationHeader);
    return new OpenAIVisionAnalysisProvider({
      apiKey,
      model: Deno.env.get("OPENAI_VISION_MODEL") ?? "gpt-5.6",
      async loadImageBytes(storagePath: string): Promise<Uint8Array> {
        const { data, error } = await supabase.storage.from("user-content").download(storagePath);
        if (error || !data) {
          throw serverError("Couldn't load the uploaded image for analysis.");
        }
        return new Uint8Array(await data.arrayBuffer());
      },
    });
  }
  return new MockVisionAnalysisProvider();
}

async function sha256Hex(canonical: string): Promise<string> {
  const bytes = new TextEncoder().encode(canonical);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function supabaseIdempotencyStore(
  authorizationHeader: string,
): IdempotencyStore {
  const supabase = createUserScopedClient(env, authorizationHeader);
  return {
    async get(userId, key) {
      void userId;
      const { data, error } = await supabase
        .from("closet_analysis_idempotency")
        .select("request_hash, response_payload")
        .eq("idempotency_key", key)
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't read analysis idempotency state.");
      }
      if (!data) {
        return null;
      }
      return {
        requestHash: data.request_hash as string,
        responsePayload: data.response_payload as ClosetItemAnalysisResultDTO,
      };
    },
    async put(userId, key, requestHash, responsePayload) {
      const { error } = await supabase.from("closet_analysis_idempotency").insert({
        user_id: userId,
        idempotency_key: key,
        request_hash: requestHash,
        response_payload: responsePayload,
      });
      if (error) {
        // A concurrent insert of the same key is fine — the next read will
        // replay whoever won. Other errors are real.
        if (error.code !== "23505") {
          throw serverError("Couldn't persist analysis idempotency state.");
        }
      }
    },
  };
}

function supabaseJobStore(authorizationHeader: string): AnalysisJobStore {
  const supabase = createUserScopedClient(env, authorizationHeader);
  return {
    async create(userId, items) {
      // Persist the handler's AnalyzeItemElement shape; the wire uses
      // snake_case, so convert for storage consistency with the request log.
      const storedItems = items.map((item) => ({
        request_id: item.requestId,
        storage_path: item.storagePath,
        image_type: item.imageType,
        device_hints: item.deviceHints
          ? {
            dominant_colors_rgb: item.deviceHints.dominantColorsRgb,
            detected_text: item.deviceHints.detectedText,
            approximate_category: item.deviceHints.approximateCategory,
          }
          : null,
      }));
      const { data, error } = await supabase
        .from("closet_analysis_jobs")
        .insert({
          user_id: userId,
          status: "queued",
          items: storedItems,
          results: [],
        })
        .select("*")
        .single();
      if (error || !data) {
        throw serverError("Couldn't enqueue the batch analysis job.");
      }
      return mapStoredJob(data as Record<string, unknown>);
    },
    async get(userId, jobId) {
      void userId;
      const { data, error } = await supabase
        .from("closet_analysis_jobs")
        .select("*")
        .eq("id", jobId)
        .maybeSingle();
      if (error) {
        throw serverError("Couldn't load the batch analysis job.");
      }
      if (!data) {
        return null;
      }
      return mapStoredJob(data as Record<string, unknown>);
    },
    async save(job) {
      const { error } = await supabase
        .from("closet_analysis_jobs")
        .update({
          status: job.status,
          results: job.results,
          error_message: job.errorMessage ?? null,
        })
        .eq("id", job.id);
      if (error) {
        throw serverError("Couldn't update the batch analysis job.");
      }
    },
  };
}

function mapStoredJob(data: Record<string, unknown>): AnalysisJobRow {
  const rawItems = (data["items"] as Array<Record<string, unknown>>) ?? [];
  const items: AnalyzeItemElement[] = rawItems.map((entry) => {
    const hintsRaw = entry["device_hints"] as Record<string, unknown> | null | undefined;
    return {
      requestId: entry["request_id"] as string,
      storagePath: entry["storage_path"] as string,
      imageType: (entry["image_type"] as string) ?? "front",
      deviceHints: hintsRaw
        ? {
          dominantColorsRgb: (hintsRaw["dominant_colors_rgb"] as string[]) ?? [],
          detectedText: (hintsRaw["detected_text"] as string[]) ?? [],
          approximateCategory: hintsRaw["approximate_category"] as string | undefined,
        }
        : undefined,
    };
  });
  return {
    id: data["id"] as string,
    userId: data["user_id"] as string,
    status: data["status"] as JobStatus,
    items,
    results: (data["results"] as ClosetItemAnalysisBatchItemDTO[]) ?? [],
    errorMessage: (data["error_message"] as string | null) ?? undefined,
  };
}

function analyzeItemRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  return handleAnalyzeItem(req, {
    authClient: createUserScopedClient(env, authorizationHeader),
    provider: buildProvider(authorizationHeader),
    idempotencyStore: supabaseIdempotencyStore(authorizationHeader),
    rateLimiter,
    now: () => new Date(),
    hashRequest: sha256Hex,
  });
}

function batchAnalyzeRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  return handleBatchAnalyze(req, {
    authClient: createUserScopedClient(env, authorizationHeader),
    provider: buildProvider(authorizationHeader),
    jobStore: supabaseJobStore(authorizationHeader),
    rateLimiter,
    now: () => new Date(),
  });
}

function batchStatusRoute(
  req: Request,
  params: Readonly<Record<string, string>>,
): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  return handleBatchStatus(
    req,
    {
      authClient: createUserScopedClient(env, authorizationHeader),
      provider: buildProvider(authorizationHeader),
      jobStore: supabaseJobStore(authorizationHeader),
      rateLimiter,
      now: () => new Date(),
    },
    params["id"] ?? "",
  );
}

Deno.serve(createRouter("closet", [
  { method: "POST", pattern: "/analyze-item", handler: analyzeItemRoute },
  { method: "POST", pattern: "/batch-analyze", handler: batchAnalyzeRoute },
  { method: "GET", pattern: "/batch-status/:id", handler: batchStatusRoute },
]));
