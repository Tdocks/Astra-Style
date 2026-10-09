# ADR 0041: Durable startup and serialized offline replay

Status: Accepted
Date: 2026-10-09

## Context

A live persistence-open failure previously selected an in-memory preview store. Queued writes could appear accepted yet disappear after termination. Separately, queue actor reentrancy allowed independent repository drain closures to overlap while awaiting network writes. Reconnection triggered scanner recovery but did not proactively replay closet/outfit edits.

## Decision

Open the durable model container before constructing the live dependency graph. If opening fails, show an explicit recovery screen with retry, preserving store files and withholding the editable application. Preview storage remains for deliberate mock operation only. This is error recovery, not proof of historical store migration compatibility.

Serialize each shared queue's complete apply/remove loop with a cancellation-aware asynchronous gate. Waiting repository handlers execute in turn; foreign entity records remain queued without incrementing attempts. Validate the current owner against outfit, wear and feedback payloads before replay, and require an actual owner before offline enqueue.

Use a coordinator to replay closet then outfit mutations on online connectivity and restored/changed authenticated sessions. Revalidate the owner before starting and between repository drains; repository guards remain the final per-record authority. A cancelled waiter must not retain the queue gate or block later callers.

## Acceptance

Require regression evidence for overlapping handlers, cancellation, persistent-queue behavior, foreign-owner retention, no-owner enqueue rejection, connectivity/session triggers, and startup failure/retry. A mock UI startup retry does not establish recovery of a corrupted real store. Historical four/five/six-entity upgrade fixtures and real-device interrupted-write acceptance remain separate requirements.
