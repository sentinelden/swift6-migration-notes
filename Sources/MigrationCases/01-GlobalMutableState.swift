// Case 01, global mutable state
//
// The error:
//   error: global variable 'requestCount' is not concurrency-safe because it
//   is non-isolated global shared mutable state
//
// This is the first error almost everyone hits, and the one where the wrong
// fix is easiest to reach for. See Notes/01-global-mutable-state.md.

import Foundation

// MARK: - Fix 1: it was never actually mutable

/// The commonest case by far. A global that is written once at startup and
/// read thereafter is a constant that was declared `var` out of habit.
public let defaultTimeout: TimeInterval = 30

// MARK: - Fix 2: genuinely shared mutable state belongs in an actor

/// When the state really is mutated from several places, an actor is the
/// answer the language wants you to give. The cost is that every access
/// becomes `await`, which is the honest price of shared mutable state: it
/// was always this expensive, and the compiler just could not make you pay
/// before.
public actor RequestCounter {
    public static let shared = RequestCounter()

    private var count = 0

    public init() {}

    public func increment() {
        count += 1
    }

    public func current() -> Int {
        count
    }
}

// MARK: - Fix 3: state that is conceptually UI-owned

/// If the state is only ever touched from the main thread, which is true of
/// most app-level caches, view models and coordinators, say so. `@MainActor`
/// is cheaper than an actor here because callers on the main actor need no
/// suspension at all.
@MainActor
public final class SessionState {
    public static let shared = SessionState()

    public private(set) var isSignedIn = false

    private init() {}

    public func signIn() {
        isSignedIn = true
    }
}

// MARK: - Fix 4: nonisolated(unsafe), used honestly

/// `nonisolated(unsafe)` disables the check without changing behaviour. That
/// makes it the right tool in exactly one situation: the value is already
/// protected by something the compiler cannot see.
///
/// Here the lock is real, so the annotation states a fact rather than making a
/// wish. Reaching for it because an actor would be inconvenient is how a
/// migration produces code that compiles and still races.
public final class LegacyCache: @unchecked Sendable {
    nonisolated(unsafe) private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func value(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func setValue(_ value: Data, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }
}
