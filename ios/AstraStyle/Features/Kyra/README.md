# Kyra

Owns the Kyra conversation UI: chat, structured response cards, and style-memory controls (spec §6.20).

## What this module owns

- Conversation UI supporting text, voice (transcribed on-device before sending), photo, product link, closet item, and outfit inputs.
- Suggested prompts and structured response rendering: outfit cards, product cards, closet items, comparison tables, and actions — Kyra never returns unparsed prose for these (spec §11's response schema).
- Style memory inspector: view and delete durable memories Kyra has saved, and confirm/reject memory proposals Kyra surfaces mid-conversation.
- The "Ask Kyra" global action's modal presentation (spec §4).

## Governing spec sections

§6.20 (screen spec), §11 (Kyra orchestration — context packet, tool calls, response schema, guardrails), §9 (`kyra_threads`, `kyra_messages`, `style_memories`), §14 (`POST /kyra/respond`), §18 (`kyra_prompt_sent` — never log the free-text prompt itself, only the `intent`), §20 (target: first token/card under 2.5s).

## What already exists to build against

- `Domain/Repositories/KyraRepository.swift` — send/fetch threads & messages/memories.
- `Domain/Models/KyraResponse.swift` — `KyraStructuredResponse`, the `KyraCard` enum (outfit/product/closetItem/comparisonTable/action) with custom `Codable` matching the server's `{"type": ...}` envelope, `KyraSuggestedAction`, `KyraMemoryProposal`.
- `Domain/Models/KyraOutgoingMessage.swift` — the attachment enum for the six input kinds.
- `Core/Mocks/MockKyraRepository.swift` — returns a fully-populated structured response (including an outfit card and suggested actions) so card rendering can be built without a live model.

## Tickets

Filled in by the **P5-KYRA** tickets in `docs/02-task-breakdown.md`.
