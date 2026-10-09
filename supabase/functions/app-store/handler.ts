import { AppError, badRequest, serverError } from "../_shared/errors.ts";
import type { RateLimiter } from "../_shared/rateLimit.ts";
import {
  AppStoreConfigurationError,
  type AppStoreSignedDataVerifier,
  AppStoreVerificationError,
  type VerifiedNotification,
  type VerifiedRenewalInfo,
  type VerifiedTransaction,
} from "../_shared/appStoreVerifier.ts";
import {
  millisecondsToISO,
  normalizeEnvironment,
  type SubscriptionRow,
} from "../subscriptions/handler.ts";
import { PREMIUM_PRODUCT_IDS } from "../subscriptions/schema.ts";

export interface AppStoreWebhookStore {
  hasProcessedNotificationUUID(notificationUUID: string): Promise<boolean>;
  fetchByOriginalTransactionId(originalTransactionId: string): Promise<SubscriptionRow | null>;
  updateForOriginalTransactionId(state: PendingWebhookState): Promise<SubscriptionRow | null>;
  upsertPending(state: PendingWebhookState): Promise<void>;
  deletePending(originalTransactionId: string): Promise<void>;
  deleteExpiredPending(before: string): Promise<void>;
}

export interface PendingWebhookState {
  readonly originalTransactionId: string;
  readonly notificationUUID: string;
  readonly productId: string;
  readonly status: string;
  readonly expiresAt: string | null;
  readonly environment: string;
  readonly signedAt: string;
}

export interface AppStoreWebhookDependencies {
  readonly store: AppStoreWebhookStore;
  readonly verifier: AppStoreSignedDataVerifier;
  readonly rateLimiter?: RateLimiter;
  readonly now: () => Date;
}

export async function handleAppStoreWebhook(
  signedPayload: string,
  deps: AppStoreWebhookDependencies,
): Promise<"updated" | "queued" | "ignored"> {
  let notification: VerifiedNotification;
  try {
    notification = await deps.verifier.verifyNotification(signedPayload);
  } catch (error) {
    throw verificationError(error, "Apple notification");
  }

  const notificationUUID = required(notification.notificationUUID);
  if (await deps.store.hasProcessedNotificationUUID(notificationUUID)) return "ignored";

  const appLimit = deps.rateLimiter?.check(
    notification.data?.bundleId ?? "unidentified-app",
    deps.now().getTime(),
  );
  if (appLimit && !appLimit.allowed) {
    throw new AppError(
      "rate_limited",
      429,
      "Too many App Store notifications. Please retry shortly.",
      appLimit.retryAfterSeconds,
    );
  }

  const notificationSignedAt = millisecondsToISO(notification.signedDate);
  if (!notificationSignedAt) throw badRequest("Apple notification is missing its signed date.");
  const signedTransactionInfo = notification.data?.signedTransactionInfo;
  if (!signedTransactionInfo) return "ignored";

  let transaction: VerifiedTransaction;
  try {
    transaction = await deps.verifier.verifyTransaction(signedTransactionInfo);
  } catch (error) {
    throw verificationError(error, "Apple transaction");
  }

  const originalTransactionId = required(transaction.originalTransactionId);
  const productId = required(transaction.productId);
  const expiresAt = millisecondsToISO(transaction.expiresDate);
  if (!expiresAt) throw badRequest("Apple subscription is missing its expiration date.");
  if (!PREMIUM_PRODUCT_IDS.includes(productId as typeof PREMIUM_PRODUCT_IDS[number])) {
    return "ignored";
  }
  const environment = normalizeEnvironment(transaction.environment);
  if (notification.data?.environment !== transaction.environment) {
    throw badRequest("Apple notification and transaction environments do not match.");
  }

  let renewalInfo: VerifiedRenewalInfo | undefined;
  const signedRenewalInfo = notification.data?.signedRenewalInfo;
  if (signedRenewalInfo) {
    try {
      renewalInfo = await deps.verifier.verifyRenewalInfo(signedRenewalInfo);
    } catch (error) {
      throw verificationError(error, "Apple renewal information");
    }
  }

  const state: PendingWebhookState = {
    originalTransactionId,
    notificationUUID,
    productId,
    status: subscriptionStatus(notification, transaction, renewalInfo, expiresAt, deps.now()),
    expiresAt,
    environment,
    signedAt: notificationSignedAt,
  };

  const row = await deps.store.fetchByOriginalTransactionId(originalTransactionId);
  if (row) {
    await deps.store.updateForOriginalTransactionId(state);
    return "updated";
  }

  // Apple may notify a renewal before the user next opens the app. Keep the
  // newest verified state so the first authenticated `/sync` cannot restore
  // an older StoreKit transaction as active.
  await deps.store.deleteExpiredPending(
    new Date(deps.now().getTime() - 90 * 24 * 60 * 60 * 1000).toISOString(),
  );
  await deps.store.upsertPending(state);
  const appearedDuringWrite = await deps.store.fetchByOriginalTransactionId(originalTransactionId);
  if (appearedDuringWrite) {
    await deps.store.updateForOriginalTransactionId(state);
    await deps.store.deletePending(originalTransactionId);
    return "updated";
  }
  return "queued";
}

function subscriptionStatus(
  notification: VerifiedNotification,
  transaction: VerifiedTransaction,
  renewalInfo: VerifiedRenewalInfo | undefined,
  expiresAt: string,
  now: Date,
): string {
  const type = notification.notificationType;
  if (type === "REFUND" || type === "REVOKE" || transaction.revocationDate !== undefined) {
    return type === "REFUND_REVERSED" && new Date(expiresAt) > now ? "active" : "revoked";
  }
  if (type === "REFUND_REVERSED") return new Date(expiresAt) > now ? "active" : "expired";
  if (type === "EXPIRED" || type === "GRACE_PERIOD_EXPIRED" || transaction.isUpgraded === true) {
    return "expired";
  }
  const gracePeriodExpiresAt = millisecondsToISO(renewalInfo?.gracePeriodExpiresDate);
  if (
    type === "DID_FAIL_TO_RENEW" && gracePeriodExpiresAt && new Date(gracePeriodExpiresAt) > now
  ) {
    return "in_grace_period";
  }
  if (type === "DID_FAIL_TO_RENEW" && new Date(expiresAt) <= now) {
    return "in_billing_retry";
  }
  return new Date(expiresAt) > now ? "active" : "expired";
}

function required(value: string | undefined): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 128) {
    throw badRequest("Apple's signed notification is incomplete.");
  }
  return value;
}

function verificationError(error: unknown, label: string): Error {
  if (error instanceof AppStoreConfigurationError) {
    return serverError("App Store notification verification isn't configured yet.");
  }
  if (error instanceof AppStoreVerificationError && error.retryable) {
    return serverError(`${label} verification is temporarily unavailable.`);
  }
  return badRequest(`${label} could not be verified.`);
}
