-- ============================================================================
-- Astra Style — 12. Indexes & search
-- ============================================================================
-- Postgres does not automatically index foreign-key columns (only the
-- referenced side is indexed). This migration adds:
--   1. btree indexes on every foreign key not already covered by a unique
--      constraint's implicit index.
--   2. Composite/partial btree indexes for the specific hot query patterns
--      named in the spec (§6.11 Daily Brief, §6.14 closet filters/views,
--      §5.4 outfit generation, §6.19/§6.20 evaluation history).
--   3. GIN indexes on jsonb columns that are filtered/queried, not just stored.
--   4. GIN trigram indexes (pg_trgm) for the closet/product search bars.
--   5. HNSW indexes on every vector column.
-- See docs/04-data-model.md "Query patterns each index serves" for the
-- one-line justification of each entry below, cross-referenced by index name.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- 1 & 2. Foreign-key and hot-path btree indexes
-- ----------------------------------------------------------------------------

-- closet_items
create index if not exists idx_closet_items_user_active
  on public.closet_items (user_id)
  where archived_at is null;

create index if not exists idx_closet_items_user_category_active
  on public.closet_items (user_id, category)
  where archived_at is null;

create index if not exists idx_closet_items_user_availability_active
  on public.closet_items (user_id, availability_state, laundry_state)
  where archived_at is null;

-- closet_item_images
create index if not exists idx_closet_item_images_closet_item_id
  on public.closet_item_images (closet_item_id);

create index if not exists idx_closet_item_images_user_id
  on public.closet_item_images (user_id);

-- outfits
create index if not exists idx_outfits_user_active
  on public.outfits (user_id)
  where archived_at is null;

create index if not exists idx_outfits_user_favorite
  on public.outfits (user_id, is_favorite)
  where archived_at is null and is_favorite;

-- outfit_items
create index if not exists idx_outfit_items_outfit_id
  on public.outfit_items (outfit_id);

create index if not exists idx_outfit_items_user_id
  on public.outfit_items (user_id);

create index if not exists idx_outfit_items_closet_item_id
  on public.outfit_items (closet_item_id)
  where closet_item_id is not null;

create index if not exists idx_outfit_items_product_candidate_id
  on public.outfit_items (product_candidate_id)
  where product_candidate_id is not null;

-- outfit_wears
create index if not exists idx_outfit_wears_outfit_id_worn_at
  on public.outfit_wears (outfit_id, worn_at desc);

create index if not exists idx_outfit_wears_user_id_worn_at
  on public.outfit_wears (user_id, worn_at desc);

-- style_feedback
create index if not exists idx_style_feedback_user_id
  on public.style_feedback (user_id);

create index if not exists idx_style_feedback_target
  on public.style_feedback (target_type, target_id);

-- style_memories
create index if not exists idx_style_memories_user_id
  on public.style_memories (user_id);

create index if not exists idx_style_memories_source_message_id
  on public.style_memories (source_message_id)
  where source_message_id is not null;

-- kyra_threads / kyra_messages
create index if not exists idx_kyra_threads_user_id_last_message
  on public.kyra_threads (user_id, last_message_at desc);

create index if not exists idx_kyra_messages_thread_id_created_at
  on public.kyra_messages (thread_id, created_at);

create index if not exists idx_kyra_messages_user_id
  on public.kyra_messages (user_id);

-- occasions
create index if not exists idx_occasions_user_id_starts_at
  on public.occasions (user_id, starts_at);

-- studio_generations
create index if not exists idx_studio_generations_user_id_status
  on public.studio_generations (user_id, status)
  where deleted_at is null;

create index if not exists idx_studio_generations_outfit_id
  on public.studio_generations (outfit_id)
  where outfit_id is not null;

-- subscriptions
create index if not exists idx_subscriptions_user_id
  on public.subscriptions (user_id);

-- product_candidates / user_product_evaluations
create index if not exists idx_user_product_evaluations_user_product_created
  on public.user_product_evaluations (user_id, product_candidate_id, created_at desc);

create index if not exists idx_user_product_evaluations_product_candidate_id
  on public.user_product_evaluations (product_candidate_id);

-- ----------------------------------------------------------------------------
-- 3. GIN indexes on queried jsonb columns
-- ----------------------------------------------------------------------------
-- jsonb_path_ops is used where the only query need is "does this array/object
-- contain value X" (containment via @>), which is smaller and faster than the
-- default jsonb_ops for that single operator class; we use it everywhere here
-- because every one of these columns is filtered by containment, not by
-- existence (?) or path queries.

create index if not exists idx_closet_items_seasonality_gin
  on public.closet_items using gin (seasonality jsonb_path_ops);

create index if not exists idx_closet_items_secondary_colors_gin
  on public.closet_items using gin (secondary_colors jsonb_path_ops);

create index if not exists idx_outfits_occasion_tags_gin
  on public.outfits using gin (occasion_tags jsonb_path_ops);

create index if not exists idx_product_candidates_attributes_gin
  on public.product_candidates using gin (attributes jsonb_path_ops);

-- ----------------------------------------------------------------------------
-- 4. Trigram search indexes (§6.14 closet search, §6.21/§6.19 product search)
-- ----------------------------------------------------------------------------

create index if not exists idx_closet_items_name_trgm
  on public.closet_items using gin (name extensions.gin_trgm_ops);

create index if not exists idx_closet_items_brand_trgm
  on public.closet_items using gin (brand extensions.gin_trgm_ops);

create index if not exists idx_product_candidates_name_trgm
  on public.product_candidates using gin (name extensions.gin_trgm_ops);

create index if not exists idx_product_candidates_brand_trgm
  on public.product_candidates using gin (brand extensions.gin_trgm_ops);

-- ----------------------------------------------------------------------------
-- 5. HNSW vector indexes
-- ----------------------------------------------------------------------------
-- vector_cosine_ops: embeddings from the EmbeddingProvider abstraction (§8)
-- are compared by cosine similarity, the standard choice for normalized text/
-- image embeddings. Default HNSW build parameters (m=16, ef_construction=64)
-- are left as pgvector defaults; revisit if recall/latency profiling on real
-- data volumes says otherwise (see docs/04-data-model.md "what changes past
-- 10k users").

create index if not exists idx_style_profiles_embedding_hnsw
  on public.style_profiles using hnsw (embedding extensions.vector_cosine_ops)
  where embedding is not null;

create index if not exists idx_closet_items_embedding_hnsw
  on public.closet_items using hnsw (embedding extensions.vector_cosine_ops)
  where embedding is not null;

create index if not exists idx_outfits_embedding_hnsw
  on public.outfits using hnsw (embedding extensions.vector_cosine_ops)
  where embedding is not null;

create index if not exists idx_style_memories_embedding_hnsw
  on public.style_memories using hnsw (embedding extensions.vector_cosine_ops)
  where embedding is not null;
