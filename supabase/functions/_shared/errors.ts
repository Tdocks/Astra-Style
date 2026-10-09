// ============================================================================
// _shared/errors.ts
// ============================================================================
// The typed error envelope every Edge Function in this project returns.
// Deliberately mirrors `AstraError`/`AstraServerErrorPayload` in
// `ios/AstraStyle/Core/Networking/AstraError.swift` and
// `AstraRequestEnvelope.swift` so the client's existing decode/mapping logic
// (`AstraServerErrorPayload.asAstraError`) works against this server without
// any client-side changes:
//
//   { "data": <T> | null, "error": { "category": string, "message": string } | null, "request_id": string | null }
//
// `category` must be one of the strings `AstraServerErrorPayload.asAstraError`
// switches on: "network" | "auth" | "validation" | "provider" | "rate_limited"
// (anything else — including "server" — maps to `.server` on the client, so
// "server" is used verbatim here purely for readability, not because the
// client special-cases it).
// ============================================================================

export type ErrorCategory =
  | "network"
  | "auth"
  | "validation"
  | "server"
  | "provider"
  | "rate_limited"
  | "subscription_limit_reached";

/** Thrown by any layer of a function to signal a specific, typed failure. */
export class AppError extends Error {
  readonly category: ErrorCategory;
  /** HTTP status code this error should be returned with. */
  readonly status: number;
  /** Retry hint for 429 responses produced by a rate limiter. */
  readonly retryAfterSeconds?: number;
  readonly details?: Record<string, unknown>;

  constructor(
    category: ErrorCategory,
    status: number,
    message: string,
    retryAfterSeconds?: number,
    details?: Record<string, unknown>,
  ) {
    super(message);
    this.name = "AppError";
    this.category = category;
    this.status = status;
    if (retryAfterSeconds !== undefined && Number.isFinite(retryAfterSeconds)) {
      this.retryAfterSeconds = Math.max(1, Math.ceil(retryAfterSeconds));
    }
    if (details !== undefined) this.details = details;
  }
}

export function unauthorized(message = "Authentication required."): AppError {
  return new AppError("auth", 401, message);
}

export function badRequest(message: string): AppError {
  return new AppError("validation", 400, message);
}

export function rateLimited(
  message = "Too many requests. Please try again shortly.",
  retryAfterSeconds?: number,
): AppError {
  return new AppError("rate_limited", 429, message, retryAfterSeconds);
}

export function serverError(message = "Internal server error."): AppError {
  return new AppError("server", 500, message);
}

export function methodNotAllowed(message = "Method not allowed."): AppError {
  return new AppError("validation", 405, message);
}

export function notFound(message = "Not found."): AppError {
  return new AppError("validation", 404, message);
}

/** Wire shape of a successful or failed response body. */
export interface ResponseEnvelope<T> {
  data: T | null;
  error: { category: ErrorCategory; message: string; details?: Record<string, unknown> } | null;
  request_id: string | null;
}

const JSON_HEADERS: Record<string, string> = { "Content-Type": "application/json" };

/** Builds a 2xx JSON response using the shared envelope shape. */
export function jsonResponse<T>(
  data: T,
  opts: { status?: number; requestId: string; extraHeaders?: Record<string, string> },
): Response {
  const body: ResponseEnvelope<T> = { data, error: null, request_id: opts.requestId };
  return new Response(JSON.stringify(body), {
    status: opts.status ?? 200,
    headers: { ...JSON_HEADERS, "x-request-id": opts.requestId, ...(opts.extraHeaders ?? {}) },
  });
}

/** Builds an error JSON response using the shared envelope shape. */
export function errorResponse(
  err: AppError,
  requestId: string,
  extraHeaders?: Record<string, string>,
): Response {
  const body: ResponseEnvelope<never> = {
    data: null,
    error: {
      category: err.category,
      message: err.message,
      ...(err.details ? { details: err.details } : {}),
    },
    request_id: requestId,
  };
  return new Response(JSON.stringify(body), {
    status: err.status,
    headers: {
      ...JSON_HEADERS,
      "x-request-id": requestId,
      ...(err.retryAfterSeconds === undefined
        ? {}
        : { "Retry-After": String(err.retryAfterSeconds) }),
      ...(extraHeaders ?? {}),
    },
  });
}
