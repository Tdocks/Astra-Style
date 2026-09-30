// ============================================================================
// profile/exportHandler.ts
// ============================================================================
// Authenticated personal-data export. All rows are read through a client
// carrying the caller's JWT and are additionally filtered by the JWT-derived
// owner id. No service-role credentials or other users' rows are involved.
// ============================================================================

import { CORS_HEADERS, handleCorsPreflight } from "../_shared/cors.ts";
import {
  AppError,
  errorResponse,
  jsonResponse,
  methodNotAllowed,
  rateLimited,
  serverError,
} from "../_shared/errors.ts";
import { type AuthClient, authenticateRequest } from "../_shared/jwt.ts";
import { createLogger } from "../_shared/logger.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import { resolveRequestId } from "../_shared/requestId.ts";

export interface PersonalDataExport {
  schema_version: 1;
  exported_at: string;
  owner_user_id: string;
  table_counts: Record<string, number>;
  tables: Record<string, unknown[]>;
}

export interface PersonalDataExportRepository {
  fetchForUser(userId: string): Promise<Record<string, unknown[]>>;
}

export interface ExportHandlerDeps {
  authClient: AuthClient;
  repository: PersonalDataExportRepository;
  rateLimiter: RateLimiter;
  now: () => Date;
}

export async function handlePersonalDataExport(
  req: Request,
  deps: ExportHandlerDeps,
): Promise<Response> {
  const startedAt = deps.now().getTime();
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  const requestId = resolveRequestId(req);
  const logger = createLogger(requestId);

  try {
    if (req.method !== "GET") {
      throw methodNotAllowed("GET /profile/export-data only accepts GET.");
    }

    const userId = await authenticateRequest(req, deps.authClient);
    const limit = deps.rateLimiter.check(userId, deps.now().getTime());
    if (!limit.allowed) {
      logger.warn("profile_export.rate_limited", {
        user_id: userId,
        retry_after_seconds: limit.retryAfterSeconds,
      });
      return errorResponse(
        rateLimited(),
        requestId,
        { ...CORS_HEADERS, "Retry-After": String(limit.retryAfterSeconds) },
      );
    }

    const tables = await deps.repository.fetchForUser(userId);
    const tableCounts = Object.fromEntries(
      Object.entries(tables).map(([name, rows]) => [name, rows.length]),
    );
    const rowCount = Object.values(tableCounts).reduce((total, count) => total + count, 0);
    const result: PersonalDataExport = {
      schema_version: 1,
      exported_at: deps.now().toISOString(),
      owner_user_id: userId,
      table_counts: tableCounts,
      tables,
    };

    logger.info("profile_export.completed", {
      user_id: userId,
      table_count: Object.keys(tables).length,
      row_count: rowCount,
      latency_ms: deps.now().getTime() - startedAt,
    });
    return jsonResponse(result, { requestId, extraHeaders: CORS_HEADERS });
  } catch (err) {
    const appError = err instanceof AppError
      ? err
      : serverError("Couldn't prepare your data export.");
    logger.warn("profile_export.failed", {
      category: appError.category,
      status: appError.status,
      latency_ms: deps.now().getTime() - startedAt,
      error_name: err instanceof Error ? err.name : "unknown",
    });
    return errorResponse(appError, requestId, CORS_HEADERS);
  }
}
