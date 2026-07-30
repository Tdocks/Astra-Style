-- §6.9's paired-image quiz infers eight dimensions: colour tolerance, formality,
-- silhouette, texture, logo tolerance, trend tolerance, accessory preference and
-- contrast preference. `style_profiles` had a home for four of them
-- (formality_preference, logo_tolerance, trend_tolerance, accessory_preference)
-- and no home at all for colour tolerance, texture or contrast preference. The
-- quiz would have run, inferred all eight, and persisted half.
--
-- WHY ONE jsonb COLUMN AND NOT FOUR MORE SCALAR ONES.
--
-- The three missing axes are not the whole problem. The four columns that do
-- exist hold a value and nothing else, and a value alone is not what §6.9
-- produces. Twelve to twenty comparisons across eight axes is one to three
-- comparisons per axis, and a forced choice between two photographs is close to
-- one bit — it says which side of a line the man fell on, not how far from it he
-- stands. "Formality: 0.8" written into a scalar column is indistinguishable
-- from a measurement, and downstream (Style DNA generation, compatibility
-- scoring, Kyra's context packet) it WILL be treated as one.
--
-- So the quiz's output is stored as a document that keeps, per axis: the score,
-- a confidence band, the effective number of observations behind it, and how
-- consistent those observations were. Adding four columns per axis — thirty-two
-- columns — to express that relationally would be a worse schema for data that
-- is always read as a whole and never filtered on individually.
--
-- The absence of an axis is itself meaningful and jsonb is what lets us say it.
-- An axis with no key was never asked about (the comparison set had no imagery
-- probing it — today that is five of the eight). An axis present with
-- observations 0 was asked about and the user had no preference. Those are
-- different facts, and a NOT NULL numeric column cannot hold the difference:
-- it would force both into 0, which reads as "measured, and neutral".
--
-- WHAT THIS DOES NOT CHANGE. formality_preference, logo_tolerance,
-- trend_tolerance and accessory_preference stay exactly as they are. They are
-- the Style DNA generator's summary output (§6.10) — a considered read across
-- goals, identity, lifestyle AND this vector — not the quiz's raw inference.
-- Having the quiz write them directly would let three photographs overwrite a
-- judgement made from everything the user said.

alter table public.style_profiles
  add column if not exists preference_vector jsonb not null default '{}'::jsonb;

comment on column public.style_profiles.preference_vector is
  'The §6.9 preference quiz result. Shape: {version, comparisons_answered, comparisons_offered, dimensions: {<axis>: {score, confidence, observations, agreement}}}. Axis keys are the raw values of the Swift StyleDimension enum; scores run -1..1 on that enum''s documented sign conventions, and flipping one silently inverts every stored row. An axis with NO key was never asked about; an axis present with observations 0 was asked and drew no preference. ''{}'' means the step was skipped, which §6.9 permits.';
