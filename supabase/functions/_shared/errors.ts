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
  | "rate_limited";

/** Thrown by any layer of a function to signal a specific, typed failure. */
export class AppError extends Error {
  readonly category: ErrorCategory;
  /** HTTP status code this error should be returned with. */
  readonly status: number;

  constructor(category: ErrorCategory, status: number, message: string) {
    super(message);
    this.name = "AppError";
    this.category = category;
    this.status = status;
  }
}

export function unauthorized(message = "Authentication required."): AppError {
  return new AppError("auth", 401, message);
}

export function badRequest(message: string): AppError {
  return new AppError("validation", 400, message);
}

export function rateLimited(message = "Too many requests. Please try again shortly."): AppError {
  return new AppError("rate_limited", 429, message);
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
  error: { category: ErrorCategory; message: string } | null;
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
    headers: { ...JSON_HEADERS, ...(opts.extraHeaders ?? {}) },
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
    error: { category: err.category, message: err.message },
    request_id: requestId,
  };
  return new Response(JSON.stringify(body), {
    status: err.status,
    headers: { ...JSON_HEADERS, ...(extraHeaders ?? {}) },
  });
}
