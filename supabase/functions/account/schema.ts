// ============================================================================
// account/schema.ts
// ============================================================================
// `DELETE /account` (spec §14/§15, ticket P7-PRIVACY-01) is the one endpoint
// in this project whose request body carries no field this handler ever
// reads. Every other `schema.ts` in `supabase/functions/` exists to parse
// and validate a payload the handler goes on to use; this one exists mainly
// to document, in code, that no such payload exists — "delete the caller's
// own account" has exactly one input (the JWT) and it is not something a
// request body could meaningfully parameterize. In particular there is no
// `user_id` field anywhere in this file, on purpose: the closest this
// project came to the account-deletion authorization bug the task
// description warns about would be a `body.user_id` this file quietly
// accepted and handler.ts quietly forgot to check. There is nothing to
// forget to check because there is nothing here to read.
// ============================================================================

import { isRecord } from "../_shared/validation.ts";

/**
 * The response body for a successful `DELETE /account` call.
 *
 * `status` is only ever "pending" or "processing" on the wire — never
 * "completed" or "failed" — because this endpoint answers synchronously
 * the moment `request_account_deletion()` (or, on a retried call, the
 * lookup of the already-in-flight row) returns, and that happens well
 * before the cascade in handler.ts's `runCascade` has had a chance to
 * finish. A client that wants to know whether deletion actually completed
 * has to poll `account_deletions` (RLS already grants the owning user
 * `select` on that table — see the migration) rather than read this
 * response as a completion signal. Modelling the full four-state enum here
 * would let a caller write `if (status === "completed")` against a value
 * this endpoint can never actually send, which is a worse API than one
 * that is honest about its own ceiling.
 */
export interface AccountDeletionStatusDTO {
  deletion_id: string;
  status: "pending" | "processing";
}

/**
 * Best-effort extraction of the client-minted `request_id` from the
 * envelope body (`AstraRequestEnvelope`'s `request_id` field), or
 * `undefined` if the body is empty, unparsable JSON, or not shaped like an
 * envelope.
 *
 * This is deliberately non-throwing, unlike every other endpoint's
 * `parseEnvelope`. Those endpoints have real payload fields, so a malformed
 * envelope is a genuine 400: something the client meant to send didn't
 * arrive intact, and silently proceeding would drop it. Here there is
 * nothing to drop — `_shared/requestId.ts` already falls back through
 * header -> body -> a freshly generated UUID, so returning `undefined`
 * degrades this call to exactly the same behavior as a client that sent an
 * empty body outright (which `AstraAPIClient.send(_:as:)` never does, but a
 * `curl` test or a future non-Swift caller might). Turning an account
 * deletion request into a confusing 400 over a body neither the client nor
 * the user would notice is a worse failure mode than ignoring it.
 */
export function tryExtractRequestId(rawBodyText: string): string | undefined {
  if (rawBodyText.trim().length === 0) {
    return undefined;
  }
  try {
    const parsed: unknown = JSON.parse(rawBodyText);
    if (isRecord(parsed) && typeof parsed["request_id"] === "string") {
      return parsed["request_id"];
    }
  } catch {
    // Unparsable JSON is treated the same as "no body" — see this
    // function's header comment.
  }
  return undefined;
}
