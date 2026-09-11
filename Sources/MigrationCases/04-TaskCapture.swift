// Case 04 — capturing self in a Task
//
// The error (5.10 warning, 6.0 error):
//   error: capture of 'self' with non-Sendable type 'Downloader' in a
//   '@Sendable' closure
//
// And the subtler one nobody warns you about: the fix that compiles can change
// your program's ordering. See Notes/04-task-capture.md.

import Foundation

// MARK: - Fix: isolate the type, and let the Task inherit it

/// A `Task {}` started from an isolated context inherits that isolation, so
/// `self` is not being sent anywhere and there is nothing to diagnose.
///
/// The ordering trap: `Task {}` inherits isolation but NOT execution order.
/// Two tasks started back to back from the main actor can run in either order.
/// Code that relied on serial dispatch to a queue for ordering will compile
/// clean here and behave differently — which is why this case has a test.
@MainActor
public final class Downloader {
    public private(set) var completed: [String] = []

    public init() {}

    public func start(_ name: String) {
        Task {
            // Inherits @MainActor from the enclosing context.
            await self.finish(name)
        }
    }

    /// When order matters, say so explicitly instead of relying on scheduling.
    /// An actor's serial execution guarantees mutual exclusion, never FIFO
    /// across separately created tasks.
    public func startOrdered(_ names: [String]) async {
        for name in names {
            await finish(name)
        }
    }

    private func finish(_ name: String) async {
        completed.append(name)
    }
}

// MARK: - Detached tasks do NOT inherit isolation

/// `Task.detached` is the one people reach for to "escape" a warning. It
/// escapes the isolation too, which reintroduces exactly the data race the
/// diagnostic was about. Everything it captures must genuinely be sendable.
public func fetchIndependently(id: Int) -> Task<Int, Never> {
    Task.detached {
        // `id` is an Int — sendable. Capturing a non-sendable object here
        // would be a real race, not a false positive.
        id * 2
    }
}
