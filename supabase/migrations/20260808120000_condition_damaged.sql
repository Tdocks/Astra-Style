-- ============================================================================
-- Astra Style — add `damaged` to the `condition` enum
-- ============================================================================
-- `docs/05` §5.6 defines the wardrobe-score condition scale as
-- `excellent=1.0, good=0.8, fair=0.5, worn=0.25, damaged=0.0`. The enum
-- shipped in `20260728100100_core_enums.sql` had no `damaged`, so the 0.0 rung
-- was unreachable: a garment with a hole in it could not score below `worn`
-- (0.25), and the "condition" component of the wardrobe score had no way to
-- tell a well-loved shirt from an unwearable one.
--
-- That gap was not confined to the score. The vision provider's own vocabulary
-- has always included `damaged` (`_shared/providers/visionAnalysis.ts`'s
-- `ProviderCondition`), and `closet/mapper.ts` was mapping it down to `worn` on
-- the way in — so on a scan of a genuinely damaged garment the model's correct
-- reading was silently downgraded to a wrong one. Under this repo's rule that
-- is the bad kind of failure: not an absent reading, a confounded one.
--
-- Why an enum value and not an `availability_state`. `availability_state`
-- already carries `unavailable`, and it is tempting to say a damaged garment is
-- simply unavailable. It is a different fact. `availability_state` answers "can
-- this be worn *right now*" — in the laundry, packed, lent out, lost — and every
-- other value in it is temporary or locational. Condition answers "what state is
-- this garment in", which is a property of the garment and persists across all
-- of those. A damaged coat that is also in alteration needs both facts, and
-- collapsing them would lose the one the wardrobe score reads.
--
-- Ordering: appended after `worn`, so the enum's declaration order continues to
-- run best-to-worst and any `order by condition` stays meaningful.
-- ============================================================================

do $$ begin
  alter type condition add value if not exists 'damaged' after 'worn';
exception when duplicate_object then null; end $$;

comment on type condition is
  'Garment physical condition, set by CV inference (§12) and user-editable (§6.15). '
  'Declared worst-last: new_with_tags > like_new > good > fair > worn > damaged. '
  '`damaged` is docs/05 §5.6''s 0.0 rung — a garment too far gone to wear, distinct '
  'from availability_state.unavailable, which is about right-now wearability.';
