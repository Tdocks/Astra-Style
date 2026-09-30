import { createClient } from "@supabase/supabase-js";
import { appStoreSignedDataVerifier } from "../_shared/appStoreVerifier.ts";
import { badRequest, errorResponse, serverError } from "../_shared/errors.ts";
import { readEdgeEnv } from "../_shared/supabaseClient.ts";
import { createRouter } from "../_shared/routing.ts";
import { resolveRequestId } from "../_shared/requestId.ts";
import { handleAppStoreWebhook, type PendingWebhookState } from "./handler.ts";
import { mapStoredRow, type SubscriptionRow } from "../subscriptions/handler.ts";

const env = readEdgeEnv();
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!serviceRoleKey) throw new Error("SUPABASE_SERVICE_ROLE_KEY is not configured.");
const serviceRoleClient = createClient(env.supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

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

async function webhookRoute(req: Request): Promise<Response> {
  const requestId = resolveRequestId(req);
  try {
    const raw = await req.text();
    if (raw.length > 100_000) throw badRequest("Apple notification is too large.");
    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      throw badRequest("Apple notification body must be valid JSON.");
    }
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw badRequest("Apple notification body must be an object.");
    }
    const signedPayload = (body as Record<string, unknown>)["signedPayload"];
    if (typeof signedPayload !== "string" || signedPayload.length > 80_000) {
      throw badRequest("Apple notification is missing its signed payload.");
    }

    const result = await handleAppStoreWebhook(signedPayload, {
      store,
      verifier: appStoreSignedDataVerifier,
      now: () => new Date(),
    });
    return Response.json({ received: true, result }, {
      status: 200,
      headers: { "x-request-id": requestId },
    });
  } catch (error) {
    if (typeof error === "object" && error !== null && "status" in error && "category" in error) {
      return errorResponse(error as Parameters<typeof errorResponse>[0], requestId);
    }
    return errorResponse(serverError(), requestId);
  }
}

Deno.serve(createRouter("app-store", [
  { method: "POST", pattern: "/webhook", handler: webhookRoute },
]));
