// Reconcile a server-verified StoreKit transaction and the latest verified
// notification state for its original transaction lineage.

import { badRequest, notFound, serverError } from "../_shared/errors.ts";
import {
  AppStoreConfigurationError,
  type AppStoreSignedDataVerifier,
  AppStoreVerificationError,
  type VerifiedTransaction,
} from "../_shared/appStoreVerifier.ts";
import { requireIso8601Seconds, toIso8601Seconds } from "../_shared/time.ts";
import {
  parseSyncBody,
  PREMIUM_PRODUCT_IDS,
  type SubscriptionDTO,
  type SyncBody,
} from "./schema.ts";

export interface SubscriptionRow {
  readonly user_id: string;
  readonly app_store_original_transaction_id: string;
  readonly product_id: string;
  readonly status: string;
  readonly expires_at: string | null;
  readonly environment: string;
  readonly app_store_last_signed_at: string;
  readonly app_store_last_notification_uuid?: string | null;
}

export interface PendingAppStoreState {
  readonly originalTransactionId: string;
  readonly notificationUUID: string;
  readonly productId: string;
  readonly status: string;
  readonly expiresAt: string | null;
  readonly environment: string;
  readonly signedAt: string;
}

export interface SubscriptionStore {
  upsertForUser(row: {
    readonly userId: string;
    readonly originalTransactionId: string;
    readonly productId: string;
    readonly status: string;
    readonly expiresAt: string;
    readonly environment: string;
    readonly signedAt: string;
  }): Promise<SubscriptionRow>;
  fetchForUser(userId: string): Promise<SubscriptionRow | null>;
  fetchByOriginalTransactionId(originalTransactionId: string): Promise<SubscriptionRow | null>;
  fetchPending(originalTransactionId: string): Promise<PendingAppStoreState | null>;
  removePending(originalTransactionId: string): Promise<void>;
}

export interface SyncDependencies {
  readonly store: SubscriptionStore;
  readonly verifier: AppStoreSignedDataVerifier;
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
    if (!existing) throw notFound("No subscription to restore.");
    return toDTO(existing, deps.now());
  }

  let transaction: VerifiedTransaction;
  try {
    transaction = await deps.verifier.verifyTransaction(body.signedTransactionInfo);
  } catch (error) {
    if (error instanceof AppStoreConfigurationError) {
      throw serverError("Apple purchase verification isn't configured yet.");
    }
    if (error instanceof AppStoreVerificationError && error.retryable) {
      throw serverError("Apple purchase verification is temporarily unavailable.");
    }
    throw badRequest(
      "Apple couldn't verify that purchase. Please restore purchases and try again.",
    );
  }

  const originalTransactionId = requiredVerifiedString(transaction.originalTransactionId);
  const productId = requiredVerifiedString(transaction.productId);
  const expiresAt = millisecondsToISO(transaction.expiresDate);
  const signedAt = millisecondsToISO(transaction.signedDate);
  const transactionID = requiredVerifiedString(transaction.transactionId);
  void transactionID;
  const existingLineage = await deps.store.fetchByOriginalTransactionId(originalTransactionId);
  if (transaction.appAccountToken) {
    if (transaction.appAccountToken.toLowerCase() !== userID.toLowerCase()) {
      throw badRequest("This App Store purchase is linked to a different Astra Style account.");
    }
  } else if (existingLineage?.user_id !== userID) {
    throw badRequest(
      "This older App Store purchase must already be linked to your Astra Style account before it can be restored.",
    );
  }
  if (!PREMIUM_PRODUCT_IDS.includes(productId as typeof PREMIUM_PRODUCT_IDS[number])) {
    throw badRequest("That App Store product isn't an Astra Style subscription.");
  }
  if (!expiresAt || !signedAt) {
    throw badRequest("Apple's transaction is missing its subscription dates.");
  }
  let state = transactionState(transaction, expiresAt, deps.now());

  const pending = await deps.store.fetchPending(originalTransactionId);
  const newerPending = pending !== null && new Date(pending.signedAt) > new Date(signedAt);
  if (pending && newerPending) {
    state = {
      productId: pending.productId,
      status: pending.status,
      expiresAt: pending.expiresAt ?? expiresAt,
      environment: pending.environment,
      signedAt: pending.signedAt,
    };
  }

  // StoreKit may return the same expired paid-period transaction after an
  // App Store server notification has already established a verified grace
  // deadline. A newer `signedDate` on that same transaction does not extend
  // its paid period, so retain the authoritative grace state until its
  // verified deadline. A newer pending notification, a new transaction
  // period, or an explicit transaction revocation still takes precedence.
  const existingGraceExpiry = existingLineage?.status === "in_grace_period"
    ? millisecondsToISO(Date.parse(existingLineage.expires_at ?? ""))
    : null;
  if (
    !newerPending &&
    transaction.revocationDate === undefined &&
    transaction.isUpgraded !== true &&
    state.status === "expired" &&
    existingGraceExpiry &&
    new Date(existingGraceExpiry) > deps.now() &&
    new Date(expiresAt) <= new Date(existingGraceExpiry)
  ) {
    state = {
      ...state,
      status: "in_grace_period",
      expiresAt: existingGraceExpiry,
    };
  }

  const row = await deps.store.upsertForUser({
    userId: userID,
    originalTransactionId,
    productId: state.productId,
    status: state.status,
    expiresAt: state.expiresAt,
    environment: state.environment,
    signedAt: state.signedAt,
  });
  if (pending) await deps.store.removePending(originalTransactionId);
  return toDTO(row, deps.now());
}

export function mapStoredRow(data: Record<string, unknown>): SubscriptionRow {
  return {
    user_id: String(data["user_id"]),
    app_store_original_transaction_id: String(data["app_store_original_transaction_id"]),
    product_id: String(data["product_id"]),
    status: String(data["status"]),
    expires_at: toIso8601Seconds(data["expires_at"]),
    environment: String(data["environment"]),
    app_store_last_signed_at: toIso8601Seconds(data["app_store_last_signed_at"]) ??
      "1970-01-01T00:00:00Z",
    app_store_last_notification_uuid: typeof data["app_store_last_notification_uuid"] === "string"
      ? data["app_store_last_notification_uuid"]
      : null,
  };
}

export function toDTO(row: SubscriptionRow, now: Date): SubscriptionDTO {
  return {
    user_id: row.user_id,
    app_store_original_transaction_id: row.app_store_original_transaction_id,
    product_id: row.product_id,
    status: row.status,
    expires_at: row.expires_at ? requireIso8601Seconds(row.expires_at, now) : null,
    environment: row.environment,
  };
}

export function millisecondsToISO(value: number | undefined): string | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function normalizeEnvironment(value: string | undefined): "sandbox" | "production" {
  if (value === "Sandbox") return "sandbox";
  if (value === "Production") return "production";
  throw badRequest("Apple returned an unsupported subscription environment.");
}

export function transactionState(
  transaction: VerifiedTransaction,
  expiresAt: string,
  now: Date,
): { productId: string; status: string; expiresAt: string; environment: string; signedAt: string } {
  const productId = requiredVerifiedString(transaction.productId);
  const signedAt = millisecondsToISO(transaction.signedDate);
  if (!signedAt) throw badRequest("Apple's transaction is missing its signed date.");
  const status = transaction.revocationDate !== undefined
    ? "revoked"
    : transaction.isUpgraded === true
    ? "expired"
    : new Date(expiresAt) > now
    ? "active"
    : "expired";
  return {
    productId,
    status,
    expiresAt,
    environment: normalizeEnvironment(transaction.environment),
    signedAt,
  };
}

function requiredVerifiedString(value: string | undefined): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 128) {
    throw badRequest("Apple's signed transaction is incomplete.");
  }
  return value;
}
