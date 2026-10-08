# ADR 0027 — Enforce guest photo locality at Storage

Status: Accepted, 2026-10-08.

ADR 0018 keeps guest photo bytes on-device until Apple or email linking. Native
local storage implemented that flow, but Storage ownership policies also allowed
anonymous Auth users to upload directly: they carry the authenticated role.

Restrictive INSERT and UPDATE policies on user-content now require the signed
root JWT is_anonymous claim to be explicitly false. Missing claims fail closed.
Editable user_metadata never authorizes uploads. Existing ownership policies
still apply, so permanent users cannot write another user's paths. Owned reads
remain available for server-generated guest inspiration; trusted server output
writes retain their service-role boundary. Linking returns a fresh session in
the Supabase Swift SDK before the app migrates local photos.

Verification: the complete scratch SQL isolation suite passed, including guest
closet/reference/avatar INSERT denial, UPDATE denial, metadata independence,
owned reads, permanent owner writes, peer isolation, missing-claim denial and
server output writes. The deployed Storage API rejected all three guest upload
categories with RLS errors, and rejected another reference upload after the QA
user changed editable is_anonymous metadata to false. The disposable account
was erased; a follow-up query confirmed zero QA accounts and objects.

This server change is compatible with build 18 and needs no new native upload.
Apple linking and the local-photo migration still require physical-device
acceptance; the SQL permanent-user checks do not establish that device flow.
