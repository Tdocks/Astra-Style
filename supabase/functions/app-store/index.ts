import { createClient } from "@supabase/supabase-js";
import { appStoreSignedDataVerifier } from "../_shared/appStoreVerifier.ts";
import { serverError } from "../_shared/errors.ts";
import { readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRouter } from "../_shared/routing.ts";
import { createRateLimiter } from "../_shared/rateLimit.ts";
import { createAppStoreWebhookRoute } from "./route.ts";
import type { PendingWebhookState } from "./handler.ts";
import { mapStoredRow, type SubscriptionRow } from "../subscriptions/handler.ts";

const env = readEdgeEnv();
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!serviceRoleKey) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not configured.");
const serviceRoleClient = createClient(env.supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const inboundRateLimiter = createRateLimiter({ limit: 1200, windowMs: 60_000 });
const verifiedBundleRateLimiter = createRateLimiter({ limit: 600, windowMs: 60_000 });

async function fetchByOriginalTransactionId(
  originalTransactionId: string,
): Promise<SubscriptionRow | null> {
  const { data, error } = await serviceRoleClient.from("subscriptions")
    .select("*")
    .eq("app_store_original_transaction_id", originalTransactionId)
    .maybeSingle();
  if (error) throw serverError("Couldn't read subscription state.");
  return data ? mapStoredRow(data as Record<string, unknown>) : null;
}

const store = {
  async hasProcessedNotificationUUID(notificationUUID: string): Promise<boolean> {
    const [subscription, pending] = await Promise.all([
      serviceRoleClient.from("subscriptions").select("user_id")
        .eq("app_store_last_notification_uuid", notificationUUID).limit(1).maybeSingle(),
      serviceRoleClient.from("pending_app_store_notifications").select("notification_uuid")
        .eq("notification_uuid", notificationUUID).limit(1).maybeSingle(),
    ]);
    if (subscription.error || pending.error) {
      throw serverError("Couldn't check App Store notification idempotency.");
    }
    return subscription.data !== null || pending.data !== null;
  },
  fetchByOriginalTransactionId,
  async updateForOriginalTransactionId(
    state: PendingWebhookState,
  ): Promise<SubscriptionRow | null> {
    const { data, error } = await serviceRoleClient.from("subscriptions")
      .update({
        product_id: state.productId,
        status: state.status,
        expires_at: state.expiresAt,
        environment: state.environment,
        app_store_last_signed_at: state.signedAt,
        app_store_last_notification_uuid: state.notificationUUID,
        updated_at: new Date().toISOString(),
      })
      .eq("app_store_original_transaction_id", state.originalTransactionId)
      .lt("app_store_last_signed_at", state.signedAt)
      .select("*")
      .maybeSingle();
    if (error) throw serverError("Couldn't update subscription state.");
    return data
      ? mapStoredRow(data as Record<string, unknown>)
      : await fetchByOriginalTransactionId(state.originalTransactionId);
  },
  async upsertPending(state: PendingWebhookState): Promise<void> {
    const { error } = await serviceRoleClient.from("pending_app_store_notifications")
      .upsert({
        app_store_original_transaction_id: state.originalTransactionId,
        notification_uuid: state.notificationUUID,
        product_id: state.productId,
        status: state.status,
        expires_at: state.expiresAt,
        environment: state.environment,
        signed_at: state.signedAt,
      }, { onConflict: "app_store_original_transaction_id" });
    if (error) throw serverError("Couldn't queue verified App Store state.");
  },
  async deletePending(originalTransactionId: string): Promise<void> {
    const { error } = await serviceRoleClient.from("pending_app_store_notifications")
      .delete()
      .eq("app_store_original_transaction_id", originalTransactionId);
    if (error) throw serverError("Couldn't clear pending App Store state.");
  },
  async deleteExpiredPending(before: string): Promise<void> {
    const { error } = await serviceRoleClient.from("pending_app_store_notifications")
      .delete()
      .lt("created_at", before);
    if (error) throw serverError("Couldn't clean expired App Store state.");
  },
};

const webhookRoute = createAppStoreWebhookRoute({
  store,
  verifier: appStoreSignedDataVerifier,
  inboundRateLimiter,
  verifiedBundleRateLimiter,
  now: () => new Date(),
});

Deno.serve(createRouter("app-store", [
  { method: "POST", pattern: "/webhook", handler: webhookRoute },
]));
