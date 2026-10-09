# ADR 0036: Re-resolve Studio inspiration references in Kyra history

**Status:** Accepted  
**Date:** 2026-10-09

## Context

Kyra accepts a `studio_inspiration` attachment as a Studio generation UUID. The current request verifies ownership, completion, deletion/retention state, canonical storage path, and signed URL before sending the image to the provider. The image URL is short lived and is deliberately not persisted. The user message is persisted as text only, however, so reopening that thread loses the image context and later provider turns cannot inspect the prior image.

Kyra history is already bounded to the most recent 12 message rows per provider request. `model_metadata` is specifically reserved for operational metadata, not private prompts or image context. Personal data export returns whole `kyra_messages` rows, so the stored reference must not contain storage paths or signed URLs.

## Decision

Add a nullable `studio_generation_id` UUID column to `kyra_messages`, with a foreign key to `studio_generations(id) ON DELETE SET NULL`. Populate it only on the user message for a successfully owner-verified current Studio inspiration attachment. The value is an opaque reference, not a capability: every replay re-resolves it using the authenticated caller and current generation status, deletion and retention state, mode, canonical object path, and Storage existence checks. A UUID supplied or written without those checks grants no image access.

On each provider turn, inspect only the bounded recent history window and resolve at most the newest historical Studio inspiration reference. If the current request contains a verified Studio image, it takes precedence and no historical image is signed. Otherwise the historical image is attached to its original user message with a newly signed short-lived URL. The URL is passed only to the provider request and is not stored in message content, `structured_payload`, `model_metadata`, or exported attachment metadata.

If a historical reference has been deleted, expired, or cannot be resolved, retain the user’s original text and add explicit system context that the image is unavailable and Kyra must not claim to see or describe it. A current-turn reference that cannot be resolved continues to fail with not-found before creating or mutating a conversation.

## Consequences

- Reopened threads can retain useful visual context without storing image bytes or bearer URLs.
- A hard-deleted generation clears the foreign key; a soft-deleted or expired generation is rejected by the resolver on every replay.
- The bounded history query and one-image maximum bound signing work and provider image input.
- Exports may include the generation UUID as part of the user’s own message row, but never a storage path or signed URL. `model_metadata` remains metadata-only.
- If the referenced Studio result is no longer available, Kyra can continue from text while clearly treating the old image as unavailable.

## Alternatives considered

- Persisting a signed URL was rejected because it is a bearer credential with a short lifetime and would expose a private storage location in history and exports.
- Persisting a storage path was rejected because it creates a broader storage locator surface and requires more parsing and trust rules than the existing generation resolver.
- Requiring the native client to reattach the image on every turn was rejected because reopening a thread should restore its bounded conversation context without client-side re-upload or synthetic attachments.
