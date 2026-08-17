//
//  AnalyticsEventDiskStore.swift
//  AstraStyle
//
//  Persists `AnalyticsEventQueue`'s backlog across launches, so a device
//  that goes offline mid-session doesn't lose everything queued since the
//  last successful flush the moment the app is force-quit or evicted.
//  Deliberately a flat JSON file, not SwiftData: `LiveAnalyticsClient` is
//  constructed with zero arguments in `AppContainer.live()`
//  (`let analyticsClient = LiveAnalyticsClient()`), before the shared
//  `ModelContainer` even exists (see `AnalyticsEventQueue`'s header for the
//  full reasoning) — adding a SwiftData `@Model` here would mean either a
//  second, unrelated `ModelContainer` just for this one table, or
//  restructuring `AppContainer`'s construction order, for a queue whose
//  worst-case failure mode (losing a handful of analytics events) does not
//  justify either.
//
//  Every operation on this type is best-effort: a failure to read or write
//  the file is swallowed, never thrown, matching `AnalyticsClient.log`'s
//  own "never throws into its caller" contract one level down. Losing the
//  queue file (corrupt disk, first-launch-after-upgrade schema mismatch)
//  degrades to "this session's analytics start from empty," not a crash.
//

import Foundation

struct AnalyticsEventDiskStore: Sendable {
    let fileURL: URL

    /// `Application Support/AstraStyle/analytics_event_queue.json`.
    /// Application Support isn't included in the user-visible Files app and
    /// isn't synced to iCloud the way Documents is by default — a
    /// reasonable home for a queue of non-sensitive metadata that has no
    /// reason to leave the device except to Astra's own backend.
    static let live = AnalyticsEventDiskStore(fileURL: Self.defaultFileURL())

    private static func defaultFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("AstraStyle", isDirectory: true)
            .appendingPathComponent("analytics_event_queue.json", isDirectory: false)
    }

    func load() -> [QueuedAnalyticsEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.astraDefault.decode([QueuedAnalyticsEvent].self, from: data)) ?? []
    }

    func save(_ events: [QueuedAnalyticsEvent]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.astraDefault.encode(events)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort only — see header comment.
        }
    }
}
