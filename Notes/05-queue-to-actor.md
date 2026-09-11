# 05 — Replacing a serial `DispatchQueue` with an actor

No compiler error drives this one. It is the change people make voluntarily, and the one that most often introduces a bug — because **an actor is not a serial queue**.

## The difference that matters

A serial queue running a synchronous block holds the queue for the entire block. An actor **releases its isolation at every `await`**. Another call can interleave in the middle of a method.

This is invisible in the diff. The shape that breaks is check-then-act:

```swift
actor ImageCache {
    var cache: [URL: Data] = [:]

    func image(at url: URL) async throws -> Data {
        if let cached = cache[url] { return cached }
        let data = try await fetch(url)      // ← isolation released here
        cache[url] = data
        return data
    }
}
```

Ten concurrent callers all miss the cache, all fetch, and nine results are thrown away. Against a serial queue this could not happen. Against an actor it happens on the first busy screen.

## The fix

Track work in flight so later arrivals join it rather than starting their own:

```swift
if let existing = inFlight[url] { return try await existing.value }
let task = Task { try await fetch(url) }
inFlight[url] = task
```

## The rule

**Any `await` inside an actor method is a place where the world can change.** Re-read state after it; do not trust anything you checked before it. Treat every `await` the way you would treat releasing and reacquiring a lock — because that is exactly what it is.

## What changes at runtime

Reentrancy is the whole story. Also: actors do not guarantee FIFO, so code that depended on queue ordering needs the treatment in [04](04-task-capture.md).

→ Compiled example with a test that demonstrates the deduplication: [`05-QueueToActor.swift`](../Sources/MigrationCases/05-QueueToActor.swift)
