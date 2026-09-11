// Case 06 — bridging completion handlers
//
// The error:
//   error: passing closure as a 'sending' parameter risks causing data races
//
// And the bug that does not produce any error at all: a continuation does not
// observe cancellation, so the obvious wrapper produces a task that hangs
// forever when cancelled. See Notes/06-continuation-bridging.md.

import Foundation

public enum BridgeError: Error, Equatable {
    case failed(String)
    case cancelled
}

// MARK: - The simple bridge

/// `withCheckedContinuation` is the right tool, and the "checked" part earns
/// its keep during a migration: it traps on double-resume and warns on a
/// leaked continuation, both easy to introduce when converting a callback that
/// had several exit paths.
///
/// Use the checked variant in production too. The unchecked one saves an
/// allocation and costs you the diagnostic that finds the bug.
public func loadValue(
    using legacyAPI: @escaping (@escaping (Result<Int, Error>) -> Void) -> Void
) async throws -> Int {
    try await withCheckedThrowingContinuation { continuation in
        legacyAPI { result in
            continuation.resume(with: result)
        }
    }
}

// MARK: - Cancellation, done correctly

/// A single-resume guard.
///
/// This is the part every "just use withTaskCancellationHandler" example
/// leaves out. Cancellation and completion race: the legacy callback can fire
/// at the same moment `onCancel` runs, and resuming a checked continuation
/// twice is a hard trap, not a warning. Both paths therefore go through one
/// lock-protected slot, and whoever arrives second is dropped.
///
/// It is also possible for cancellation to arrive *before* the continuation is
/// installed, which is why `install` checks `isCancelled` and resumes
/// immediately rather than storing a continuation nobody will ever resume.
private final class ContinuationGuard<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var finished = false
    private var cancelledEarly = false

    /// Store the continuation, or resume it at once if cancellation already
    /// happened.
    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        if cancelledEarly {
            finished = true
            lock.unlock()
            continuation.resume(throwing: BridgeError.cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Resume exactly once. Later callers are ignored rather than trapping.
    ///
    /// `sending` rather than a plain parameter: `Result<T, any Error>` is not
    /// `Sendable`, because `any Error` is not. `sending` says the caller gives
    /// up its copy at the call, which is what actually happens here and what
    /// lets the value cross into the guard safely. Constraining the failure to
    /// `Error & Sendable` is the other option, and it is the better one when
    /// you control the legacy API's error type.
    func finish(with result: sending Result<T, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil {
            // Cancellation beat installation; remember it so `install` can
            // resolve the continuation the moment it arrives.
            cancelledEarly = true
            finished = false
        }
        lock.unlock()
        continuation?.resume(with: result)
    }
}

/// Bridge a cancellable legacy operation.
///
/// Without the cancellation handler this compiles, looks modern, and produces
/// a task that ignores `cancel()` and never completes. That is a hang, not a
/// leak, and it will not show up until something upstream starts cancelling.
public func loadCancellable(
    start: @escaping (@escaping (Result<Int, Error>) -> Void) -> Void,
    cancel: @Sendable @escaping () -> Void
) async throws -> Int {
    let guardBox = ContinuationGuard<Int>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            guardBox.install(continuation)
            start { result in
                guardBox.finish(with: result)
            }
        }
    } onCancel: {
        cancel()
        // Resume the waiter. Omitting this is the hang.
        guardBox.finish(with: .failure(BridgeError.cancelled))
    }
}
