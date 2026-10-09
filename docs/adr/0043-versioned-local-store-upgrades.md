# ADR 0043 — Versioned local stores with historical upgrade coverage

Status: Accepted (2026-10-09)

## Decision

Use explicit SwiftData VersionedSchema revisions and a lightweight migration plan.
V1 contains closet items, outfits, daily briefs, and offline mutations; V2 adds
pending scans; V3 adds the scanner-save recovery journal. Historical entity
property declarations were checked against their introducing commits and remain
unchanged. These revisions add entities without replacing existing rows.

The production container accepts an optional store URL for isolated on-disk
acceptance fixtures. Production startup still reports an opening failure and
allows explicit retry; it never deletes a store or substitutes a preview store.

## Domain mapping

Persistent reference models remain separate from domain value models.
PersistenceMapping.swift converts closet, outfit, and brief rows; queue and scanner
journals preserve their owner-bearing serialized payloads. Repository adapters
remain responsible for synchronization with Supabase rather than schema migration.

## Evidence and limits

A signed simulator test created each historical unversioned four-, five-, and
six-entity store, seeded its entity rows and payload/date fields, opened it through
the production V3 factory, and verified preservation after another reopen.
A second on-disk test verified mixed-entity queue payloads, FIFO order, durable
retry counts, and clearing after successful replay. Both passed in
/tmp/astra-historical-store-disk-tests.log on 2026-10-09.

These fixtures establish compatibility with the verified historical declarations.
They do not establish compatibility with arbitrary corrupted stores or unknown
future property changes. Future revisions must preserve historical declarations,
add an explicit migration stage, and extend fixture coverage before shipping.
