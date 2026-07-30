// ============================================================================
// _shared/routing.ts
// ============================================================================
// Supabase routes `/functions/v1/{slug}/{rest}` to a deployed Edge Function
// by the FIRST path segment only — the function slug. Spec §14's endpoint
// paths, however, are slash-shaped (`POST /outfits/generate`,
// `GET /studio/status/:id`, ...), and the iOS client builds exactly those
// URLs (`AstraEndpoint.path`). Deploying one function per §14 endpoint would
// therefore require flattening the client's paths into hyphenated slugs,
// contradicting the spec's verbatim URL shapes. Instead (see
// docs/adr/0013-edge-function-routing.md), each first path segment is ONE
// deployed function — `outfits`, `profile`, `style-dna`, ... — and this
// helper is the single, shared way such a function dispatches on the path
// REMAINDER. Every grouped function should use it rather than hand-rolling
// its own pathname parsing; twelve slightly-different in-function routers
// would be twelve chances to disagree about trailing slashes, method
// mismatches, or the 404 envelope shape.
//
// Grouping also directly serves docs/11-risk-register.md §9b (Edge Function
// cold starts): 12 grouped functions mean 12 isolates instead of 16, and
// related endpoints (`outfits/generate` + `outfits/rank`) share a warm
// isolate instead of cold-starting independently.
//
// Path normalization — why the slug is stripped defensively rather than
// assumed: what `req.url`'s pathname looks like inside the function differs
// by environment. Deployed and `supabase functions serve` runtimes pass
// `/{slug}/{rest}` (the slug included, `/functions/v1` already stripped by
// the platform), but a gateway that forwards the full original path would
// pass `/functions/v1/{slug}/{rest}`, and a runtime that strips the slug
// itself would pass `/{rest}` alone. `resolveRoutePath` accepts all three,
// so the router never breaks because of where it happens to be mounted.
// ============================================================================

import { CORS_HEADERS, handleCorsPreflight } from "./cors.ts";
import { AppError, errorResponse, methodNotAllowed, notFound, serverError } from "./errors.ts";
import { resolveRequestId } from "./requestId.ts";

/**
 * Path parameters captured from `:name` pattern segments, e.g. matching
 * `/status/:id` against `/status/123` yields `{ id: "123" }`. Values are
 * URL-decoded but otherwise unvalidated — a route handler must validate
 * them (e.g. `isUUID` from `_shared/validation.ts`) exactly like any other
 * untrusted request input.
 */
export type RouteParams = Readonly<Record<string, string>>;

export interface Route {
  /** Uppercase HTTP method this route answers, e.g. "POST". */
  readonly method: string;
  /**
   * Path remainder AFTER the function slug, starting with "/", with `:name`
   * segments capturing parameters: "/generate", "/status/:id", or "/" for
   * an endpoint at the function root (spec §14's `DELETE /account`).
   */
  readonly pattern: string;
  readonly handler: (req: Request, params: RouteParams) => Promise<Response> | Response;
}

/**
 * Strips the deployment-environment prefix (`/functions/v1` and/or the
 * function's own slug) off `pathname`, returning the remainder the routes
 * are declared against. Always returns a "/"-prefixed path ("/" itself for
 * a request to the bare slug).
 */
export function resolveRoutePath(pathname: string, slug: string): string {
  const segments = pathname.split("/").filter((segment) => segment.length > 0);
  let index = 0;
  if (segments[index] === "functions" && segments[index + 1] === "v1") {
    index += 2;
  }
  if (segments[index] === slug) {
    index += 1;
  }
  return "/" + segments.slice(index).join("/");
}

interface RouteMatch {
  readonly route: Route;
  readonly params: RouteParams;
}

function matchPattern(pattern: string, path: string): RouteParams | null {
  const patternSegments = pattern.split("/").filter((segment) => segment.length > 0);
  const pathSegments = path.split("/").filter((segment) => segment.length > 0);
  if (patternSegments.length !== pathSegments.length) {
    return null;
  }
  const params: Record<string, string> = {};
  for (let i = 0; i < patternSegments.length; i++) {
    const patternSegment = patternSegments[i];
    const pathSegment = pathSegments[i];
    if (patternSegment === undefined || pathSegment === undefined) {
      return null;
    }
    if (patternSegment.startsWith(":")) {
      // Decode captured parameters so a handler sees the value the client
      // meant (e.g. an id that was percent-encoded in transit), matching
      // what a web framework would hand it. Literal segments are compared
      // encoded-vs-encoded on purpose: our patterns only ever use plain
      // ASCII segment names, so decoding buys nothing there and
      // `decodeURIComponent` throwing on malformed input (handled below)
      // should only ever be attributable to a parameter value.
      try {
        params[patternSegment.slice(1)] = decodeURIComponent(pathSegment);
      } catch {
        return null;
      }
    } else if (patternSegment !== pathSegment) {
      return null;
    }
  }
  return params;
}

/**
 * Builds the request handler a grouped Edge Function passes to
 * `Deno.serve`. Behavior, in order:
 *
 *  1. CORS preflight (`OPTIONS`) is answered 204 for ANY path, before route
 *     matching — a browser preflights the exact URL it is about to call,
 *     and answering only known paths would make CORS failures
 *     indistinguishable from routing failures in the browser console.
 *  2. A request matching a route's pattern AND method is dispatched to that
 *     route's handler.
 *  3. A request matching some route's pattern but no route's method gets
 *     405 (the path exists; the verb is wrong) rather than 404, so a client
 *     bug like GET-ing a POST endpoint produces the accurate error.
 *  4. Anything else gets 404 in the project's standard error envelope
 *     (`_shared/errors.ts`) — the same wire shape as every other error, so
 *     `AstraServerErrorPayload` decoding on iOS works unchanged.
 *
 * Both fallthrough responses carry the resolved request id (spec §14 "Log
 * request ID") and CORS headers, like every real handler's responses.
 */
export function createRouter(
  slug: string,
  routes: readonly Route[],
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    const preflight = handleCorsPreflight(req);
    if (preflight) {
      return preflight;
    }

    const requestId = resolveRequestId(req);

    let url: URL;
    try {
      url = new URL(req.url);
    } catch {
      // `req.url` inside Deno.serve is always absolute in practice; this
      // branch exists so a malformed URL from an unexpected runtime still
      // produces the standard envelope instead of an unhandled throw.
      return errorResponse(serverError("Could not parse request URL."), requestId, CORS_HEADERS);
    }

    const path = resolveRoutePath(url.pathname, slug);

    let match: RouteMatch | null = null;
    let sawPathMatch = false;
    for (const route of routes) {
      const params = matchPattern(route.pattern, path);
      if (params === null) {
        continue;
      }
      sawPathMatch = true;
      if (route.method.toUpperCase() === req.method.toUpperCase()) {
        match = { route, params };
        break;
      }
    }

    if (match === null) {
      const error = sawPathMatch
        ? methodNotAllowed(`${req.method} is not supported for this endpoint.`)
        : notFound("No such endpoint.");
      return errorResponse(error, requestId, CORS_HEADERS);
    }

    try {
      return await match.route.handler(req, match.params);
    } catch (err) {
      // Route handlers are expected to catch their own errors and build
      // their own envelopes (handler.ts owns logging, latency, etc.). This
      // is the last-resort net so a handler that throws anyway still
      // returns the standard envelope and never leaks a stack trace.
      const appError = err instanceof AppError ? err : serverError();
      return errorResponse(appError, requestId, CORS_HEADERS);
    }
  };
}
