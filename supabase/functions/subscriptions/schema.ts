// ============================================================================
// subscriptions/schema.ts
// ============================================================================
// POST /subscriptions/sync — what the iOS client sends after a locally
// verified StoreKit 2 transaction (`AppStoreTransactionPayload`) or after
// Restore Purchases (`{ restore: true }`).
//
// THIS SLICE TRUSTS THE CLIENT PAYLOAD. Apple Server API verification and
// App Store Server Notifications V2 live on `app-store/webhook` and are
// not this file. The stub persists `original_transaction_id` so the closet
// cap can uncap against a server row. Spoofing is a real gap; gating
// inference-cost features on this row alone would be wrong. Wear This and
// paste-evaluate are not gated here.
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
  readonly originalTransactionId: string;
  readonly transactionId: string;
  readonly productId: PremiumProductID;
  readonly purchaseDate: string;
  readonly expiresDate: string | null;
  readonly environment: "sandbox" | "production";
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

  const originalTransactionId = requireNonEmptyString(
    record["original_transaction_id"],
    "body.original_transaction_id",
  );
  const transactionId = requireNonEmptyString(record["transaction_id"], "body.transaction_id");
  const productId = record["product_id"];
  if (productId !== PREMIUM_PRODUCT_IDS[0] && productId !== PREMIUM_PRODUCT_IDS[1]) {
    throw badRequest(
      "body.product_id must be com.astrastyle.app.premium.monthly or .annual.",
    );
  }
  const purchaseDate = requireNonEmptyString(record["purchase_date"], "body.purchase_date");
  const expiresRaw = record["expires_date"];
  let expiresDate: string | null = null;
  if (expiresRaw !== undefined && expiresRaw !== null) {
    expiresDate = requireNonEmptyString(expiresRaw, "body.expires_date");
  }
  const environment = record["environment"];
  if (environment !== "sandbox" && environment !== "production") {
    throw badRequest('body.environment must be "sandbox" or "production".');
  }

  return {
    kind: "transaction",
    originalTransactionId,
    transactionId,
    productId,
    purchaseDate,
    expiresDate,
    environment,
  };
}

function requireNonEmptyString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw badRequest(`${field} must be a non-empty string.`);
  }
  if (value.length > 128) {
    throw badRequest(`${field} must be at most 128 characters.`);
  }
  return value;
}
