# P5-KYRA-17 live memory acceptance — 2026-10-09

The existing Style Memories UI uses the authenticated caller's `style_memories` rows and filters `is_user_visible = true`. Its delete action issues a caller-scoped hard delete. This acceptance exercised those production data paths and Kyra's live context retrieval with a disposable anonymous user and synthetic text only.

The check inserted one visible preference and one internal-only memory. The visible-list query returned the visible row and excluded the internal row. A fresh Kyra conversation used the visible synthetic preference. After hard-deleting that row, a second fresh conversation did not repeat it; using a new thread excluded conversation history as an alternate source. No image, photo, or attachment was used.

The repeatable runner is [live_memory_acceptance.ts](../../supabase/functions/kyra/live_memory_acceptance.ts). It is explicitly opt-in and always requests normal account deletion, including when an assertion fails after signup.

The synthetic owner `786c6069-f7b7-421c-b3c2-c9b39f5f0178` was deleted through `DELETE /account`; deletion `a805f656-c82f-4a8c-bbf3-5bdc3f972fc0` completed with the owner ID cleared. Independent SQL readback found zero rows in `auth.users`, `profiles`, `style_memories`, `kyra_threads`, and `kyra_messages` for that owner.

Local verification: `deno test --import-map=deno.json kyra/` passed 148 tests; the runner passed `deno lint` and `deno check`. The two live responses confirmed the memory-present and memory-deleted behavior for this synthetic prompt; this is a focused acceptance, not a general guarantee of model wording for unrelated prompts.
