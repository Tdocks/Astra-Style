// ============================================================================
// subscriptions/handler.ts
// ============================================================================
// Persist a StoreKit-observed transaction so `fetchCurrentSubscription`
// (PostgREST, RLS) can uncap the closet. Writes go through the service-role
// store — authenticated INSERT is forbidden by RLS.
//
// Identity is the JWT. The body has no user_id.
// ============================================================================

import { notFound } from "../_shared/errors.ts";
import { requireIso8601Seconds, toIso8601Seconds } from "../_shared/time.ts";
import { parseSyncBody, type SubscriptionDTO, type SyncBody } from "./schema.ts";

export interface SubscriptionRow {
  readonly user_id: string;
  readonly app_store_original_transaction_id: string;
  readonly product_id: string;
  readonly status: string;
  readonly expires_at: string | null;
  readonly environment: string;
}

export interface SubscriptionStore {
  upsertForUser(row: {
    readonly userId: string;
    readonly originalTransactionId: string;
    readonly productId: string;
    readonly status: string;
    readonly expiresAt: string | null;
    readonly environment: string;
  }): Promise<SubscriptionRow>;
  fetchForUser(userId: string): Promise<SubscriptionRow | null>;
}

export interface SyncDependencies {
  readonly store: SubscriptionStore;
  readonly now: () => Date;
}

export async function handleSync(
  rawBody: unknown,
  userID: string,
  deps: SyncDependencies,
): Promise<SubscriptionDTO> {
  const body: SyncBody = parseSyncBody(rawBody);
  if (body.kind === "restore") {
    const existing = await deps.store.fetchForUser(userID);
    if (!existing) {
      throw notFound("No subscription to restore.");
    }
    return toDTO(existing, deps.now());
  }

  const expiresAt = body.expiresDate ? requireIso8601Seconds(body.expiresDate, deps.now()) : null;
  const row = await deps.store.upsertForUser({
    userId: userID,
    originalTransactionId: body.originalTransactionId,
    productId: body.productId,
    status: "active",
    expiresAt,
    environment: body.environment,
  });
  return toDTO(row, deps.now());
}

function toDTO(row: SubscriptionRow, now: Date): SubscriptionDTO {
  return {
    user_id: row.user_id,
    app_store_original_transaction_id: row.app_store_original_transaction_id,
    product_id: row.product_id,
    status: row.status,
    expires_at: row.expires_at ? requireIso8601Seconds(row.expires_at, now) : null,
    environment: row.environment,
  };
}

export function mapStoredRow(data: Record<string, unknown>): SubscriptionRow {
  return {
    user_id: String(data["user_id"]),
    app_store_original_transaction_id: String(data["app_store_original_transaction_id"]),
    product_id: String(data["product_id"]),
    status: String(data["status"]),
    expires_at: toIso8601Seconds(data["expires_at"]),
    environment: String(data["environment"]),
  };
}
