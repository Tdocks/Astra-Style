// ============================================================================
// products/urlValidation.ts
// ============================================================================
// `POST /products/extract` is the one endpoint in this codebase whose job
// is to make an Edge Function fetch a URL an authenticated-but-untrusted
// caller supplied. That is a textbook SSRF shape: without a check here, a
// caller could paste `http://169.254.169.254/latest/meta-data/` (the cloud
// metadata endpoint) or `http://localhost:...` and use this endpoint's
// server-side fetch as a proxy into infrastructure the client could never
// reach directly. No other function in `supabase/functions/` fetches a
// caller-supplied URL at all, which is why this check lives here and not in
// `_shared/` — see `_shared/validation.ts`'s header for the project's
// general request-validation helpers, none of which anticipate this.
//
// WHAT THIS DOES NOT DO, STATED PLAINLY. This is a hostname/IP-literal
// check performed BEFORE any DNS resolution happens. It blocks the obvious
// cases (an IP-literal private/loopback/link-local address, `localhost`,
// a bare `.local` name) but it cannot see through DNS rebinding — a
// hostname that resolves to a public IP at request-validation time and a
// private one at `fetch()`-time. Closing that gap needs a custom resolver
// that checks the IP `fetch()` is about to connect to, which Deno's global
// `fetch` does not expose a hook for. This is a real, documented gap, not
// a silent one: treat this as defense against casual/accidental misuse,
// not a hardened SSRF boundary.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";

const MAX_URL_LENGTH = 2048;

/** IPv4 octets that are loopback, private, link-local (incl. the cloud metadata address), or "this network". */
function isBlockedIPv4(hostname: string): boolean {
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(hostname);
  if (!match) return false;
  const a = Number(match[1]);
  const b = Number(match[2]);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return true; // Malformed octet — refuse rather than guess.
  if (a === 127) return true; // loopback
  if (a === 10) return true; // private
  if (a === 172 && b >= 16 && b <= 31) return true; // private
  if (a === 192 && b === 168) return true; // private
  if (a === 169 && b === 254) return true; // link-local, incl. 169.254.169.254 cloud metadata
  if (a === 0) return true; // "this network"
  return false;
}

function isBlockedIPv6(hostname: string): boolean {
  const normalized = hostname.replace(/^\[|\]$/g, "").toLowerCase();
  if (normalized === "::1") return true; // loopback
  if (normalized.startsWith("fe80:")) return true; // link-local
  if (normalized.startsWith("fc") || normalized.startsWith("fd")) return true; // unique local (fc00::/7)
  return false;
}

/**
 * Throws `badRequest` for anything that is not a plausible, safe-to-fetch
 * public http(s) product page URL. Returns nothing on success — callers
 * proceed to `canonicalizeUrl`/the provider only after this passes.
 */
export function assertSafeExternalUrl(rawUrl: string): void {
  if (rawUrl.length === 0) {
    throw badRequest("url must not be empty.");
  }
  if (rawUrl.length > MAX_URL_LENGTH) {
    throw badRequest(`url must be at most ${MAX_URL_LENGTH} characters.`);
  }

  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw badRequest("url must be a well-formed URL.");
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw badRequest("url must use http or https.");
  }

  const hostname = url.hostname.toLowerCase();
  if (hostname.length === 0) {
    throw badRequest("url must include a hostname.");
  }
  if (hostname === "localhost" || hostname.endsWith(".localhost") || hostname.endsWith(".local")) {
    throw badRequest("url must not point at a local hostname.");
  }
  if (isBlockedIPv4(hostname) || isBlockedIPv6(hostname)) {
    throw badRequest("url must not point at a private or link-local address.");
  }
  if (url.username || url.password) {
    // Embedded credentials have no legitimate reason to appear in a pasted
    // storefront link and are a classic SSRF/credential-leak vector.
    throw badRequest("url must not contain embedded credentials.");
  }
}
