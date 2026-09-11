# 04 — Capturing `self` in a `Task`

```
error: capture of 'self' with non-Sendable type 'Downloader' in a '@Sendable' closure
```

## Why the compiler is right

`Task { }` from a nonisolated context runs on the global executor. Capturing a non-sendable `self` hands it to another domain.

## The fix

Isolate the type. A `Task { }` started from an isolated context **inherits that isolation**, so `self` is not going anywhere and there is nothing to diagnose.

```swift
@MainActor final class Downloader {
    func start(_ name: String) {
        Task { await self.finish(name) }   // inherits @MainActor
    }
}
```

## The trap nobody warns you about

**`Task { }` inherits isolation but not ordering.** Two tasks created back to back can run in either order. Code that relied on a serial `DispatchQueue` for sequencing will compile clean and behave differently.

If order matters, express it:

```swift
for name in names { await finish(name) }   // ordered, explicitly
```

An actor guarantees mutual exclusion, never FIFO across separately created tasks. This is the quietest regression in the whole migration: no error, no warning, and it only shows up under load.

## The escape hatch and why it is a trap

`Task.detached` makes the diagnostic go away by leaving the isolation domain entirely — which reintroduces exactly the race being reported. Use it when the work is genuinely independent and everything captured is genuinely sendable, not to quiet a warning.

→ Compiled examples: [`04-TaskCapture.swift`](../Sources/MigrationCases/04-TaskCapture.swift)
