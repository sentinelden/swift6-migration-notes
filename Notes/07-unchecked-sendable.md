# 07: `@unchecked Sendable`: fact or wish

No error drives this. It is the escape hatch, and it is the single biggest determinant of whether a migration produced safer code or merely quieter code.

## The test

`@unchecked Sendable` is a promise that **you** maintain the invariant the compiler would otherwise check. Writing it down is fine when the invariant exists.

Before using it, complete this sentence in a comment:

> This is safe because ___

If the blank cannot be filled, or the honest filling is *"an actor would have meant changing every caller"*, the annotation is wrong.

## Legitimate uses

**A real lock protects every access.** The invariant is stated and a reader can verify it in the same screenful of code. That is the bar.

```swift
final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T { ... }
}
```

**A non-sendable type held privately and never handed out.** `NumberFormatter` is not `Sendable` and is not safe for concurrent use, so a wrapper that funnels every call through a lock is doing real work.

## The illegitimate shape

```swift
final class Cache: @unchecked Sendable {
    var storage: [String: Data] = [:]   // public, unprotected
}
```

There is no invariant to maintain. The annotation silences the diagnostic and leaves the race exactly where it was.

## What to do instead

Before reaching for it, in order: make the type a value type; make the class `final` with only `let` properties (then it is `Sendable` with no `@unchecked` at all, the most commonly missed option); make it an actor; isolate it to `@MainActor`.

## Auditing a finished migration

`grep -rn "@unchecked Sendable" --include="*.swift" .` and read every one. A migration that ends with dozens of them did not make the code safer; it made the compiler stop mentioning it.

→ Compiled examples: [`07-UncheckedSendable.swift`](../Sources/MigrationCases/07-UncheckedSendable.swift)
