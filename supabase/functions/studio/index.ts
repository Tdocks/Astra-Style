// ============================================================================
// studio/index.ts
// ============================================================================
// Deployment entrypoint for the `studio` Edge Function — the grouped
// function serving spec §14's `POST /studio/generate` and
// `GET /studio/status/:id` (ADR 0013: one function per first path
// segment, dispatching on the remainder via `_shared/routing.ts`).
//
// THE PROVIDER SWAP HAPPENS HERE AND NOWHERE ELSE (ADR 0004). `provider`
// below is the single decision point for which `ImageGenerationProvider`
// backs these endpoints. Default: `MockImageGenerationProvider`, which
// writes an unmistakable placeholder — never a fake likeness — to the real
// result path. Live OpenAI adapter (`gpt-image-1.5`, docs/08 §3.5's
// measured decision) only when `IMAGE_GENERATION_PROVIDER=openai` AND
// `IMAGE_PROVIDER_API_KEY` are both set. A vendor swap changes this file
// only — not handler.ts, not the DTO, not a single Swift file.
//
// THE KEY IS `IMAGE_PROVIDER_API_KEY` — spec §25's one-variable-per-
// capability scheme. The closet function's header records what happens
// when this scheme is ignored (six weeks of silent mock because the code
// asked for a vendor-named variable nobody set); the same loud-error-on-
// half-configuration policy is copied here so a misconfigured deploy says
// which variable is missing instead of quietly serving grey squares.
//
// Server-only job writes/allowances use a privileged client (ADR 0022).
// Authentication and reference-image reads remain caller-scoped under RLS.
// Generated result writes use the service-role client only after checking the
// canonical path against a live generation row owned by that path's user.
// ============================================================================

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { serverError } from "../_shared/errors.ts";
import type {
  ImageGenerationProvider,
  StudioGarment,
} from "../_shared/providers/imageGeneration.ts";
import { MockImageGenerationProvider } from "../_shared/providers/mockImageGeneration.ts";
import { OpenAIImageGenerationProvider } from "../_shared/providers/openaiImageGeneration.ts";
import {
  handleGenerate,
  handleHiResExport,
  handleStatus,
  type StudioGarmentSource,
} from "./handler.ts";

import { handleQuota, readQuota } from "./quota.ts";
import { supabaseJobStore } from "./jobStore.ts";
import { deletionDeps, handleDelete } from "./deletion.ts";
import { storeOwnedStudioResult } from "./resultStorage.ts";

const env = readEdgeEnv();
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!serviceKey) throw new Error("Studio server writes require SUPABASE_SERVICE_ROLE_KEY.");
const jobClient = createClient(env.supabaseUrl, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Generate is a paid-provider action and the row insert is cheap — 6/min
// absorbs a double-tap without letting a runaway loop enqueue a backlog.
// Status must comfortably cover the client's backoff schedule (2s → 4s,
// docs/10 §2.4: at most ~20 polls across the 90s window) plus a couple of
// concurrent jobs. Per-isolate and honest about it — see rateLimit.ts.
const generateRateLimiter = createRateLimiter({ limit: 6, windowMs: 60_000 });
const statusRateLimiter = createRateLimiter({ limit: 120, windowMs: 60_000 });

const USER_CONTENT_BUCKET = "user-content";

interface StorageSeam {
  loadImageBytes(storagePath: string): Promise<Uint8Array>;
  storeResult(storagePath: string, bytes: Uint8Array, contentType: string): Promise<void>;
  resultExists(storagePath: string): Promise<boolean>;
}

function storageSeam(supabase: SupabaseClient): StorageSeam {
  return {
    async loadImageBytes(storagePath: string): Promise<Uint8Array> {
      const { data, error } = await supabase.storage.from(USER_CONTENT_BUCKET).download(
        storagePath,
      );
      if (error || !data) {
        throw serverError("Couldn't load the reference image for generation.");
      }
      return new Uint8Array(await data.arrayBuffer());
    },
    async storeResult(storagePath: string, bytes: Uint8Array, contentType: string): Promise<void> {
      // upsert: a §21 retry of a lost render may legitimately rewrite the
      // same deterministic path.
      const { data, error: authError } = await supabase.auth.getUser();
      if (authError || !data.user) throw serverError("Couldn't store the generated image.");
      await storeOwnedStudioResult(data.user.id, storagePath, bytes, contentType, {
        async hasLiveOwnedGeneration(userId, generationId) {
          const { data, error } = await jobClient.from("studio_generations")
            .select("id")
            .eq("id", generationId)
            .eq("user_id", userId)
            .in("status", ["queued", "generating"])
            .is("deleted_at", null)
            .maybeSingle();
          return !error && data !== null;
        },
        async ownerHasPendingDeletion(userId) {
          const { data, error } = await jobClient.from("account_deletions")
            .select("id")
            .eq("user_id", userId)
            .in("status", ["pending", "processing"])
            .limit(1)
            .maybeSingle();
          // Treat an unreadable deletion state as pending. A privileged
          // result write must not race an uncertain account-erasure state.
          if (error) return true;
          return data !== null;
        },
        async enqueueOrphanCleanup(userId, generationId, path) {
          const { error } = await jobClient.rpc("enqueue_studio_orphan_result_cleanup", {
            p_owner_id: userId,
            p_generation_id: generationId,
            p_storage_path: path,
          });
          if (error) throw serverError("Couldn't queue generated-image cleanup.");
        },
        async upload(path, imageBytes, type) {
          const { error } = await jobClient.storage.from(USER_CONTENT_BUCKET).upload(
            path,
            // A fresh copy so the Blob cannot capture a larger backing buffer.
            new Blob([new Uint8Array(imageBytes).buffer], { type }),
            { contentType: type, upsert: true, cacheControl: "60" },
          );
          if (error) throw serverError("Couldn't store the generated image.");
        },
        async remove(path) {
          // `storeOwnedStudioResult` validates this exact canonical owner/job
          // path before handing it to the service-role cleanup seam.
          const { error } = await jobClient.storage.from(USER_CONTENT_BUCKET).remove([path]);
          if (error) throw serverError("Couldn't clean up an unowned generated image.");
        },
        async completeOrphanCleanup(path) {
          const { error } = await jobClient.rpc("complete_studio_orphan_result_cleanup", {
            p_storage_path: path,
          });
          if (error) throw serverError("Couldn't finish generated-image cleanup.");
        },
      });
    },
    async resultExists(storagePath: string): Promise<boolean> {
      const lastSlash = storagePath.lastIndexOf("/");
      const directory = storagePath.slice(0, lastSlash);
      const filename = storagePath.slice(lastSlash + 1);
      const { data, error } = await supabase.storage.from(USER_CONTENT_BUCKET).list(directory, {
        search: filename,
      });
      if (error || !data) {
        return false;
      }
      return data.some((entry) => entry.name === filename);
    },
  };
}

function buildProvider(
  storage: StorageSeam,
): { provider: ImageGenerationProvider; providerName: string } {
  const mode = (Deno.env.get("IMAGE_GENERATION_PROVIDER") ?? "mock").toLowerCase();
  const apiKey = Deno.env.get("IMAGE_PROVIDER_API_KEY");
  if (mode === "openai" && !apiKey) {
    // Loud, once per request path, and it names the variable — the closet
    // function's six-week silent-mock bug is the reason this is not quiet.
    console.error(
      "[studio] IMAGE_GENERATION_PROVIDER=openai but IMAGE_PROVIDER_API_KEY is not set. " +
        "Falling back to the mock generator: every generation will return a placeholder " +
        "square that nothing rendered. Set the secret (spec §25) or unset " +
        "IMAGE_GENERATION_PROVIDER to run on the mock deliberately.",
    );
  }
  if (mode === "openai" && apiKey) {
    return {
      providerName: "openai",
      provider: new OpenAIImageGenerationProvider({
        apiKey,
        // Pinned per docs/08 §3.5 — newest measured WORSE on identity
        // retention. Re-measure on docs/15 §3a's protocol before moving.
        model: Deno.env.get("IMAGE_PROVIDER_MODEL") ?? "gpt-image-1.5",
        loadImageBytes: storage.loadImageBytes,
        storeResult: storage.storeResult,
        resultExists: storage.resultExists,
      }),
    };
  }
  return {
    providerName: "mock",
    provider: new MockImageGenerationProvider({
      storeResult: storage.storeResult,
      resultExists: storage.resultExists,
    }),
  };
}

interface ClosetItemGarmentRow {
  name: string | null;
  subcategory: string | null;
  category: string;
  primary_color: string | null;
  pattern: string | null;
  material: unknown;
  fit: string | null;
}

function garmentFromClosetItem(item: ClosetItemGarmentRow, role: string): StudioGarment {
  const material = Array.isArray(item.material)
    ? (item.material as unknown[]).filter((entry): entry is string => typeof entry === "string")
    : [];
  return {
    role,
    normalizedTitle: item.name ?? item.subcategory ?? item.category,
    colorDescription: item.primary_color ?? "",
    material,
    pattern: item.pattern ?? "",
    fit: item.fit ?? "",
  };
}

const CLOSET_ITEM_COLUMNS = "name, subcategory, category, primary_color, pattern, material, fit";

function supabaseGarmentSource(supabase: SupabaseClient): StudioGarmentSource {
  return {
    async outfitGarments(userId, outfitId) {
      void userId;
      const { data, error } = await supabase
        .from("outfit_items")
        .select(`role, sort_order, closet_items(${CLOSET_ITEM_COLUMNS})`)
        .eq("outfit_id", outfitId)
        .order("sort_order", { ascending: true });
      if (error) {
        throw serverError("Couldn't load that outfit's items.");
      }
      // `as unknown` first: supabase-js types an embedded to-one resource
      // as an array even though `outfit_items.closet_item_id` is a to-one
      // FK and PostgREST returns an object for it at runtime.
      const rows = (data ?? []) as unknown as Array<
        { role: string; closet_items: ClosetItemGarmentRow | null }
      >;
      // Product-candidate slots (shop-the-look "missing item" slots) have
      // no closet row and are skipped: Studio renders what the man OWNS;
      // rendering a candidate he hasn't bought as if hanging in his closet
      // would be the §11 confounded reading in image form.
      return rows
        .filter((row) => row.closet_items !== null)
        .map((row) => garmentFromClosetItem(row.closet_items as ClosetItemGarmentRow, row.role));
    },
    async itemGarments(userId, itemIds) {
      void userId;
      const { data, error } = await supabase
        .from("closet_items")
        .select(CLOSET_ITEM_COLUMNS)
        .in("id", itemIds);
      if (error) {
        throw serverError("Couldn't load those closet items.");
      }
      const rows = (data ?? []) as ClosetItemGarmentRow[];
      return rows.map((row) => garmentFromClosetItem(row, row.category));
    },
  };
}

function depsFor(req: Request) {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  const supabase = createUserScopedClient(env, authorizationHeader);
  const { provider, providerName } = buildProvider(storageSeam(supabase));
  return {
    authClient: supabase,
    provider,
    providerName,
    jobStore: supabaseJobStore(jobClient),
    garmentSource: supabaseGarmentSource(supabase),
    generateRateLimiter,
    statusRateLimiter,
    now: () => new Date(),
    hasActivePremiumSubscription: (nowIso: string) =>
      hasActivePremiumSubscription(supabase, nowIso),
    freeStudioTrialGenerations: 1,
  };
}

const PREMIUM_STATUSES = new Set(["trialing", "active", "in_grace_period", "in_billing_retry"]);

async function hasActivePremiumSubscription(
  supabase: SupabaseClient,
  nowIso: string,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("status, expires_at");
  if (error) {
    return false;
  }
  const rows = (data ?? []) as Array<{ status: string; expires_at: string | null }>;
  return rows.some((row) =>
    PREMIUM_STATUSES.has(row.status) &&
    (row.expires_at === null || row.expires_at > nowIso)
  );
}

Deno.serve(createRouter("studio", [
  {
    method: "POST",
    pattern: "/export-hi-res",
    handler: (req) => handleHiResExport(req, depsFor(req)),
  },
  {
    method: "GET",
    pattern: "/quota",
    handler: (req) =>
      handleQuota(
        req,
        createUserScopedClient(env, req.headers.get("authorization") ?? ""),
        (userID) => readQuota(jobClient, userID, new Date()),
      ),
  },
  {
    method: "DELETE",
    pattern: "/generations/:id",
    handler: (req, params) =>
      handleDelete(
        req,
        deletionDeps(
          createUserScopedClient(env, req.headers.get("authorization") ?? ""),
          jobClient,
        ),
        params["id"] ?? "",
      ),
  },
  { method: "POST", pattern: "/generate", handler: (req) => handleGenerate(req, depsFor(req)) },
  {
    method: "GET",
    pattern: "/status/:id",
    handler: (req, params) => handleStatus(req, depsFor(req), params["id"] ?? ""),
  },
]));
