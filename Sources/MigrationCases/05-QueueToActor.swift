// Case 05 — replacing a serial DispatchQueue with an actor
//
// No compiler error drives this one. It is the migration people undertake
// voluntarily, and the one that most often introduces a bug, because an actor
// and a serial queue are not the same thing.
//
// See Notes/05-queue-to-actor.md.

import Foundation

// MARK: - The reentrancy difference

/// A serial queue running a synchronous block holds the queue for the whole
/// block. An actor releases its isolation at every `await`, so another call
/// can interleave *in the middle of a method*.
///
/// This is the single biggest behavioural difference in the migration and it
/// is invisible in the diff. The check-then-act below is the shape that breaks:
/// without the in-flight bookkeeping, two concurrent callers both see a cache
/// miss and both fetch.
public actor ImageCache {
    private var cache: [URL: Data] = [:]
    private var inFlight: [URL: Task<Data, Error>] = [:]

    public init() {}

    public func image(at url: URL, fetch: @Sendable @escaping (URL) async throws -> Data) async throws -> Data {
        if let cached = cache[url] {
            return cached
        }

        // Deduplicate: a second caller arriving during the await joins the
        // existing task instead of starting a second fetch. Without this, the
        // `await` below hands isolation to the next caller, who sees the same
        // empty cache.
        if let existing = inFlight[url] {
            return try await existing.value
        }

        let task = Task { try await fetch(url) }
        inFlight[url] = task

        defer { inFlight[url] = nil }

        let data = try await task.value
        cache[url] = data
        return data
    }

    public func cachedCount() -> Int {
        cache.count
    }
}
