# ADR 0032 — Kyra Responses API and private reasoning replay

Date: 2026-10-08
Status: Accepted; deployed as Kyra v14

## Decision

The live adapter uses OpenAI Responses, with low reasoning effort for Luna and
medium for Terra/Sol, the existing tier/model mapping, and the same Astra-shaped
provider protocol. Function definitions explicitly use non-strict schemas; final
responses still undergo Astra schema parsing, repair and guardrails. Requests set
store=false and request encrypted reasoning content.

Within a server request, encrypted reasoning items are replayed alongside their
function calls. The private adapter cache is scoped by owner, request and model,
expires after five minutes, holds at most 128 request entries, and rejects more
than 64 calls or 512 KB of replay data per entry. It is never persisted in user
messages, returned to the app, or logged. Cross-model escalation replays the
portable tool history rather than another model's encrypted reasoning. Same-model
schema repairs retain the replay cache. Future streaming remains unfinished.

## Evidence

The old Chat Completions request failed live with HTTP 400 identifying
reasoning_effort. Official guidance recommends Responses for reasoning and tools:
https://developers.openai.com/api/docs/guides/reasoning
https://developers.openai.com/api/docs/guides/function-calling

135 Kyra tests passed, including actual Responses-shaped fixtures, tool-result
mapping, request privacy flags, encrypted reasoning replay and peer isolation.
A deployed authenticated guest conversation returned a nonempty styling response
without fallback and saved user/assistant messages. Client reads/preparation of
private approvals returned 403. The disposable user and conversation were removed
and verified absent. Full hosted multi-tool/preview/concurrency and real-device
acceptance remain open; one conversation does not establish full Kyra acceptance.
