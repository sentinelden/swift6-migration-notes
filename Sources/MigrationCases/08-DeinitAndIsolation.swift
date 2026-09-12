// Case 08, deinit cannot be isolated
//
// The error:
//   error: call to main actor-isolated instance method 'invalidate()' in a
//   synchronous nonisolated context
//
// ...on a `deinit` of a `@MainActor` class. A surprise, because the type looks
// fully isolated. See Notes/08-deinit-and-isolation.md.

import Foundation

// MARK: - The problem

/// `deinit` is always nonisolated, on every type including actors, because
/// deallocation happens wherever the last reference is released. It cannot
/// hop, so it cannot touch isolated state.

// MARK: - Fix 1: make the cleanup explicit

/// Cleanup that needs isolated state has to be something a caller invokes,
/// not something deallocation does. More code, but the alternative is a
/// `Task { }` in `deinit` capturing a half-dead object.
@MainActor
public final class PollingClient {
    private var timer: Timer?
    public private(set) var isRunning = false

    public init() {}

    public func start() {
        isRunning = true
    }

    /// Callers must invoke this. Swift has no isolated-deinit escape hatch, so
    /// an explicit teardown is the honest design rather than a workaround.
    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}

// MARK: - Fix 2: hold the resource in a nonisolated, sendable box

/// If cleanup must happen at deallocation, the resource cannot live in
/// isolated storage. Moving it into a sendable type lets `deinit` release it
/// without touching isolation.
public final class FileHandleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32?

    public init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        descriptor = nil
    }

    deinit {
        // Safe: touches only this type's own lock-protected state, which is
        // nonisolated by construction.
        descriptor = nil
    }
}

@MainActor
public final class DocumentEditor {
    private let handle: FileHandleBox

    public init(descriptor: Int32) {
        self.handle = FileHandleBox(descriptor: descriptor)
    }

    /// `deinit` releases `handle`, whose own deinit does the cleanup. No
    /// isolated state is touched at deallocation.
    deinit {
        handle.close()
    }
}
