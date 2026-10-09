-- Optional garment care notes supplied by the owner from the item label.
-- Do not infer these values from material; garments with the same fabric can
-- have different construction and cleaning requirements.
ALTER TABLE public.closet_items
    ADD COLUMN care_instructions text;

COMMENT ON COLUMN public.closet_items.care_instructions IS
    'Optional care notes entered by the closet owner; never inferred from garment material.';
