# 0023. Private Studio saved-look collections

## Status

Accepted — implementing against master spec §5.6, §13 and ADR 0010.

## Decision

Use owned `studio_lookbooks` and `studio_lookbook_entries` for explicit collections
of completed Studio estimates. Inspiration images have no closet garments, so
they must not become empty wardrobe outfits or public worn looks. Discover's
outfit/public-look models remain separate.

Composite ownership foreign keys prevent linking another user's collection or
generation. RLS only admits completed, undeleted owned estimates. Client entries
are immutable; moving a look means saving/removing it explicitly. The client
never receives a public image URL and resolves each result privately on view.

Saving an estimate clears its `retention_expires_at`. Removing it from its last
collection starts a fresh 30-day unsaved window so removal does not unexpectedly
destroy an older estimate. Removing a collection has the same effect on its
entries. Deleting an estimate removes its collection entries and stored image;
account deletion cascades the new tables. Consumed generation allowances survive
individual image deletion, as in ADR 0022.

The retention timestamp and permanent-save exception are implemented with the
collection schema. A scheduled Storage API expiration sweep is separate required
work; timestamps alone do not prove automatic deletion. Source images referenced
by retained generations must not be swept while still needed for comparison.

Export includes both collection tables and the generation's retention timestamp.
No image copies or expiring signed URLs are persisted in collection rows. Export
uses the existing owned, paginated path. Collections are private; public/social
lookbook sharing remains the master spec's deferred scope.
