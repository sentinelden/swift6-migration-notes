// Case 07, @unchecked Sendable: when it is a fact and when it is a wish
//
// No error drives this. It is the escape hatch, and the single biggest
// determinant of whether a migration produced safer code or just quieter code.
//
// The test: `@unchecked Sendable` is a promise that YOU maintain the
// invariant the compiler would otherwise check. Writing it down is fine when
// the invariant exists. It is a lie when the reason is "an actor would have
// meant changing callers."
//
// See Notes/07-unchecked-sendable.md.

import Foundation

// MARK: - Legitimate: a real lock protects every access

/// The invariant is real and stated: every access goes through `lock`. Someone
/// reading this can verify the promise in the same screenful of code, which is
/// the bar `@unchecked` should have to clear.
public final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    public init(_ value: Value) {
        self.value = value
    }

    public func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    public func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - Legitimate: immutable after init, but the compiler cannot prove it

/// A class holding a non-sendable type it never mutates and never hands out.
/// `Formatter` is not `Sendable`, but this wrapper only ever reads through a
/// lock, so the promise holds.
public final class SharedFormatter: @unchecked Sendable {
    private let formatter: NumberFormatter
    private let lock = NSLock()

    public init() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        self.formatter = formatter
    }

    public func string(from value: Int) -> String {
        // NumberFormatter is not thread-safe for concurrent use, so the lock
        // is load-bearing, not decorative.
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Not legitimate
//
// The shape below is what a rushed migration produces. It is written here as a
// comment rather than as code, because compiling it would put a racy type in a
// package whose point is the opposite.
//
//     public final class Cache: @unchecked Sendable {
//         public var storage: [String: Data] = [:]   // public, unprotected
//     }
//
// There is no invariant here to maintain. `@unchecked` silences the diagnostic
// and leaves the race. If reaching for it, write the sentence "this is safe
// because ___" in a comment first; when the blank cannot be filled, the
// annotation is wrong.
