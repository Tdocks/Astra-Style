import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import type {
  AppStoreSignedDataVerifier,
  VerifiedTransaction,
} from "../_shared/appStoreVerifier.ts";
import {
  handleSync,
  type PendingAppStoreState,
  type SubscriptionRow,
  type SubscriptionStore,
} from "./handler.ts";
import { parseEnvelope, parseSyncBody } from "./schema.ts";

const USER_A = "11111111-1111-1111-1111-111111111111";
const USER_B = "22222222-2222-2222-2222-222222222222";

Deno.test("parseEnvelope requires a body field", () => {
  assertThrows(() => parseEnvelope({}), AppError);
});

Deno.test("parseSyncBody accepts a signed StoreKit transaction", () => {
  const body = parseSyncBody({ signed_transaction_info: "apple-signed-jws" });
  assertEquals(body.kind, "transaction");
  if (body.kind === "transaction") assertEquals(body.signedTransactionInfo, "apple-signed-jws");
});

Deno.test("parseSyncBody rejects a transaction without signed data", () => {
  assertThrows(() => parseSyncBody({ product_id: "com.astrastyle.app.premium.monthly" }), AppError);
});

Deno.test("handleSync persists the verified transaction for the JWT user", async () => {
  const store = memoryStore();
  const dto = await handleSync(
    { signed_transaction_info: "apple-signed-jws" },
    USER_A,
    {
      store,
      verifier: verifierFor(verifiedTransaction({ appAccountToken: USER_A })),
      now: () => new Date("2026-08-22T21:00:00Z"),
    },
  );
  assertEquals(dto.status, "active");
  assertEquals(dto.user_id, USER_A);
  assertEquals(dto.product_id, "com.astrastyle.app.premium.annual");
  assertEquals(dto.app_store_original_transaction_id, "orig-1");
  assertEquals(dto.expires_at, "2027-08-22T21:00:00Z");
});

Deno.test("sync keeps a live verified grace period for the same expired paid transaction", async () => {
  const store = memoryStore({
    user_id: USER_A,
    app_store_original_transaction_id: "orig-1",
    product_id: "com.astrastyle.app.premium.annual",
    status: "in_grace_period",
    expires_at: "2026-10-10T12:00:00.000Z",
    environment: "sandbox",
    app_store_last_signed_at: "2026-09-30T11:00:00.000Z",
  });
  const dto = await handleSync(
    { signed_transaction_info: "apple-signed-jws" },
    USER_A,
    {
      store,
      verifier: verifierFor(verifiedTransaction({
        appAccountToken: USER_A,
        expiresDate: Date.parse("2026-09-29T12:00:00.000Z"),
        signedDate: Date.parse("2026-10-01T09:00:00.000Z"),
      })),
      now: () => new Date("2026-10-01T10:00:00.000Z"),
    },
  );

  assertEquals(dto.status, "in_grace_period");
  assertEquals(dto.expires_at, "2026-10-10T12:00:00Z");
});

Deno.test("a verified new paid period replaces the existing grace state", async () => {
  const store = memoryStore({
    user_id: USER_A,
    app_store_original_transaction_id: "orig-1",
    product_id: "com.astrastyle.app.premium.annual",
    status: "in_grace_period",
    expires_at: "2026-10-10T12:00:00.000Z",
    environment: "sandbox",
    app_store_last_signed_at: "2026-09-30T11:00:00.000Z",
  });
  const dto = await handleSync(
    { signed_transaction_info: "apple-signed-jws" },
    USER_A,
    {
      store,
      verifier: verifierFor(verifiedTransaction({
        appAccountToken: USER_A,
        transactionId: "tx-renewed",
        expiresDate: Date.parse("2027-09-29T12:00:00.000Z"),
        signedDate: Date.parse("2026-10-01T09:00:00.000Z"),
      })),
      now: () => new Date("2026-10-01T10:00:00.000Z"),
    },
  );

  assertEquals(dto.status, "active");
  assertEquals(dto.expires_at, "2027-09-29T12:00:00Z");
});

Deno.test("a verified revocation overrides an existing grace period", async () => {
  const store = memoryStore({
    user_id: USER_A,
    app_store_original_transaction_id: "orig-1",
    product_id: "com.astrastyle.app.premium.annual",
    status: "in_grace_period",
    expires_at: "2026-10-10T12:00:00.000Z",
    environment: "sandbox",
    app_store_last_signed_at: "2026-09-30T11:00:00.000Z",
  });
  const dto = await handleSync(
    { signed_transaction_info: "apple-signed-jws" },
    USER_A,
    {
      store,
      verifier: verifierFor(verifiedTransaction({
        appAccountToken: USER_A,
        expiresDate: Date.parse("2026-09-29T12:00:00.000Z"),
        signedDate: Date.parse("2026-10-01T09:00:00.000Z"),
        revocationDate: Date.parse("2026-09-30T18:00:00.000Z"),
      })),
      now: () => new Date("2026-10-01T10:00:00.000Z"),
    },
  );

  assertEquals(dto.status, "revoked");
  assertEquals(dto.expires_at, "2026-09-29T12:00:00Z");
});

Deno.test("a newer verified revocation notification overrides existing grace", async () => {
  const store = memoryStore(
    {
      user_id: USER_A,
      app_store_original_transaction_id: "orig-1",
      product_id: "com.astrastyle.app.premium.annual",
      status: "in_grace_period",
      expires_at: "2026-10-10T12:00:00.000Z",
      environment: "sandbox",
      app_store_last_signed_at: "2026-09-30T11:00:00.000Z",
    },
    {
      originalTransactionId: "orig-1",
      notificationUUID: "revoke-1",
      productId: "com.astrastyle.app.premium.annual",
      status: "revoked",
      expiresAt: "2026-09-29T12:00:00.000Z",
      environment: "sandbox",
      signedAt: "2026-10-01T09:30:00.000Z",
    },
  );
  const dto = await handleSync(
    { signed_transaction_info: "apple-signed-jws" },
    USER_A,
    {
      store,
      verifier: verifierFor(verifiedTransaction({
        appAccountToken: USER_A,
        expiresDate: Date.parse("2026-09-29T12:00:00.000Z"),
        signedDate: Date.parse("2026-10-01T09:00:00.000Z"),
      })),
      now: () => new Date("2026-10-01T10:00:00.000Z"),
    },
  );

  assertEquals(dto.status, "revoked");
  assertEquals(dto.expires_at, "2026-09-29T12:00:00Z");
});

Deno.test("handleSync rejects a signed purchase bound to another Astra account", async () => {
  await assertRejects(
    () =>
      handleSync(
        { signed_transaction_info: "apple-signed-jws" },
        USER_B,
        {
          store: memoryStore(),
          verifier: verifierFor(verifiedTransaction({ appAccountToken: USER_A })),
          now: () => new Date("2026-08-22T21:00:00Z"),
        },
      ),
    AppError,
  );
});

Deno.test("handleSync rejects a verified product outside Astra Premium", async () => {
  await assertRejects(
    () =>
      handleSync(
        { signed_transaction_info: "apple-signed-jws" },
        USER_A,
        {
          store: memoryStore(),
          verifier: verifierFor(verifiedTransaction({
            productId: "com.astrastyle.app.credits",
            appAccountToken: USER_A,
          })),
          now: () => new Date("2026-08-22T21:00:00Z"),
        },
      ),
    AppError,
  );
});

Deno.test("restore with no row is 404, not a fake free entitlement", async () => {
  await assertRejects(
    () =>
      handleSync({ restore: true }, USER_A, {
        store: memoryStore(),
        verifier: verifierFor(verifiedTransaction({ appAccountToken: USER_A })),
        now: () => new Date("2026-08-22T21:00:00Z"),
      }),
    AppError,
  );
});

Deno.test("restore returns the stored row", async () => {
  const store = memoryStore();
  await handleSync(
    { signed_transaction_info: "apple-signed-jws" },
    USER_B,
    {
      store,
      verifier: verifierFor(verifiedTransaction({
        originalTransactionId: "orig-2",
        productId: "com.astrastyle.app.premium.monthly",
        transactionId: "tx-2",
        expiresDate: Date.parse("2026-09-22T21:00:00Z"),
        appAccountToken: USER_B,
      })),
      now: () => new Date("2026-08-22T21:00:00Z"),
    },
  );
  const restored = await handleSync({ restore: true }, USER_B, {
    store,
    verifier: verifierFor(verifiedTransaction({ appAccountToken: USER_B })),
    now: () => new Date("2026-08-22T21:00:00Z"),
  });
  assertEquals(restored.app_store_original_transaction_id, "orig-2");
});

function verifiedTransaction(overrides: Partial<VerifiedTransaction> = {}): VerifiedTransaction {
  return {
    originalTransactionId: "orig-1",
    transactionId: "tx-1",
    productId: "com.astrastyle.app.premium.annual",
    purchaseDate: Date.parse("2026-08-22T21:00:00Z"),
    expiresDate: Date.parse("2027-08-22T21:00:00Z"),
    signedDate: Date.parse("2026-08-22T21:00:00Z"),
    environment: "Sandbox",
    bundleId: "com.astrastyle.app",
    ...overrides,
  };
}

function verifierFor(transaction: VerifiedTransaction): AppStoreSignedDataVerifier {
  return {
    verifyTransaction: () => Promise.resolve(transaction),
    verifyRenewalInfo: () => Promise.resolve({}),
    verifyNotification: () => Promise.resolve({}),
  };
}

function memoryStore(
  initial?: SubscriptionRow,
  initialPending?: PendingAppStoreState,
): SubscriptionStore {
  const rows = new Map<string, SubscriptionRow>();
  if (initial) rows.set(initial.user_id, initial);
  const pending = new Map<string, PendingAppStoreState>();
  if (initialPending) pending.set(initialPending.originalTransactionId, initialPending);
  return {
    upsertForUser(row) {
      const stored: SubscriptionRow = {
        user_id: row.userId,
        app_store_original_transaction_id: row.originalTransactionId,
        product_id: row.productId,
        status: row.status,
        expires_at: row.expiresAt,
        environment: row.environment,
        app_store_last_signed_at: row.signedAt,
      };
      rows.set(row.userId, stored);
      return Promise.resolve(stored);
    },
    fetchForUser(userId) {
      return Promise.resolve(rows.get(userId) ?? null);
    },
    fetchByOriginalTransactionId(originalTransactionId) {
      return Promise.resolve(
        [...rows.values()].find((row) =>
          row.app_store_original_transaction_id === originalTransactionId
        ) ?? null,
      );
    },
    fetchPending(originalTransactionId) {
      return Promise.resolve(pending.get(originalTransactionId) ?? null);
    },
    removePending(originalTransactionId) {
      pending.delete(originalTransactionId);
      return Promise.resolve();
    },
  };
}
