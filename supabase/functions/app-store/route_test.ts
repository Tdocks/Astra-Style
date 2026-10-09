import { assertEquals } from "@std/assert";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import type { AppStoreSignedDataVerifier } from "../_shared/appStoreVerifier.ts";
import type { AppStoreWebhookStore } from "./handler.ts";
import { createAppStoreWebhookRoute } from "./route.ts";

const NOW = new Date("2026-10-09T12:00:00.000Z");

Deno.test("App Store webhook returns Retry-After on global overload without logging payload", async () => {
  const route = createAppStoreWebhookRoute({
    store: emptyStore(),
    verifier: verifierWithoutTransaction(),
    inboundRateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }),
    verifiedBundleRateLimiter: createRateLimiter({ limit: 10, windowMs: 60_000 }),
    now: () => NOW,
  });
  const lines: string[] = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (line: unknown) => lines.push(String(line));
  console.error = (line: unknown) => lines.push(String(line));
  try {
    const payload = "private-signed-payload-marker";
    const first = await route(webhookRequest(payload, "webhook-1"));
    const second = await route(webhookRequest("another-payload", "webhook-2"));
    assertEquals(first.status, 200);
    assertEquals(second.status, 429);
    assertEquals(second.headers.get("Retry-After"), "60");
    assertEquals(second.headers.get("x-request-id"), "webhook-2");
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
  assertEquals(lines.every((line) => !line.includes("private-signed-payload-marker")), true);
  const completed = JSON.parse(lines.find((line) => line.includes("app_store_webhook.completed"))!);
  assertEquals(completed.request_id, "webhook-1");
  assertEquals(completed.latency_ms, 0);
  const rejected = JSON.parse(
    lines.find((line) => line.includes("app_store_webhook.rate_limited"))!,
  );
  assertEquals(rejected.request_id, "webhook-2");
  assertEquals(rejected.retry_after_seconds, 60);
});

Deno.test("verified duplicate notifications are acknowledged despite bundle throttling", async () => {
  const store = emptyStore();
  let alreadyProcessed = false;
  store.hasProcessedNotificationUUID = () => Promise.resolve(alreadyProcessed);
  const route = createAppStoreWebhookRoute({
    store,
    verifier: {
      verifyNotification: () =>
        Promise.resolve({
          notificationUUID: "notification-1",
          signedDate: NOW.getTime(),
          data: { environment: "Sandbox", bundleId: "com.astrastyle.app" },
        }),
      verifyTransaction: () => Promise.reject(new Error("not used")),
      verifyRenewalInfo: () => Promise.resolve({}),
    },
    inboundRateLimiter: createRateLimiter({ limit: 10, windowMs: 60_000 }),
    verifiedBundleRateLimiter: createRateLimiter({ limit: 1, windowMs: 60_000 }),
    now: () => NOW,
  });

  const first = await route(webhookRequest("signed", "webhook-a"));
  assertEquals(first.status, 200);
  alreadyProcessed = true;
  const duplicate = await route(webhookRequest("signed", "webhook-b"));
  assertEquals(duplicate.status, 200);
  assertEquals((await duplicate.json()).result, "ignored");
});

function webhookRequest(payload: string, requestId: string): Request {
  return new Request("https://example.supabase.co/app-store/webhook", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Request-Id": requestId },
    body: JSON.stringify({ signedPayload: payload }),
  });
}

function verifierWithoutTransaction(): AppStoreSignedDataVerifier {
  return {
    verifyNotification: () =>
      Promise.resolve({
        notificationUUID: "notification-1",
        signedDate: NOW.getTime(),
        data: undefined,
      }),
    verifyTransaction: () => Promise.reject(new Error("not used")),
    verifyRenewalInfo: () => Promise.resolve({}),
  };
}

function emptyStore(): AppStoreWebhookStore {
  return {
    hasProcessedNotificationUUID: () => Promise.resolve(false),
    fetchByOriginalTransactionId: () => Promise.resolve(null),
    updateForOriginalTransactionId: () => Promise.resolve(null),
    upsertPending: () => Promise.resolve(),
    deletePending: () => Promise.resolve(),
    deleteExpiredPending: () => Promise.resolve(),
  };
}
