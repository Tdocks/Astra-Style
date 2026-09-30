import { assertEquals, assertRejects } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import type {
  AppStoreSignedDataVerifier,
  VerifiedNotification,
  VerifiedRenewalInfo,
  VerifiedTransaction,
} from "../_shared/appStoreVerifier.ts";
import type { SubscriptionRow } from "../subscriptions/handler.ts";
import {
  type AppStoreWebhookStore,
  handleAppStoreWebhook,
  type PendingWebhookState,
} from "./handler.ts";

const NOW = new Date("2026-09-30T12:00:00.000Z");

Deno.test("verified renewal updates the caller's matching subscription lineage", async () => {
  const store = memoryStore(true);
  const result = await handleAppStoreWebhook("notification-jws", {
    store,
    verifier: verifierFor(),
    now: () => NOW,
  });

  assertEquals(result, "updated");
  assertEquals(store.row?.status, "active");
  assertEquals(store.row?.product_id, "com.astrastyle.app.premium.annual");
  assertEquals(store.row?.app_store_last_signed_at, "2026-09-30T11:00:00.000Z");
  assertEquals(store.updated[0]?.notificationUUID, "notification-1");
});

Deno.test("a verified notification arriving before first sync is queued", async () => {
  const store = memoryStore(false);
  const result = await handleAppStoreWebhook("notification-jws", {
    store,
    verifier: verifierFor(),
    now: () => NOW,
  });

  assertEquals(result, "queued");
  assertEquals(store.pending[0]?.originalTransactionId, "original-1");
  assertEquals(store.pending[0]?.status, "active");
  assertEquals(store.deletedExpiredBefore, "2026-07-02T12:00:00.000Z");
});

Deno.test("a failed renewal inside its grace period preserves access", async () => {
  const store = memoryStore(true);
  const result = await handleAppStoreWebhook("notification-jws", {
    store,
    verifier: verifierFor({
      notification: { notificationType: "DID_FAIL_TO_RENEW" },
      renewal: { gracePeriodExpiresDate: Date.parse("2026-10-10T12:00:00.000Z") },
    }),
    now: () => NOW,
  });

  assertEquals(result, "updated");
  assertEquals(store.row?.status, "in_grace_period");
});

Deno.test("notification and transaction environments must match", async () => {
  await assertRejects(
    () =>
      handleAppStoreWebhook("notification-jws", {
        store: memoryStore(true),
        verifier: verifierFor({
          transaction: { environment: "Production" },
        }),
        now: () => NOW,
      }),
    AppError,
  );
});

Deno.test("notifications without subscription transaction data are ignored", async () => {
  const store = memoryStore(false);
  const result = await handleAppStoreWebhook("notification-jws", {
    store,
    verifier: verifierFor({ notification: { data: undefined } }),
    now: () => NOW,
  });

  assertEquals(result, "ignored");
  assertEquals(store.pending.length, 0);
});

function verifierFor(overrides: {
  notification?: Partial<VerifiedNotification>;
  transaction?: Partial<VerifiedTransaction>;
  renewal?: VerifiedRenewalInfo;
} = {}): AppStoreSignedDataVerifier {
  const notification: VerifiedNotification = {
    notificationUUID: "notification-1",
    notificationType: "DID_RENEW",
    signedDate: Date.parse("2026-09-30T11:00:00.000Z"),
    data: {
      environment: "Sandbox",
      signedTransactionInfo: "transaction-jws",
      signedRenewalInfo: "renewal-jws",
    },
    ...overrides.notification,
  };
  const transaction: VerifiedTransaction = {
    originalTransactionId: "original-1",
    transactionId: "transaction-1",
    productId: "com.astrastyle.app.premium.annual",
    expiresDate: Date.parse("2027-09-30T11:00:00.000Z"),
    environment: "Sandbox",
    ...overrides.transaction,
  };
  return {
    verifyNotification: () => Promise.resolve(notification),
    verifyTransaction: () => Promise.resolve(transaction),
    verifyRenewalInfo: () => Promise.resolve(overrides.renewal ?? {}),
  };
}

function memoryStore(hasSubscription: boolean): AppStoreWebhookStore & {
  row: SubscriptionRow | null;
  updated: PendingWebhookState[];
  pending: PendingWebhookState[];
  deletedExpiredBefore: string | null;
} {
  const store = {
    row: hasSubscription ? subscriptionRow() : null,
    updated: [] as PendingWebhookState[],
    pending: [] as PendingWebhookState[],
    deletedExpiredBefore: null as string | null,
    fetchByOriginalTransactionId(originalTransactionId: string) {
      return Promise.resolve(
        store.row?.app_store_original_transaction_id === originalTransactionId ? store.row : null,
      );
    },
    updateForOriginalTransactionId(state: PendingWebhookState) {
      store.updated.push(state);
      if (
        !store.row || store.row.app_store_original_transaction_id !== state.originalTransactionId
      ) {
        return Promise.resolve(null);
      }
      if (new Date(state.signedAt) <= new Date(store.row.app_store_last_signed_at)) {
        return Promise.resolve(store.row);
      }
      store.row = {
        ...store.row,
        product_id: state.productId,
        status: state.status,
        expires_at: state.expiresAt,
        environment: state.environment,
        app_store_last_signed_at: state.signedAt,
      };
      return Promise.resolve(store.row);
    },
    upsertPending(state: PendingWebhookState) {
      store.pending = store.pending.filter((item) =>
        item.originalTransactionId !== state.originalTransactionId
      );
      store.pending.push(state);
      return Promise.resolve();
    },
    deletePending(originalTransactionId: string) {
      store.pending = store.pending.filter((item) =>
        item.originalTransactionId !== originalTransactionId
      );
      return Promise.resolve();
    },
    deleteExpiredPending(before: string) {
      store.deletedExpiredBefore = before;
      return Promise.resolve();
    },
  };
  return store;
}

function subscriptionRow(): SubscriptionRow {
  return {
    user_id: "11111111-1111-1111-1111-111111111111",
    app_store_original_transaction_id: "original-1",
    product_id: "com.astrastyle.app.premium.annual",
    status: "active",
    expires_at: "2027-08-22T21:00:00.000Z",
    environment: "sandbox",
    app_store_last_signed_at: "2026-08-22T21:00:00.000Z",
  };
}
