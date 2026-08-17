// ============================================================================
// account/index.ts
// ============================================================================
// Deployment entrypoint for the `account` Edge Function — slug `account`,
// serving `DELETE /account` (spec §14, ticket P7-PRIVACY-01). This is the
// only endpoint whose path IS the function's root: `AstraEndpoint.path`
// resolves `.deleteAccount` to the bare string `"account"`, with no
// sub-segment, which is exactly the `pattern: "/"` case `_shared/
// routing.ts`'s own header comment names as its motivating example.
//
// THE SLUG TRAP THIS FUNCTION MUST NOT FALL INTO: this migration's own
// header comment (`supabase/migrations/20260728101300_account_deletion.sql`)
// instructs building "in `supabase/functions/account-delete`". That
// directory name would 404 in production: Supabase routes
// `/functions/v1/{slug}/...` by the deployed function's FIRST PATH SEGMENT
// only, the client builds `DELETE {base}/account` (not `/account-delete`),
// and `EndpointDeploymentMappingTests.expectedSlugs` on the iOS side
// already requires the slug `"account"` — it does not know or care what the
// migration's comment says. This is deployed at `account/` and the
// migration's comment has been corrected to match, in the same change that
// added this directory. See `docs/adr/0013-edge-function-routing.md` for
// the general rule and its own worked example (`outfits-generate` shipping
// instead of `outfits`, 404ing every production call while every unit test
// stayed green).
//
// SERVICE ROLE: this is the one function in this project that legitimately
// needs it (see `README.md`'s "Why no service-role key in `outfits`", which
// names this exact endpoint as the documented exception). Two Supabase
// clients are constructed per request:
//   - `createUserScopedClient` (this request's own JWT) for step 2,
//     `request_account_deletion()` — RLS-scoped, reads only `auth.uid()`.
//   - `serviceRoleClient` (module-scoped, built once at cold start — it
//     does not vary per caller the way the user-scoped client does) for
//     steps 3-6: the Storage API sweep, `finalize_account_deletion()`,
//     `auth.admin.deleteUser()`, and the two status-marking RPCs. RLS
//     cannot express any of these (deleting another table's rows via a
//     cascade this endpoint doesn't touch directly, or the GoTrue Admin
//     API, which has no RLS concept at all), which is what makes
//     service-role the correct tool here rather than a shortcut around it.
// ============================================================================

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createUserScopedClient, readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createRouter } from "../_shared/routing.ts";
import { createLogger } from "../_shared/logger.ts";
import {
  type AccountDeletionRepository,
  type DeletionRequestResult,
  handleDeleteAccount,
} from "./handler.ts";

const env = readEdgeEnv();

/**
 * Supabase auto-injects this for every deployed Edge Function and for
 * `supabase functions serve` against a local stack, the same as
 * `SUPABASE_URL`/`SUPABASE_ANON_KEY` (see `_shared/supabaseClient.ts`'s
 * `readEdgeEnv`). It is read here rather than added to that shared helper
 * because every OTHER function in this project deliberately does not need
 * it — see this file's header and `README.md`'s "Why no service-role key
 * in `outfits`" — and a shared reader would make it one line away from
 * being reached for out of convenience somewhere it has no business being.
 */
function readServiceRoleKey(): string {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY must be set. Supabase provides it automatically for " +
        "deployed Edge Functions and for `supabase functions serve` against a local stack.",
    );
  }
  return key;
}

// Built once per isolate, not per request — the service-role client's
// identity is the function itself, not the caller, so there is nothing
// request-scoped about it (contrast `createUserScopedClient`, which must be
// rebuilt every request against that request's own Authorization header).
const serviceRoleClient = createClient(env.supabaseUrl, readServiceRoleKey(), {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Account deletion is the single most expensive and most irreversible call
// in this API: a full Storage API sweep plus a GoTrue Admin API identity
// deletion, per request. It is also something a real user does at most a
// handful of times ever (the RPC itself refuses a second concurrent
// request for the same account — see handler.ts's idempotency comment), so
// there is no legitimate high-frequency use to protect, unlike `outfits`'s
// 20/min or `closet`'s 30/min. 3/min is chosen over 1/min specifically to
// leave room for the ordinary retry case (a client that times out waiting
// for a response and taps again, or `AstraAPIClient`'s own backoff-retry
// wrapper on a transient 5xx) without opening the door to a scripted loop
// against the Auth Admin API.
const rateLimiter = createRateLimiter({ limit: 3, windowMs: 60_000 });

const STORAGE_BUCKET = "user-content";
// Supabase Storage's own `list()` page cap.
const STORAGE_LIST_PAGE_SIZE = 1000;
// `remove()` accepts an array of paths; chunked defensively rather than
// assuming an arbitrarily large single call is guaranteed to succeed.
const STORAGE_REMOVE_BATCH_SIZE = 100;
// `users/{uid}/{feature}/{itemId}/{file}` (see
// `20260728101000_storage_buckets.sql`'s path shapes) is 4 segments deep
// from the bucket root. Doubled for headroom against a feature adding one
// more level of nesting later; this is a runaway-recursion guard, not a
// real, expected limit.
const MAX_STORAGE_RECURSION_DEPTH = 8;

/**
 * Recursively lists every OBJECT (not folder) path under `prefix` in the
 * `user-content` bucket.
 *
 * Storage's `list()` is one level deep per call and represents a "folder" —
 * really just a common prefix, not a real object — as an entry with
 * `id: null` and `metadata: null`; there is no dedicated `isFolder` field on
 * `FileObject`, so checking `id === null` is the documented way to tell a
 * folder apart from a real file. This matters here specifically because
 * `users/{user_id}/` is never flat: `closet/` alone nests one further level
 * per closet item (`closet/{closet_item_id}/{image_id}.jpg`), so a
 * single-level `list()` + `remove()` would silently leave every closet
 * photo behind while reporting success — the exact "confounded reading"
 * (a green response masking incomplete work) this project's house rule
 * forbids.
 */
async function listAllObjectPaths(
  storage: SupabaseClient["storage"],
  prefix: string,
  depth = 0,
): Promise<string[]> {
  if (depth > MAX_STORAGE_RECURSION_DEPTH) {
    throw new Error(
      `Storage prefix "${prefix}" is nested deeper than expected (> ${MAX_STORAGE_RECURSION_DEPTH} levels) — aborting rather than recursing without bound.`,
    );
  }
  const { data, error } = await storage.from(STORAGE_BUCKET).list(prefix, {
    limit: STORAGE_LIST_PAGE_SIZE,
  });
  if (error) {
    throw new Error(`Storage list failed for prefix "${prefix}": ${error.message}`);
  }
  const paths: string[] = [];
  for (const entry of data ?? []) {
    const entryPath = `${prefix}/${entry.name}`;
    if (entry.id === null) {
      paths.push(...(await listAllObjectPaths(storage, entryPath, depth + 1)));
    } else {
      paths.push(entryPath);
    }
  }
  return paths;
}

function chunk<T>(items: readonly T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

/**
 * The production `AccountDeletionRepository`. `userId` is the JWT-verified
 * id `handler.ts` threads through — never anything read from the request
 * body (there is no such field; see `schema.ts`) — so every service-role
 * call below, despite bypassing RLS entirely, only ever acts on the id the
 * caller authenticated as.
 */
function buildRepository(authorizationHeader: string): AccountDeletionRepository {
  const userScopedClient = createUserScopedClient(env, authorizationHeader);

  return {
    async requestDeletion(userId: string): Promise<DeletionRequestResult> {
      void userId; // Interface symmetry only — see handler.ts's doc comment.
      const { data, error } = await userScopedClient.rpc("request_account_deletion");
      if (!error) {
        if (typeof data !== "string") {
          throw new Error("request_account_deletion() did not return a deletion id.");
        }
        return { deletionId: data, status: "pending", freshlyRequested: true };
      }

      // `request_account_deletion()` raises this exact message (see the
      // migration) when a pending/processing row already exists for this
      // user. Matched by substring, not a Postgres error code, because the
      // function uses a plain `raise exception` (default SQLSTATE P0001,
      // indistinguishable by code from any other plpgsql exception) rather
      // than a custom SQLSTATE — there is no more precise signal to key on
      // without changing the migration's error-raising shape, which is out
      // of this endpoint's scope to do for a message-matching convenience.
      if (!error.message.includes("already in progress")) {
        throw new Error(`request_account_deletion() failed: ${error.message}`);
      }

      const { data: existing, error: selectError } = await userScopedClient
        .from("account_deletions")
        .select("id, status")
        .in("status", ["pending", "processing"])
        .order("requested_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (selectError || !existing) {
        // The RPC just told us a row exists; if we cannot find it a moment
        // later under the same RLS-scoped identity, something is wrong
        // enough that a generic failure is more honest than guessing.
        throw new Error(
          "request_account_deletion() reported an in-progress deletion, but it could not be read back.",
        );
      }
      const status = existing.status as string;
      if (status !== "pending" && status !== "processing") {
        throw new Error(`Unexpected in-progress deletion status: ${status}`);
      }
      return { deletionId: existing.id as string, status, freshlyRequested: false };
    },

    async purgeStorage(userId: string): Promise<void> {
      // Lowercased to match `assertOwnsStoragePath`'s convention elsewhere
      // (`closet/schema.ts`) and the RLS policies' own
      // `(select auth.uid())::text` comparison — Postgres's `auth.uid()`
      // renders lowercase even when a client minted an uppercase UUID
      // string (HANDOFF §5.3, referenced there too).
      const prefix = `users/${userId.toLowerCase()}`;
      const paths = await listAllObjectPaths(serviceRoleClient.storage, prefix);
      for (const batch of chunk(paths, STORAGE_REMOVE_BATCH_SIZE)) {
        const { error } = await serviceRoleClient.storage.from(STORAGE_BUCKET).remove(batch);
        if (error) {
          throw new Error(`Storage remove failed under "${prefix}": ${error.message}`);
        }
      }
    },

    async finalizeMetadata(deletionId: string): Promise<void> {
      const { error } = await serviceRoleClient.rpc("finalize_account_deletion", {
        p_deletion_id: deletionId,
      });
      if (error) {
        throw new Error(`finalize_account_deletion() failed: ${error.message}`);
      }
    },

    async deleteAuthIdentity(userId: string): Promise<void> {
      const { error } = await serviceRoleClient.auth.admin.deleteUser(userId);
      if (error) {
        throw new Error(`auth.admin.deleteUser() failed: ${error.message}`);
      }
    },

    async markComplete(deletionId: string): Promise<void> {
      const { error } = await serviceRoleClient.rpc("mark_account_deletion_complete", {
        p_deletion_id: deletionId,
      });
      if (error) {
        throw new Error(`mark_account_deletion_complete() failed: ${error.message}`);
      }
    },

    async markFailed(deletionId: string, reason: string): Promise<void> {
      const { error } = await serviceRoleClient.rpc("mark_account_deletion_failed", {
        p_deletion_id: deletionId,
        p_reason: reason,
      });
      if (error) {
        throw new Error(`mark_account_deletion_failed() failed: ${error.message}`);
      }
    },
  };
}

/**
 * Keeps `task` running after the response has been sent, via the Supabase
 * Edge Runtime's `EdgeRuntime.waitUntil` (a global injected by the
 * platform, present both when deployed and under `supabase functions
 * serve` — it is part of the edge-runtime Deno build both use, not a
 * production-only extra). `task()` is always invoked regardless of whether
 * `EdgeRuntime` is present; the global is only used to ask the platform to
 * keep the isolate alive for it. If it is ever absent (a future runtime
 * change, or this function running under some other Deno host), the
 * cascade still runs — it just loses the platform's guarantee not to
 * freeze the isolate before it finishes, which is the same honestly-stated
 * limitation `_shared/rateLimit.ts` documents for its own in-memory-only
 * implementation: real, useful work today, without a guarantee this
 * project doesn't have the infrastructure to back.
 */
function scheduleBackground(task: () => Promise<void>): void {
  const logger = createLogger("account-delete-background");
  const promise = task().catch((err: unknown) => {
    // Every failure inside `runCascade` already turns itself into a
    // `mark_account_deletion_failed()` call. Reaching this catch means
    // `runCascade` itself threw, which its own implementation is written
    // not to do — this is the last-resort net, not an expected path.
    logger.error("account_delete.background_task_unhandled_error", {
      error_name: err instanceof Error ? err.name : "unknown",
    });
  });
  const edgeRuntime = (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } })
    .EdgeRuntime;
  edgeRuntime?.waitUntil(promise);
}

function deleteAccountRoute(req: Request): Promise<Response> {
  const authorizationHeader = req.headers.get("Authorization") ??
    req.headers.get("authorization") ?? "";
  return handleDeleteAccount(req, {
    authClient: createUserScopedClient(env, authorizationHeader),
    repository: buildRepository(authorizationHeader),
    rateLimiter,
    now: () => new Date(),
    background: scheduleBackground,
  });
}

Deno.serve(createRouter("account", [
  { method: "DELETE", pattern: "/", handler: deleteAccountRoute },
]));
