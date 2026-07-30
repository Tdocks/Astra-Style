-- §6.8 lists "Typical week" as its own profile field, alongside dress code and
-- common occasions. It was never given a column, so the onboarding step had
-- nowhere to put the answer.
--
-- Adding the column rather than dropping the question, because the answer does
-- real work: dress code says what a man wears when he is dressed for work, and
-- "typical week" says how many days that actually is. Someone in the office five
-- days a week and someone in it once need different quantities of the same
-- wardrobe, and without this Kyra cannot tell them apart.
--
-- text, not an enum, for the same reason laundry_cadence is text (see that
-- column's comment): §6.8 enumerates no value set, and the phrasing is naturally
-- open. The onboarding screen offers a short list to keep common answers
-- consistent without closing the set.

alter table public.lifestyle_profiles
  add column if not exists typical_week text;

comment on column public.lifestyle_profiles.typical_week is
  'Shape of the user''s week from §6.8 — e.g. "Mostly in an office", "Split between home and office". Free text: the onboarding screen offers a short list but does not constrain the value.';
