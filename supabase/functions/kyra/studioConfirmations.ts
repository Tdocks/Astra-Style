import type { SupabaseClient } from "@supabase/supabase-js";
import { serverError } from "../_shared/errors.ts";
import { isUUID } from "../_shared/validation.ts";
import {
  parseStudioPreview,
  type StudioPreviewSelection,
  studioSelectionKey,
} from "./tools/generateStudioPreview.ts";

export interface SavedStudioConfirmation {
  id: string;
  promptMessageID: string;
  selection: StudioPreviewSelection;
  selectionKey: string;
  expiresAt: string;
}

/** Hydrate only server-owned records; model/client message metadata is never
 * an authorization source. Matching the last saved assistant prompt prevents
 * a later unrelated affirmative from approving an earlier proposal.
 */
export function activeStudioConfirmation(
  row: Record<string, unknown> | null,
  userID: string,
  threadID: string,
  lastAssistantMessageID: string | null,
  now = Date.now(),
): SavedStudioConfirmation | null {
  if (
    !row || row.user_id !== userID || row.thread_id !== threadID ||
    row.closed_at !== null || !isUUID(row.id) || !isUUID(row.prompt_message_id) ||
    row.prompt_message_id !== lastAssistantMessageID || typeof row.expires_at !== "string" ||
    !Number.isFinite(Date.parse(row.expires_at)) || Date.parse(row.expires_at) <= now
  ) return null;
  const stored = row.selection;
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) return null;
  const value = stored as Record<string, unknown>;
  const selection = parseStudioPreview({
    outfit_id: value.outfitId,
    item_ids: value.itemIds,
    reference_image_id: value.referenceImageId,
    pose: value.pose,
    background: value.background,
    resolution: value.resolution,
  });
  if (!selection || studioSelectionKey(selection) !== row.selection_key) return null;
  return {
    id: row.id,
    promptMessageID: row.prompt_message_id,
    selection,
    selectionKey: row.selection_key,
    expiresAt: row.expires_at,
  };
}

/** The injected client must be service-role scoped and stay exclusively inside
 * the Edge Function. All operations still explicitly constrain owner and thread.
 */
export function buildStudioConfirmationStore(client: SupabaseClient) {
  return {
    async pending(userID: string, threadID: string, lastAssistantMessageID: string | null) {
      const { data, error } = await client.from("kyra_studio_confirmations")
        .select("*").eq("user_id", userID).eq("thread_id", threadID)
        .is("closed_at", null).maybeSingle();
      if (error) throw serverError("Couldn't verify your preview confirmation.");
      return activeStudioConfirmation(data, userID, threadID, lastAssistantMessageID);
    },
    async prepare(
      userID: string,
      threadID: string,
      promptMessageID: string,
      selection: StudioPreviewSelection,
    ) {
      const { data, error } = await client.rpc("prepare_kyra_studio_confirmation", {
        p_user_id: userID,
        p_thread_id: threadID,
        p_prompt_message_id: promptMessageID,
        p_selection: selection,
        p_selection_key: studioSelectionKey(selection),
      });
      if (error) throw serverError("Couldn't save your preview confirmation.");
      const saved = activeStudioConfirmation(data?.[0] ?? null, userID, threadID, promptMessageID);
      if (!saved) throw serverError("Couldn't save your preview confirmation.");
      return saved;
    },
    async close(userID: string, threadID: string, confirmationID: string) {
      const { error } = await client.from("kyra_studio_confirmations")
        .update({ closed_at: new Date().toISOString() }).eq("user_id", userID)
        .eq("thread_id", threadID).eq("id", confirmationID).is("closed_at", null);
      if (error) throw serverError("Couldn't close your preview confirmation.");
    },
  };
}
