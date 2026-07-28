-- ============================================================================
-- Astra Style — 02. Core enum types
-- ============================================================================
-- Every enum below is created inside a `do $$ ... exception when duplicate_object`
-- guard because Postgres has no `create type if not exists`. This makes each
-- block idempotent-safe to rerun.
--
-- Value sets are derived from the master spec as follows:
--   clothing_category      -> §26 ClothingCategory, §6.13 category rail, §6.14 filters
--   laundry_state           -> §26 LaundryState
--   availability_state      -> §9 closet_items.availability_state (values not
--                               enumerated in the spec; see docs/04-data-model.md
--                               "Ambiguities resolved" for the interpretation used)
--   condition                -> §6.15 item detail, §12 CV pipeline "estimate condition"
--                               (values not enumerated; reasonable menswear-resale
--                               scale chosen, documented in the data model doc)
--   fit_preference            -> §6.6 "Preferred fit: slim, tailored, regular, relaxed, oversized"
--   kyra_verdict              -> §26 KyraVerdict, §6.19 Kyra verdict
--   feedback_signal           -> §9 style_feedback "Signals" list
--   subscription_status       -> §16 subscription model + standard App Store
--                                 Server API / StoreKit 2 subscription states
--   generation_status         -> §6.17 "Generation states: Queued, Generating,
--                                 Complete, Failed with retry"
--   image_type                -> §5.3 closet scan capture (front/back/label/detail),
--                                 §6.16 scanner capture modes
--   dress_code                -> §6.8, §6.24 "dress codes" (values not enumerated;
--                                 a standard menswear dress-code ladder is used)
--   style_identity             -> §6.5 the ten named style identity cards
--   formality_preference       -> §6.9 style quiz "formality" axis
--   accessory_preference       -> §6.9 style quiz "accessory preference" axis
--   units_preference / theme_preference -> §9 profiles.units / profiles.theme, §3
--   subscription_tier          -> §16 Free / Astra Style Premium
--   memory_type                -> §6.20 "save durable preferences" / style_memories
--   feedback_target_type       -> §9 style_feedback.target_type (polymorphic target)
--   kyra_message_role          -> §9 kyra_messages.role (standard chat roles)
--   outfit_source               -> §9 outfits.source
--   occasion_source             -> §9 occasions.source
--   subscription_environment    -> §9 subscriptions.environment (sandbox/production)
-- ============================================================================

set search_path = public, extensions;

do $$ begin
  create type clothing_category as enum (
    'top', 'bottom', 'outerwear', 'shoes', 'accessory', 'watch', 'fragrance'
  );
exception when duplicate_object then null; end $$;
comment on type clothing_category is
  'Top-level garment category. Doubles as outfit_items.role and the closet builder category rail (§6.13).';

do $$ begin
  create type laundry_state as enum (
    'clean', 'worn_once', 'laundry', 'unavailable'
  );
exception when duplicate_object then null; end $$;
comment on type laundry_state is
  'Where an item sits in the wash cycle. Narrower than availability_state, which is the overall wearability gate.';

do $$ begin
  create type availability_state as enum (
    'available', 'in_laundry', 'in_alteration', 'packed_for_travel', 'lent_out', 'lost', 'unavailable'
  );
exception when duplicate_object then null; end $$;
comment on type availability_state is
  'Overall gate on whether an item can be selected into an outfit right now. Broader than laundry_state: covers alteration, travel packing, loans, and loss, not just the wash cycle.';

do $$ begin
  create type condition as enum (
    'new_with_tags', 'like_new', 'good', 'fair', 'worn'
  );
exception when duplicate_object then null; end $$;
comment on type condition is
  'Garment physical condition, set by CV inference (§12) and user-editable (§6.15).';

do $$ begin
  create type fit_preference as enum (
    'slim', 'tailored', 'regular', 'relaxed', 'oversized'
  );
exception when duplicate_object then null; end $$;
comment on type fit_preference is
  'Cut/fit preference, §6.6. Used both as a user preference (style_profiles) and a per-garment attribute (closet_items).';

do $$ begin
  create type kyra_verdict as enum (
    'buy', 'consider', 'wait_for_sale', 'skip'
  );
exception when duplicate_object then null; end $$;
comment on type kyra_verdict is
  'Kyra''s purchase verdict, §6.19 / §26 KyraVerdict.';

do $$ begin
  create type feedback_signal as enum (
    'like', 'dislike', 'wore', 'skipped', 'saved', 'purchased', 'returned',
    'too_formal', 'too_casual', 'bad_fit', 'wrong_color'
  );
exception when duplicate_object then null; end $$;
comment on type feedback_signal is
  'style_feedback.signal value set, verbatim from §9.';

do $$ begin
  create type subscription_status as enum (
    'trialing', 'active', 'in_grace_period', 'in_billing_retry', 'expired', 'revoked', 'cancelled'
  );
exception when duplicate_object then null; end $$;
comment on type subscription_status is
  'Mirrors App Store Server Notifications / StoreKit 2 subscription status categories, reconciled by POST /subscriptions/sync and POST /app-store/webhook (§14).';

do $$ begin
  create type generation_status as enum (
    'queued', 'generating', 'complete', 'failed'
  );
exception when duplicate_object then null; end $$;
comment on type generation_status is
  'Style Studio generation job state, §6.17.';

do $$ begin
  create type image_type as enum (
    'front', 'back', 'label', 'detail', 'on_body', 'other'
  );
exception when duplicate_object then null; end $$;
comment on type image_type is
  'closet_item_images.image_type — capture role of the source photo, §5.3/§6.16.';

do $$ begin
  create type dress_code as enum (
    'ultra_casual', 'casual', 'smart_casual', 'business_casual', 'business_formal',
    'black_tie', 'formal', 'athletic'
  );
exception when duplicate_object then null; end $$;
comment on type dress_code is
  'Menswear dress-code ladder used by lifestyle_profiles.dress_code, occasions.dress_code, and packing (§6.24). Not enumerated verbatim in the spec; see docs/04-data-model.md.';

do $$ begin
  create type style_identity as enum (
    'modern_heritage', 'quiet_luxury', 'smart_casual', 'minimalist', 'luxury_streetwear',
    'rugged_utility', 'classic_americana', 'european_summer', 'executive', 'creative'
  );
exception when duplicate_object then null; end $$;
comment on type style_identity is
  'The ten style-identity cards from §6.5, used for style_profiles.primary_identity and secondary_identities.';

do $$ begin
  create type formality_preference as enum (
    'very_casual', 'casual', 'balanced', 'formal', 'very_formal'
  );
exception when duplicate_object then null; end $$;
comment on type formality_preference is
  'Discretized version of the §6.9 style-quiz "formality" comparison axis.';

do $$ begin
  create type accessory_preference as enum (
    'minimal', 'moderate', 'bold'
  );
exception when duplicate_object then null; end $$;
comment on type accessory_preference is
  'Discretized version of the §6.9 style-quiz "accessory preference" axis.';

do $$ begin
  create type units_preference as enum ('imperial', 'metric');
exception when duplicate_object then null; end $$;

do $$ begin
  create type theme_preference as enum ('dark', 'light', 'system');
exception when duplicate_object then null; end $$;

do $$ begin
  create type subscription_tier as enum ('free', 'premium');
exception when duplicate_object then null; end $$;
comment on type subscription_tier is '§16 Free vs Astra Style Premium.';

do $$ begin
  create type memory_type as enum (
    'preference', 'dislike', 'fit_note', 'brand_affinity', 'budget_note', 'sizing_note', 'general'
  );
exception when duplicate_object then null; end $$;
comment on type memory_type is
  'style_memories.memory_type — categorizes durable preferences Kyra chooses to remember, §6.20.';

do $$ begin
  create type feedback_target_type as enum (
    'closet_item', 'outfit', 'outfit_item', 'product_candidate'
  );
exception when duplicate_object then null; end $$;
comment on type feedback_target_type is
  'style_feedback.target_type — see column comment on style_feedback.target_id for why this is a polymorphic reference rather than a foreign key.';

do $$ begin
  create type kyra_message_role as enum ('system', 'user', 'assistant', 'tool');
exception when duplicate_object then null; end $$;

do $$ begin
  create type outfit_source as enum (
    'ai_generated', 'user_created', 'kyra_suggested', 'studio_derived'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type occasion_source as enum ('manual', 'calendar_sync', 'ai_suggested');
exception when duplicate_object then null; end $$;

do $$ begin
  create type subscription_environment as enum ('sandbox', 'production');
exception when duplicate_object then null; end $$;
