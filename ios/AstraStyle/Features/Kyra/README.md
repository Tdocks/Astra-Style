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

## What is built (P5-KYRA-13/-14/-15, P5-TEST-02)

- `Views/KyraConversationView.swift` — the conversation screen: transcript, composer, spec §21's state set (loading/empty/offline/recoverable error with conditional retry), and the thinking indicator (the §3 breathing orb).
- `ViewModels/KyraConversationViewModel.swift` — send/retry/offline/action state. Offline is a stated "Kyra needs a connection" condition, never a silent queue — the client half of the P5-KYRA-18 decision recorded in `Core/Persistence/AstraModelContainer.swift`.
- `Services/KyraCardHydrator.swift` + `Models/KyraRenderedCard.swift` — id-reference cards joined to drawable rows; a failed fetch degrades to an honest `.unavailable` card, never a fabricated one.
- `Components/KyraCardView.swift` — the five card renderers (outfit reuses `LookSilhouetteView`/`AstraScoreMeter`, per P5-KYRA-14's component-reuse criterion). No `default:` branch: unknown card types are dropped at decode.
- `Components/KyraComposerView.swift` + `KyraAttachmentPickers.swift` — text, photo, product link, closet item, outfit inputs. **Voice is P5-KYRA-16 and not yet present** (needs the mic permission).
- `Components/KyraAskButton.swift` — the spec §4 global action, floated above the tab bar by `App/MainTabView.swift`.
- Memory proposals render as visible notes (the server has already persisted them); the inspect/delete surface is **P5-KYRA-17, still open**, as is `.memories`' placeholder in `Routing/KyraDestinationView.swift`.

## Tickets

Filled in by the **P5-KYRA** tickets in `docs/02-task-breakdown.md`.
Open here: **P5-KYRA-16** (voice input), **P5-KYRA-17** (memory inspector).
