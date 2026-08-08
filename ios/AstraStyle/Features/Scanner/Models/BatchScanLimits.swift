//
//  BatchScanLimits.swift
//  AstraStyle
//
//  The one number the batch scan flow shares with the server.
//

import Foundation

/// Limits for `ScannerRoute.batchCloset` (spec §6.16 "Batch closet scan").
public enum BatchScanLimits {

    /// Maximum images in a single `POST /closet/batch-analyze` submission.
    ///
    /// **Mirrors `MAX_BATCH_ITEMS` in `supabase/functions/closet/schema.ts`.**
    /// The server rejects a larger body with a 400 naming the limit, so a
    /// picker that let the user choose 30 photographs would spend the time
    /// preparing and uploading every one of them and then fail the whole
    /// submission — the failure would arrive after the work, not before it.
    /// Capping the picker means the limit is expressed where the user is
    /// making the choice.
    ///
    /// If the server's number moves, this one has to move with it. There is
    /// no checker for this pair; the drift would show up as that same 400,
    /// which is at least loud.
    public static let maxItemsPerBatch = 20
}
