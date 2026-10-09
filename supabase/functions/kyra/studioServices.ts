import type { SupabaseClient } from "@supabase/supabase-js";
import type { EdgeEnv } from "../_shared/supabaseClient.ts";
import { AppError, serverError } from "../_shared/errors.ts";
import { isUUID } from "../_shared/validation.ts";
import { CURRENT_STUDIO_CONSENT_TERMS_VERSION } from "../studio/schema.ts";
import { buildStudioReferenceReads, resolveConsentedStudioReference } from "./studioReferences.ts";
import { studioRequestBody } from "./studioRequest.ts";
import type { GenerateStudioPreviewDeps } from "./tools/generateStudioPreview.ts";
import { studioSelectionKey } from "./tools/generateStudioPreview.ts";
import type { SavedStudioConfirmation } from "./studioConfirmations.ts";
import type { PendingStudioConfirmation } from "./tools/studioConfirmation.ts";

/** Explicit generation commands use the persisted user-message UUID. Replies
 * approving a saved proposal reuse its confirmation UUID across turns, so
 * concurrent/retried approvals cannot consume a second generation.
 */
export function buildStudioPreviewServices(
  env: EdgeEnv,
  authorization: string,
  supabase: SupabaseClient,
  turn: {
    userID: string;
    messageID: string;
    userText: string;
    pending: PendingStudioConfirmation | null;
    confirmedProposal?: SavedStudioConfirmation | null;
  },
  fetcher: typeof fetch = fetch,
): GenerateStudioPreviewDeps {
  if (!isUUID(turn.userID) || !isUUID(turn.messageID)) {
    throw serverError("Invalid Studio request identity.");
  }
  return {
    userText: turn.userText,
    pending: turn.pending,
    currentConsentTermsVersion: CURRENT_STUDIO_CONSENT_TERMS_VERSION,
    resolveOwnedConsentedReference: (id) =>
      resolveConsentedStudioReference(
        turn.userID,
        id,
        CURRENT_STUDIO_CONSENT_TERMS_VERSION,
        buildStudioReferenceReads(supabase, turn.userID),
      ),
    async enqueue(selection, reference) {
      const proposal = turn.confirmedProposal;
      if (
        proposal &&
        (!Number.isFinite(Date.parse(proposal.expiresAt)) ||
          Date.parse(proposal.expiresAt) <= Date.now() ||
          proposal.selectionKey !== studioSelectionKey(selection))
      ) {
        throw new AppError(
          "validation",
          409,
          "This preview confirmation expired or changed. Ask for a new preview.",
        );
      }
      const body = studioRequestBody(selection, reference);
      const response = await fetcher(`${env.supabaseUrl}/functions/v1/studio/generate`, {
        method: "POST",
        headers: {
          Authorization: authorization,
          apikey: env.supabaseAnonKey,
          "Content-Type": "application/json",
          "Idempotency-Key": proposal?.id ?? turn.messageID,
          ...(proposal ? { "X-Astra-Studio-Confirmation": proposal.id } : {}),
        },
        body: JSON.stringify({ body }),
        signal: AbortSignal.timeout(20_000),
      });
      if ([400, 401, 403, 409, 429].includes(response.status)) {
        throw new AppError(
          response.status === 429 ? "rate_limited" : "validation",
          response.status,
          response.status === 429
            ? "Your Studio allowance is used. Open Studio to review your plan."
            : response.status === 409
            ? "This chat turn already requested a different preview, or its preview was removed. Confirm a new preview in a new message."
            : "Studio could not accept this preview. Check the selected outfit and photo in Studio.",
        );
      }
      if (!response.ok) throw serverError("Studio is unavailable. Please try again.");
      const payload = await response.json();
      const row = payload.data;
      if (
        !row || !isUUID(row.id) || row.user_id !== turn.userID ||
        !["queued", "generating", "complete", "failed"].includes(row.status)
      ) {
        throw serverError("Studio returned an invalid preview response.");
      }
      // This estimate is explicitly approximate, never a provider completion SLA.
      return {
        generationId: row.id,
        status: row.status,
        estimatedSeconds: row.status === "queued" || row.status === "generating" ? 120 : 0,
      };
    },
  };
}
