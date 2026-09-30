// ============================================================================
// subscriptions/schema.ts
// ============================================================================
// POST /subscriptions/sync accepts Apple's signed StoreKit 2 transaction.
// The handler verifies this JWS server-side and ignores client-supplied
// transaction metadata.
// ============================================================================

import { badRequest } from "../_shared/errors.ts";
import { isRecord, requireRecord } from "../_shared/validation.ts";

export const PREMIUM_PRODUCT_IDS = [
  "com.astrastyle.app.premium.monthly",
  "com.astrastyle.app.premium.annual",
] as const;

export type PremiumProductID = (typeof PREMIUM_PRODUCT_IDS)[number];

export interface SyncTransactionBody {
  readonly kind: "transaction";
  readonly signedTransactionInfo: string;
}

export interface SyncRestoreBody {
  readonly kind: "restore";
}

export type SyncBody = SyncTransactionBody | SyncRestoreBody;

export interface SubscriptionDTO {
  readonly user_id: string;
  readonly app_store_original_transaction_id: string;
  readonly product_id: string;
  readonly status: string;
  readonly expires_at: string | null;
  readonly environment: string;
}

export function parseEnvelope(raw: unknown): { requestId?: string; body: unknown } {
  if (!isRecord(raw)) {
    throw badRequest("Request body must be a JSON object.");
  }
  if (!("body" in raw)) {
    throw badRequest('Request envelope is missing the required "body" field.');
  }
  const requestId = typeof raw["request_id"] === "string" ? raw["request_id"] : undefined;
  return { requestId, body: raw["body"] };
}

export function parseSyncBody(rawBody: unknown): SyncBody {
  const record = requireRecord(rawBody, "body");
  if (record["restore"] === true) {
    return { kind: "restore" };
  }

  return {
    kind: "transaction",
    signedTransactionInfo: requireNonEmptyString(
      record["signed_transaction_info"],
      "body.signed_transaction_info",
      50_000,
    ),
  };
}

function requireNonEmptyString(value: unknown, field: string, maximumLength = 128): string {
  if (typeof value !== "string" || value.length === 0) {
    throw badRequest(`${field} must be a non-empty string.`);
  }
  if (value.length > maximumLength) {
    throw badRequest(`${field} must be at most ${maximumLength} characters.`);
  }
  return value;
}
