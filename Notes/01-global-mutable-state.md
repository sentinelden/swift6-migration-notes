# 01 — Global mutable state

```
error: global variable 'requestCount' is not concurrency-safe because it is
non-isolated global shared mutable state
```

The first error almost everyone hits, and usually the largest count in the build log.

## Why the compiler is right

A global `var` can be read and written from any thread with no synchronisation. That was always a data race; Swift 5 just had no way to say so. Nothing about your program changed — the compiler's vision improved.

## The fixes, in the order worth trying

**1. It was never mutable.** Check this first. A large share of flagged globals are written once during startup and only read afterwards. They are constants declared `var` out of habit.

```swift
let defaultTimeout: TimeInterval = 30
```

**2. It belongs to the main actor.** Most app-level caches, view models, and coordinators are only ever touched from the main thread. Saying so costs nothing at the call site for code already on the main actor.

```swift
@MainActor final class SessionState { static let shared = SessionState() }
```

**3. It is genuinely shared, mutable state.** Then it wants an actor, and every access becomes `await`. That cost is real, and it is the honest price — it was always this expensive, you just were not being charged.

**4. `nonisolated(unsafe)`, when a lock already exists.** Legitimate when the value is protected by something the compiler cannot see — an `NSLock`, a serial queue you still own. The annotation then records a fact.

## The escape hatch and why it is a trap

`nonisolated(unsafe)` on a value with no actual protection silences the diagnostic and leaves the race. If you reach for it, write the sentence *"this is safe because ___"* first. When the blank cannot be filled, the annotation is wrong.

## What changes at runtime

Options 1 and 4: nothing. Option 2: callers not already on the main actor must now `await`, so some code moves to a later turn of the run loop. Option 3: same, and the state is now genuinely serialised, which may expose ordering assumptions that were previously accidental.

→ Compiled examples: [`01-GlobalMutableState.swift`](../Sources/MigrationCases/01-GlobalMutableState.swift)
