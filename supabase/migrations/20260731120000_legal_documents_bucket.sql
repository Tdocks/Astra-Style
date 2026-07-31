-- ============================================================================
-- 20260731120000_legal_documents_bucket.sql
-- ============================================================================
-- A public bucket for the four legal documents spec §29 requires: Terms of
-- Service, Privacy Policy, the data-deletion instructions (§15), and the
-- affiliate disclosure (§17).
--
-- WHY A PUBLIC BUCKET, WHEN §15 SAYS "KEEP BUCKETS PRIVATE".
--
-- That rule is about USER CONTENT, and it stands: `user-content` holds a man's
-- closet photographs, his reference selfies and his Studio generations, every
-- object is reached through a signed URL, and nothing about this migration
-- touches it. These documents are the exact opposite kind of object. They must
-- be readable by anyone, without an account and without a session, because the
-- people who need to read them include a prospective user on the welcome
-- screen who has not signed up, and an App Store reviewer who never will.
-- A signed URL cannot serve either.
--
-- Keeping them in a SEPARATE bucket rather than relaxing `user-content` is the
-- whole point. One bucket has exactly one visibility, so a public document and
-- a private photograph must never share one — the failure mode of getting that
-- wrong is not a broken link, it is a stranger's body measurements behind a
-- guessable URL.
--
-- WHY SUPABASE STORAGE AND NOT A DOMAIN.
--
-- There is no domain. `astrastyle.app` is unregistered (verified 2026-07-31:
-- RDAP returns 404, i.e. nobody owns it — the links were dead because the
-- domain was never bought, not because it lapsed). An App Store submission
-- needs a working privacy-policy URL, and this project already pays for
-- storage that serves one over HTTPS today:
--
--   https://<project-ref>.supabase.co/storage/v1/object/public/legal/privacy.html
--
-- It is not a pretty URL. It is a real one, it costs nothing extra, and it
-- unblocks submission without a purchase. Moving to a custom domain later
-- changes one constant in `AstraLegal.swift` and nothing else.
--
-- WHAT THIS MIGRATION DELIBERATELY DOES NOT DO: it does not upload anything.
-- The bucket is created empty. As of this migration the documents exist in the
-- repository under `legal/` as UNREVIEWED DRAFTS carrying visible
-- `[[NEEDS INPUT]]` placeholders — an entity name, a jurisdiction, a contact
-- address, and a flagged biometric-privacy question that needs a lawyer.
-- Publishing an unreviewed privacy policy at a public URL is worse than
-- publishing none, because the unpublished case is honest and the published
-- one makes promises nobody has checked. Upload happens when the drafts are
-- reviewed, in the same change that flips `AstraLegal.isPublished`.
-- ============================================================================

set search_path = public, extensions;

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage.buckets not found (not a Supabase project) — skipping legal bucket setup.';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values (
    'legal',
    'legal',
    true, -- public BY DESIGN: see the header. Static documents only, no user content, ever.
    2097152, -- 2 MiB per object. Generous for self-contained HTML and small
             -- enough that this bucket can never quietly become an asset host.
    array['text/html', 'text/plain', 'text/markdown']
    -- No image types. If a legal document ever needs an image, inline it as a
    -- data: URL in the HTML rather than widening this list — the narrow MIME
    -- allowlist is what stops a public bucket drifting into general-purpose use.
  )
  on conflict (id) do nothing;
end
$$;

-- ----------------------------------------------------------------------------
-- Writes stay service-role only.
-- ----------------------------------------------------------------------------
-- A public bucket is public to READ. Without an explicit policy nobody holding
-- an anon or authenticated JWT can write here, because storage.objects has RLS
-- enabled and no policy grants them insert/update/delete on this bucket — the
-- default is denial, and that is the behaviour we want.
--
-- This block asserts it rather than assuming it, and exists mostly as a place
-- to record the intent for whoever reads this next: publishing a legal document
-- is a deploy step performed with the service-role key, never something the app
-- or a signed-in user can do. If a future migration adds a broad
-- `storage.objects` policy that is not scoped by `bucket_id`, this bucket would
-- silently become writable, and the RLS suite should catch that.
do $$
declare
  writable_policies int;
begin
  if to_regclass('storage.objects') is null then
    return;
  end if;

  select count(*) into writable_policies
  from pg_policies
  where schemaname = 'storage'
    and tablename = 'objects'
    and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
    and roles::text[] && array['anon', 'authenticated']
    and coalesce(qual, '') || coalesce(with_check, '') not like '%bucket_id%';

  if writable_policies > 0 then
    raise warning
      'A storage.objects write policy for anon/authenticated is not scoped by bucket_id (% found). The public `legal` bucket may be writable by end users — check before deploying.',
      writable_policies;
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- Two buckets, deliberately opposite visibility. Do not merge them.
-- ----------------------------------------------------------------------------
--   user-content : PRIVATE. Signed URLs only. Closet photographs, reference
--                  selfies, Studio output. Never public, under any pressure.
--   legal        : PUBLIC.  Static §29 documents. Service-role writes only.
--                  Never user content, under any pressure.
--
-- This was originally written as `comment on schema storage`, which fails with
-- "must be owner of schema storage" — Supabase owns that schema and a project
-- migration cannot annotate it. Left here as a comment rather than dropped,
-- because the instruction matters more than where it is attached.
