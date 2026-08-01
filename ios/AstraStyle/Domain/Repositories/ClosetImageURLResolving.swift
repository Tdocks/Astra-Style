//
//  ClosetImageURLResolving.swift
//  AstraStyle
//
//  Turns a `ClosetItemImage.storagePath` into something a view can actually
//  display.
//
//  This gap was real and total: `closet_item_images.storage_path` holds a
//  path inside the PRIVATE `user-content` bucket (spec §15,
//  supabase/migrations/20260728101000_storage_buckets.sql), there is no
//  public URL for it by construction, and nothing in the client could
//  produce one. Every closet surface that renders a photo needs this, and
//  none of them may do it themselves — CLAUDE.md's "no network calls in
//  views" is exactly the rule a `.task { try await supabase.storage... }`
//  inside a grid tile would break.
//
//  Two calls, not one. `resolve(storagePaths:)` exists because a closet
//  grid of N tiles resolved one at a time is N HTTPS round trips before
//  the first photograph appears; Storage signs a whole batch in one
//  request. The single-path call is kept for the item-detail screen, where
//  batching one path is just noise.
//

import Foundation

/// Resolves Supabase Storage paths to displayable, time-limited URLs.
///
/// Conformances are expected to cache: signed URLs are valid for a fixed
/// window, and re-signing a path that was signed a minute ago is a round
/// trip that buys nothing. See `LiveClosetImageURLResolver` for the expiry
/// and refresh numbers actually used, and why those numbers.
///
/// GUEST MODE. This is never called for a guest. `GuestClosetRepository`
/// returns `[]` from `fetchImages(forItem:)` — verified, and deliberate per
/// ADR 0011: guest image bytes never reach Supabase Storage, so a guest has
/// no storage path to resolve. A guest closet renders
/// `AstraRemoteImage`'s no-photo fallback, which is the honest result.
public protocol ClosetImageURLResolving: Sendable {
    /// Resolves one path.
    ///
    /// - Throws: `AstraError` when the path cannot be signed — most often
    ///   because it does not exist, or because Row Level Security refused
    ///   it (the object belongs to another user).
    func resolve(storagePath: String) async throws -> URL

    /// Resolves many paths in as few round trips as the backing store
    /// allows.
    ///
    /// - Returns: A map from the requested path to its URL. Paths that
    ///   could not be signed are ABSENT from the result rather than
    ///   throwing — one deleted photo must not blank out a whole grid, and
    ///   the caller already has to handle "no image" for items that have
    ///   none. A caller that needs the distinction should use
    ///   `resolve(storagePath:)`.
    func resolve(storagePaths: [String]) async throws -> [String: URL]
}
