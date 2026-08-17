// ============================================================================
// account/handler.ts
// ============================================================================
// `DELETE /account` (spec §14/§15, ticket P7-PRIVACY-01, App Store Guideline
// 5.1.1(v)). Deployment wiring lives in `index.ts`; everything here is pure
// enough to unit test with an injected fake repository and no network
// access, following `profile/handler.ts` and `closet/handler.ts`'s shape.
//
// THE ORCHESTRATION THIS FILE IMPLEMENTS, matched step-for-step against the
// prose in `supabase/migrations/20260728101300_account_deletion.sql`'s
// header comment (steps 1-2 happen inline; steps 3-6 happen in the
// background — see "WHY THE CASCADE RUNS AFTER THE RESPONSE" below):
//   1. Validate the caller's JWT -> userId.                     (inline)
//   2. `request_account_deletion()` as the caller -> deletion_id, and
//      respond 202 immediately with it.                          (inline)
//   3. Storage API: remove every object under `users/{user_id}/`
//      in `user-content` (service role).                     (background)
//   4. `finalize_account_deletion(deletion_id)` (service role). (background)
//   5. `auth.admin.deleteUser(user_id)` (service role, Auth
//      Admin API) — the actual row cascade.                  (background)
//   6. `mark_account_deletion_complete(deletion_id)` (service role),
//      or `mark_account_deletion_failed(deletion_id, reason)` on any
//      failure in steps 3-5.                                  (background)
//
// WHY THE CASCADE RUNS AFTER THE RESPONSE, NOT BEFORE IT: the migration's
// own orchestration comment says so explicitly — "Respond to the client
// immediately with 202 Accepted + deletion_id ... rather than blocking on
// the steps below" — and §15 independently allows "a deletion job with
// user-visible status if immediate deletion cannot complete synchronously".
// Blocking the HTTP response on steps 3-5 would mean a phone on a bad
// connection times out waiting for a Storage API sweep + an Auth Admin API
// call it has no way to retry safely (a second `DELETE /account` from a
// client that never saw the first response must NOT start a second
// cascade — see the idempotency handling below), for an operation the user
// already confirmed and does not need to watch happen in real time. `202 +
// deletion_id` lets the client show "deletion in progress" (the UI ticket,
// P7-PRIVACY-02) and poll `account_deletions` if it wants to, instead of
// holding a socket open across the app's single most expensive call chain.
//
// WHY THE CASCADE IS STILL SYNCHRONOUS *WITHIN ITSELF*, RATHER THAN A QUEUE:
// there is no job-queue infrastructure in this project's scope (same
// exclusion `_shared/rateLimit.ts` documents for a durable rate limiter) —
// `deps.background()` is Edge-Function-native "keep the isolate alive after
// responding" (see index.ts's `EdgeRuntime.waitUntil` wiring), not a durable
// retryable job. If the isolate is killed mid-cascade the account_deletions
// row is left at 'pending' or 'processing' rather than 'failed', which is a
// real, stated limitation — an operator polling stuck rows past a
// reasonable timeout is the recovery path this vertical slice has, not
// silent automatic retry.
// ============================================================================

import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  serverError,
} from "../_shared/errors.ts";
import { createLogger, type RequestLogger } from "../_shared/logger.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { type AccountDeletionStatusDTO, tryExtractRequestId } from "./schema.ts";

/** What `request_account_deletion()` can return via the user-scoped RPC. */
export type InFlightDeletionStatus = "pending" | "processing";

export interface DeletionRequestResult {
  deletionId: string;
  status: InFlightDeletionStatus;
  /**
   * `false` when this call found an ALREADY in-flight deletion for this
   * user rather than creating a new one. This is the field the handler
   * uses to decide whether to start the cascade — see the idempotency
   * comment on `AccountDeletionRepository.requestDeletion` below.
   */
  freshlyRequested: boolean;
}

/**
 * The four privileged steps the migration documents, plus the request that
 * kicks the job off. Split out from `HandlerDeps` as its own interface
 * (rather than inlined) so `handler_test.ts` can build one fake that is
 * handed to both the inline and the backgrounded code paths, matching how
 * the real repository in index.ts is one object backed by two Supabase
 * clients (caller-scoped for step 2, service-role for steps 3-6).
 */
export interface AccountDeletionRepository {
  /**
   * Step 2. Calls `request_account_deletion()` — which reads ONLY
   * `auth.uid()` from the caller-scoped connection, never `userId` — and
   * returns the resulting deletion id.
   *
   * MUST be idempotent from the caller's perspective. `request_account_
   * deletion()` itself raises rather than inserting a second row when one
   * is already `pending`/`processing` for this user (see the migration);
   * the production implementation of this method catches exactly that
   * condition and returns the EXISTING row's id/status with
   * `freshlyRequested: false` instead of surfacing it as an error. This is
   * what makes a client's retried `DELETE /account` (dropped connection,
   * double-tap past a UI that should have disabled itself, etc.) land here
   * safely: same response shape either way, and only the first call's
   * result carries `freshlyRequested: true`, which is the ONLY thing that
   * triggers `runCascade` below. A second call never reaches steps 3-5
   * again, so it can never remove a second user's worth of storage
   * objects (there is only ever one caller in play) and can never call
   * `auth.admin.deleteUser` twice on an id GoTrue may have already
   * forgotten.
   *
   * `userId` is the JWT-verified id from `authenticateRequest`, threaded
   * through for interface symmetry and so a test can assert this method is
   * called with it — exactly as `OnboardingRepository.complete`'s `userId`
   * parameter does in `profile/handler.ts`. The production implementation
   * passes NOTHING to the RPC itself.
   */
  requestDeletion(userId: string): Promise<DeletionRequestResult>;

  /**
   * Step 3. Removes every Storage object under `users/{userId}/` in the
   * `user-content` bucket via the Storage API (service role) — the actual
   * blob deletion, not just `storage.objects` metadata rows.
   */
  purgeStorage(userId: string): Promise<void>;

  /** Step 4. `finalize_account_deletion(deletion_id)` (service role). */
  finalizeMetadata(deletionId: string): Promise<void>;

  /**
   * Step 5. `auth.admin.deleteUser(userId)` (service role, Auth Admin
   * API). This is what actually deletes the `auth.users` row and, via
   * `on delete cascade`, every user-owned row the migration's header
   * enumerates — see this file's top-of-file comment.
   */
  deleteAuthIdentity(userId: string): Promise<void>;

  /** Step 6, success path. `mark_account_deletion_complete(deletion_id)`. */
  markComplete(deletionId: string): Promise<void>;

  /** Step 6, failure path. `mark_account_deletion_failed(deletion_id, reason)`. */
  markFailed(deletionId: string, reason: string): Promise<void>;
}

export interface HandlerDeps {
  authClient: AuthClient;
  repository: AccountDeletionRepository;
  rateLimiter: RateLimiter;
  now: () => Date;
  /**
   * Runs `task` without the HTTP response waiting on it. Production
   * (index.ts) wraps `EdgeRuntime.waitUntil` so the Deno Deploy isolate is
   * kept alive after `Deno.serve`'s handler returns; the default test
   * double just invokes `task()` immediately and lets the test `await` the
   * returned promise before asserting on the fake repository's recorded
   * calls. Either way `task()` is always actually invoked — this seam
   * controls WHEN the response is allowed to return relative to the
   * cascade, never WHETHER the cascade runs, so a broken fake here can
   * make a test flaky but can never make it silently skip the cascade
   * entirely and still pass.
   */
  background: (task: () => Promise<void>) => void;
}

/**
 * Runs steps 3-6 of the migration's orchestration, after the 202 response
 * for a freshly-requested deletion has already been built. Never called
 * for an idempotent replay (`freshlyRequested: false`) — see
 * `AccountDeletionRepository.requestDeletion`'s header comment.
 *
 * Each step's failure calls `markFailed` with a specific, non-sensitive
 * reason code and stops — later steps never run against a user/storage
 * state a prior step already gave up on. `userId` and `deletionId` are the
 * only two things logged; nothing about WHY a step failed beyond the error
 * class ever reaches structured logs (spec §14 "avoid logging private
 * content"), and the full Postgres/Storage/GoTrue error detail is
 * available in the platform's own logs for anyone who needs it.
 */
export async function runCascade(
  userId: string,
  deletionId: string,
  repository: AccountDeletionRepository,
  logger: RequestLogger,
): Promise<void> {
  const failStep = async (step: string, reason: string, err: unknown): Promise<void> => {
    logger.error("account_delete.cascade_step_failed", {
      user_id: userId,
      deletion_id: deletionId,
      step,
      error_name: err instanceof Error ? err.name : "unknown",
    });
    try {
      await repository.markFailed(deletionId, reason);
    } catch (markErr) {
      // Nothing left to retry from in-process code at this point — see
      // this file's header on the queue-less cascade's limitations. This
      // is the loudest signal a stuck-at-'processing' row can leave.
      logger.error("account_delete.mark_failed_also_failed", {
        user_id: userId,
        deletion_id: deletionId,
        error_name: markErr instanceof Error ? markErr.name : "unknown",
      });
    }
  };

  try {
    await repository.purgeStorage(userId);
  } catch (err) {
    await failStep("purge_storage", "storage_purge_failed", err);
    return;
  }

  try {
    await repository.finalizeMetadata(deletionId);
  } catch (err) {
    await failStep("finalize_metadata", "finalize_metadata_failed", err);
    return;
  }

  try {
    await repository.deleteAuthIdentity(userId);
  } catch (err) {
    await failStep("delete_auth_identity", "auth_identity_delete_failed", err);
    return;
  }

  try {
    await repository.markComplete(deletionId);
  } catch (err) {
    // The identity — and with it, per the migration's cascade, every row
    // §15 requires gone — is ALREADY DELETED by this point. The one thing
    // that failed is recording that fact. Calling markFailed here would be
    // the exact "confounded reading" the house rule forbids: it would tell
    // an operator the deletion failed when what actually failed is a
    // status update about a deletion that succeeded. Logging loudly and
    // leaving the row at 'processing' is the honest state — a stuck-at-
    // 'processing' row with no matching auth.users entry is a known,
    // findable inconsistency; a row that says 'failed' for an account that
    // no longer exists is a lie an operator would act on.
    logger.error("account_delete.mark_complete_failed", {
      user_id: userId,
      deletion_id: deletionId,
      error_name: err instanceof Error ? err.name : "unknown",
    });
    return;
  }

  logger.info("account_delete.cascade_complete", { user_id: userId, deletion_id: deletionId });
}

export async function handleDeleteAccount(
  req: Request,
  deps: HandlerDeps,
): Promise<Response> {
  const startedAtMs = deps.now().getTime();

  const preflight = handleCorsPreflight(req);
  if (preflight) {
    return preflight;
  }

  let requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "DELETE") {
      throw methodNotAllowed("DELETE /account only accepts DELETE.");
    }

    // 1. Validate JWT. This is the ONLY place a user id enters this
    // handler. There is no field anywhere in this file, `schema.ts`, or
    // `AccountDeletionRepository` that accepts a client-supplied id — see
    // schema.ts's header comment. A request whose body claims to act on
    // some other user id has no code path to reach, rather than a check
    // that could be forgotten or bypassed.
    const userId = await authenticateRequest(req, deps.authClient);

    // 2. Rate limit. See index.ts for the chosen limit and why.
    const rateLimitResult = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!rateLimitResult.allowed) {
      logger.warn("account_delete.rate_limited", {
        user_id: userId,
        retry_after_seconds: rateLimitResult.retryAfterSeconds,
      });
      return errorResponse(
        new AppError("rate_limited", 429, "Too many requests. Please try again shortly."),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(rateLimitResult.retryAfterSeconds) },
      );
    }

    // 3. Validate request schema. There is nothing to validate — see
    // schema.ts's header — beyond optionally recovering a client-minted
    // request_id for log correlation.
    const rawBodyText = await req.text();
    const bodyRequestId = tryExtractRequestId(rawBodyText);
    requestId = resolveRequestId(req, bodyRequestId);
    logger.adoptRequestId(requestId);

    // 4. Ownership: structural, not checked — see the comment on `userId`
    // above and on `AccountDeletionRepository.requestDeletion`.
    const result = await deps.repository.requestDeletion(userId);

    if (result.freshlyRequested) {
      deps.background(() => runCascade(userId, result.deletionId, deps.repository, logger));
    } else {
      // Idempotency: a retried DELETE lands here instead of starting a
      // second cascade. Same 202 shape either way — the client cannot
      // distinguish "this call started the deletion" from "a deletion was
      // already running", which is the point: both mean "you are safe to
      // show the in-progress state".
      logger.info("account_delete.idempotent_replay", {
        user_id: userId,
        deletion_id: result.deletionId,
        status: result.status,
      });
    }

    // 5 & 6. Request id + latency, and only non-content fields — no email,
    // no profile data, nothing about what was in this account.
    logger.info("account_delete.accepted", {
      user_id: userId,
      deletion_id: result.deletionId,
      freshly_requested: result.freshlyRequested,
      latency_ms: deps.now().getTime() - startedAtMs,
    });

    const payload: AccountDeletionStatusDTO = {
      deletion_id: result.deletionId,
      status: result.status,
    };
    return jsonResponse(payload, { status: 202, requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    const latencyMs = deps.now().getTime() - startedAtMs;
    const appError = err instanceof AppError ? err : serverError();

    if (err instanceof AppError) {
      logger.warn("account_delete.rejected", {
        category: appError.category,
        status: appError.status,
        message: appError.message,
        latency_ms: latencyMs,
      });
    } else {
      logger.error("account_delete.unexpected_error", {
        latency_ms: latencyMs,
        error_name: err instanceof Error ? err.name : "unknown",
      });
    }

    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
