import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { AppError } from "../_shared/errors.ts";
import { handleSync, type SubscriptionRow, type SubscriptionStore } from "./handler.ts";
import { parseEnvelope, parseSyncBody } from "./schema.ts";

Deno.test("parseEnvelope requires a body field", () => {
  assertThrows(() => parseEnvelope({}), AppError);
});

Deno.test("parseSyncBody accepts restore", () => {
  const body = parseSyncBody({ restore: true });
  assertEquals(body.kind, "restore");
});

Deno.test("parseSyncBody accepts a monthly sandbox transaction", () => {
  const body = parseSyncBody({
    original_transaction_id: "1000000123456789",
    transaction_id: "2000000123456789",
    product_id: "com.astrastyle.app.premium.monthly",
    purchase_date: "2026-08-22T21:00:00Z",
    expires_date: "2026-09-22T21:00:00Z",
    environment: "sandbox",
  });
  assertEquals(body.kind, "transaction");
  if (body.kind === "transaction") {
    assertEquals(body.productId, "com.astrastyle.app.premium.monthly");
    assertEquals(body.environment, "sandbox");
  }
});

Deno.test("parseSyncBody rejects an unknown product", () => {
  assertThrows(
    () =>
      parseSyncBody({
        original_transaction_id: "1",
        transaction_id: "2",
        product_id: "com.astrastyle.app.credits",
        purchase_date: "2026-08-22T21:00:00Z",
        environment: "sandbox",
      }),
    AppError,
  );
});

Deno.test("handleSync upserts an active row for the JWT user", async () => {
  const store = memoryStore();
  const dto = await handleSync(
    {
      original_transaction_id: "orig-1",
      transaction_id: "tx-1",
      product_id: "com.astrastyle.app.premium.annual",
      purchase_date: "2026-08-22T21:00:00Z",
      expires_date: "2027-08-22T21:00:00Z",
      environment: "sandbox",
    },
    "11111111-1111-1111-1111-111111111111",
    { store, now: () => new Date("2026-08-22T21:00:00Z") },
  );
  assertEquals(dto.status, "active");
  assertEquals(dto.user_id, "11111111-1111-1111-1111-111111111111");
  assertEquals(dto.product_id, "com.astrastyle.app.premium.annual");
  assertEquals(dto.app_store_original_transaction_id, "orig-1");
  assertEquals(dto.expires_at, "2027-08-22T21:00:00Z");
});

Deno.test("handleSync restore with no row is 404, not a fake free entitlement", async () => {
  await assertRejects(
    () =>
      handleSync({ restore: true }, "11111111-1111-1111-1111-111111111111", {
        store: memoryStore(),
        now: () => new Date("2026-08-22T21:00:00Z"),
      }),
    AppError,
  );
});

Deno.test("handleSync restore returns the stored row", async () => {
  const store = memoryStore();
  await handleSync(
    {
      original_transaction_id: "orig-2",
      transaction_id: "tx-2",
      product_id: "com.astrastyle.app.premium.monthly",
      purchase_date: "2026-08-22T21:00:00Z",
      expires_date: "2026-09-22T21:00:00Z",
      environment: "sandbox",
    },
    "22222222-2222-2222-2222-222222222222",
    { store, now: () => new Date("2026-08-22T21:00:00Z") },
  );
  const restored = await handleSync({ restore: true }, "22222222-2222-2222-2222-222222222222", {
    store,
    now: () => new Date("2026-08-22T21:00:00Z"),
  });
  assertEquals(restored.app_store_original_transaction_id, "orig-2");
});

function memoryStore(): SubscriptionStore {
  const rows = new Map<string, SubscriptionRow>();
  return {
    upsertForUser(row) {
      const stored: SubscriptionRow = {
        user_id: row.userId,
        app_store_original_transaction_id: row.originalTransactionId,
        product_id: row.productId,
        status: row.status,
        expires_at: row.expiresAt,
        environment: row.environment,
      };
      rows.set(row.userId, stored);
      return Promise.resolve(stored);
    },
    fetchForUser(userId) {
      return Promise.resolve(rows.get(userId) ?? null);
    },
  };
}
