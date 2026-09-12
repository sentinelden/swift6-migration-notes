# 08: `deinit` cannot be isolated

```
error: call to main actor-isolated instance method 'invalidate()' in a
synchronous nonisolated context
```

...on the `deinit` of a class that is entirely `@MainActor`. Surprising, because the type looks fully isolated.

## Why the compiler is right

`deinit` is always nonisolated, on every type including actors. Deallocation happens wherever the last reference is released, which could be any thread. It cannot hop to an actor (there is nothing left to suspend), so it cannot touch isolated state.

## The fixes

**1. Make teardown explicit.** Cleanup that needs isolated state has to be something a caller invokes.

```swift
@MainActor final class PollingClient {
    func stop() { timer?.invalidate(); timer = nil }
}
```

More code, and callers can forget. The alternative is worse.

**2. Move the resource into a nonisolated, sendable box.** If cleanup must happen at deallocation, the resource cannot live in isolated storage. A small `@unchecked Sendable` wrapper with its own lock can be released from `deinit` safely, because it touches only its own state.

## The escape hatch and why it is a trap

```swift
deinit {
    Task { @MainActor in self.cleanup() }   // do not
}
```

This captures `self` inside its own `deinit`. The object is already being torn down; by the time the task runs, it is gone. Depending on the day this is a use-after-free or a silent no-op. It compiles.

## What changes at runtime

Option 1: cleanup now happens when the caller says so rather than at an unpredictable deallocation point, generally more deterministic, and a good thing. Option 2: nothing.

→ Compiled examples: [`08-DeinitAndIsolation.swift`](../Sources/MigrationCases/08-DeinitAndIsolation.swift)
