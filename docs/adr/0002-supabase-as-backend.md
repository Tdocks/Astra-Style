# 0002. Supabase as the backend platform

## Status

Accepted

## Context

Astra Style needs, at minimum: relational storage for wardrobe/outfit/profile data
with strong per-user isolation, object storage for garment and generated imagery,
authentication (Apple + email), vector storage for style/closet/outfit embeddings
(§9), and a place to run privileged server logic that talks to AI providers without
exposing provider keys to the client (§8, §25). §8 specifies Supabase Postgres,
Auth, Storage, Realtime, Edge Functions, and pgvector explicitly, with Row Level
Security mandatory on every user-owned table (§15).

The alternative shape is a bespoke backend (e.g. a Node/Go service on top of managed
Postgres, Auth0/Firebase Auth, S3, and a separate vector DB like Pinecone), assembled
from best-of-breed pieces.

## Decision

Use Supabase as the single backend platform: Postgres as the system of record,
Supabase Auth (Apple + email OTP/magic link) for identity, Supabase Storage for
private per-user object storage, pgvector for style/closet/outfit embeddings, and
Supabase Edge Functions (Deno) as the only place that holds provider credentials and
talks to AI/vision/image/weather/affiliate providers (§8, §25). RLS with
`user_id = auth.uid()` is mandatory on every user-owned table (§15).

## Consequences

### Positive

- One platform, one bill, one dashboard, one migration history — meaningfully less
  operational surface for a small team than assembling Postgres + Auth0 + S3 +
  Pinecone + a hand-rolled API server.
- RLS lets a large fraction of "is this my data" authorization live in the database
  itself rather than being re-implemented in every Edge Function and, later, in an
  admin tool — reduces the chance of an authorization bug shipping in application code.
- pgvector living in the same Postgres instance as the relational wardrobe data means
  a compatibility query can join structured filters (category, formality, laundry
  state) with a vector similarity search in one SQL statement, instead of
  round-tripping to a separate vector service and re-joining in application code.
- Edge Functions give a natural boundary for "the app never talks to a model vendor
  directly" (ADR 0004) without standing up a separate API gateway.

### Negative (real costs, named)

- **Deno runtime constraints in Edge Functions.** Edge Functions run on Deno, not
  Node — npm packages that rely on Node-specific APIs (native addons, some HTTP
  client internals, certain image-processing libraries) may not run or may require
  `npm:` specifier shims with version pinning risk. This narrows the library choices
  available for, e.g., server-side image pre-processing ahead of a generation
  provider call, and can force hand-rolling logic that would be a one-line dependency
  on a Node backend.
- **Vendor lock-in on RLS-centric auth.** The authorization model is expressed as
  Postgres RLS policies tied to `auth.uid()`, which is a Supabase Auth concept wired
  through Postgres session claims. Migrating identity to a different provider (e.g.
  moving off Supabase Auth to Cognito or a custom OIDC provider) means rewriting
  every RLS policy's assumptions, not just swapping a client SDK call. The wardrobe
  graph's row-level security posture is therefore coupled to staying on Supabase Auth
  specifically, not just Postgres.
- Edge Function cold starts add latency variance to endpoints like
  `POST /kyra/respond` and `POST /outfits/generate`, which have explicit performance
  targets in §20 (Kyra first token under 2.5s). This has to be actively managed
  (keep functions warm, minimize per-invocation init work) rather than assumed away.
- Supabase Realtime, listed as "where useful" in §8, is easy to reach for and easy to
  overuse; every Realtime channel is another thing that must respect RLS and another
  thing that silently degrades under connection churn on mobile networks.
- Running two logically separate environments (local Supabase CLI stack for dev,
  hosted project for staging/prod) means schema drift is a real risk unless
  migrations are disciplined (see ADR 0002 companion practice in CLAUDE.md:
  migrations are append-only).

### The escape hatch

Because the domain and business logic live in Edge Functions written in standard
TypeScript against Postgres, not in Supabase-proprietary stored procedures or
client-only SDK calls, the practical migration path off Supabase is:

1. Postgres is vanilla Postgres — a `pg_dump`/restore to any managed Postgres
   (RDS, Cloud SQL, Neon) preserves the schema, data, and pgvector extension with no
   data-model rewrite.
2. Edge Functions are Deno/TypeScript HTTP handlers; the majority of their logic
   (request validation, provider orchestration, response shaping) ports to any
   Node/Deno-compatible serverless runtime (Cloudflare Workers, Lambda, Fly Machines)
   with moderate, not total, rewrite effort.
3. The component that does *not* port cleanly is RLS-based authorization — that has
   to be reimplemented as explicit authorization checks in the new API layer before
   cutover, which is the single largest migration cost.
4. Storage objects are addressed by `users/{user_id}/...` paths (§15) with no
   Supabase-specific metadata baked into the app; a bucket-to-bucket copy to S3/GCS
   preserves the path convention.

This escape hatch is deliberately not exercised unless Supabase becomes a genuine
blocker (sustained outages, pricing that breaks unit economics at scale, or a hard
platform limitation) — see ADR 0002's Alternatives below for why it isn't the
starting choice.

## Alternatives Considered

- **Firebase (Firestore + Auth + Storage + Functions).** Rejected: Firestore's
  document model is a poor fit for the relational wardrobe graph's join-heavy
  compatibility queries (§10) and has no first-class vector search comparable to
  pgvector at the time of this decision.
- **Bespoke stack (Postgres on RDS + Auth0 + S3 + Pinecone + a Go/Node API server).**
  Rejected for v1: strictly more operational surface (five vendors instead of one),
  more integration glue code, and no material capability advantage for an MVP-stage
  team. This remains the most likely destination if the Supabase escape hatch above
  is ever exercised.
- **AWS Amplify.** Rejected: heavier AWS-specific tooling lock-in than Supabase's
  vanilla-Postgres-plus-Deno-functions approach, and weaker out-of-the-box RLS
  ergonomics for a Postgres-centric relational model.
