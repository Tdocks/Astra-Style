//
//  Deadline.swift
//  AstraStyle
//
//  Bounds an async operation in wall-clock time.
//
//  Written for launch (spec §6.1: the splash routes within 1.4 seconds), but
//  the problem it solves is general: `async` gives no timeout for free, so any
//  `await` on the network can hang for as long as the OS is willing to wait —
//  which, on a flaky connection, is far longer than a user will.
//

import Foundation

/// Runs `operation`, returning `nil` if it has not finished within `duration`.
///
/// The losing task is cancelled, but cancellation in Swift is cooperative: a
/// task that never checks `Task.isCancelled` and never awaits a
/// cancellation-aware call will keep running to completion in the background.
/// That is acceptable here — the point is to stop the CALLER waiting, not to
/// guarantee the work stops — but it does mean this must not be used where a
/// half-finished side effect would be harmful.
///
/// - Returns: The operation's value, or `nil` on timeout.
/// What happened to a deadline-bounded operation.
///
/// Three outcomes, not two. Collapsing `timedOut` and `failed` into a single
/// `nil` loses the distinction between "the network is slow" and "the server
/// rejected us", and those want opposite handling: the first should let the
/// user proceed, the second should send them back to sign in.
enum DeadlineOutcome<T: Sendable>: Sendable {
    case success(T)
    case timedOut
    case failed(any Error)
}

func withDeadline<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async -> DeadlineOutcome<T> {
    await withTaskGroup(of: DeadlineOutcome<T>.self) { group in
        group.addTask {
            do {
                return .success(try await operation())
            } catch {
                return .failed(error)
            }
        }
        group.addTask {
            try? await Task.sleep(for: duration)
            return .timedOut
        }

        // The first result wins — whether that is the operation finishing or
        // the sleep elapsing. Cancelling the group takes the loser down with it.
        let first = await group.next() ?? .timedOut
        group.cancelAll()
        return first
    }
}

/// Ensures `operation` takes *at least* `duration` before returning.
///
/// The splash is a brand moment, and a launch fast enough to skip it entirely
/// reads as a flicker rather than as speed. This holds a floor without adding
/// delay to a launch that was already slower than the floor.
func withMinimumDuration<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async -> T
) async -> T {
    // `try?` on Task.sleep yields `Void?`, not `Void` — it has to be bound to
    // an optional and then awaited, rather than discarded into `_`.
    async let value = operation()
    async let floor: Void? = try? await Task.sleep(for: duration)

    let result = await value
    _ = await floor
    return result
}
