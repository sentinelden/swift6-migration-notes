// These tests exist to prove the claims the notes make.
//
// A note that says "an actor is not a serial queue, and the difference will
// bite you here" is worth more when there is a test demonstrating the bite.
// Several of these would fail against the naive version of the fix, which is
// the point.

import XCTest
@testable import MigrationCases

// MARK: - Case 01

final class GlobalStateTests: XCTestCase {

    func testActorSerialisesConcurrentMutation() async {
        let counter = RequestCounter()

        // 1,000 concurrent increments. Against a plain global `var` this is
        // the race the compiler now refuses to allow.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1_000 {
                group.addTask { await counter.increment() }
            }
        }

        let total = await counter.current()
        XCTAssertEqual(total, 1_000)
    }

    @MainActor
    func testMainActorStateIsReachableWithoutSuspension() {
        let state = SessionState.shared
        state.signIn()
        XCTAssertTrue(state.isSignedIn)
    }

    func testLockedLegacyCacheSurvivesConcurrentAccess() async {
        let cache = LegacyCache()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    cache.setValue(Data([UInt8(i % 256)]), for: "key-\(i)")
                    _ = cache.value(for: "key-\(i)")
                }
            }
        }

        XCTAssertEqual(cache.value(for: "key-5"), Data([5]))
    }
}

// MARK: - Case 02

final class SendableTests: XCTestCase {

    func testSendableValueCrossesTaskBoundary() async {
        let users = [
            User(id: UUID(), name: "ada", joinedAt: .distantPast),
            User(id: UUID(), name: "grace", joinedAt: .distantPast),
        ]
        let names = await summarise(users: users)
        XCTAssertEqual(names, ["ADA", "GRACE"])
    }
}

// MARK: - Case 03

final class ProtocolIsolationTests: XCTestCase {

    @MainActor
    func testMainActorDelegateConformance() {
        let controller = ListViewController()
        controller.didUpdate(itemCount: 7)
        XCTAssertEqual(controller.lastCount, 7)
    }

    func testActorConformsViaAsyncRequirement() async {
        let sink: any EventSink = BufferedSink()
        await sink.record("one")
        await sink.record("two")

        let drained = await (sink as! BufferedSink).drain()
        XCTAssertEqual(drained, ["one", "two"])
    }
}

// MARK: - Case 04

final class TaskCaptureTests: XCTestCase {

    /// The claim in the note: `Task {}` inherits isolation but not ordering,
    /// so sequencing must be explicit. This asserts the explicit version does
    /// what the queue-based original did.
    @MainActor
    func testExplicitSequencingPreservesOrder() async {
        let downloader = Downloader()
        await downloader.startOrdered(["a", "b", "c"])
        XCTAssertEqual(downloader.completed, ["a", "b", "c"])
    }

    func testDetachedTaskRunsIndependently() async {
        let value = await fetchIndependently(id: 21).value
        XCTAssertEqual(value, 42)
    }
}

// MARK: - Case 05

final class ReentrancyTests: XCTestCase {

    /// The load-bearing test of the whole repository.
    ///
    /// Ten callers ask for the same URL at once. An actor releases isolation
    /// at every `await`, so without the in-flight bookkeeping every one of
    /// them would observe an empty cache and start its own fetch. A serial
    /// DispatchQueue would not have behaved this way, which is exactly why
    /// this migration breaks things quietly.
    func testConcurrentRequestsForTheSameURLFetchOnce() async throws {
        let cache = ImageCache()
        let url = URL(string: "https://example.com/a.png")!
        let fetchCount = FetchCounter()

        let results = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await cache.image(at: url) { _ in
                        await fetchCount.increment()
                        // Yield so the other callers are guaranteed to arrive
                        // during this await — the interleaving window is the
                        // whole point.
                        try await Task.sleep(nanoseconds: 10_000_000)
                        return Data([1, 2, 3])
                    }
                }
            }
            var all: [Data] = []
            for try await value in group { all.append(value) }
            return all
        }

        XCTAssertEqual(results.count, 10)
        XCTAssertTrue(results.allSatisfy { $0 == Data([1, 2, 3]) })

        let fetches = await fetchCount.value()
        XCTAssertEqual(fetches, 1, "the fetch should be deduplicated across concurrent callers")

        let cached = await cache.cachedCount()
        XCTAssertEqual(cached, 1)
    }
}

actor FetchCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}

// MARK: - Case 06

final class ContinuationTests: XCTestCase {

    func testBridgesSuccess() async throws {
        let value = try await loadValue { completion in
            completion(.success(99))
        }
        XCTAssertEqual(value, 99)
    }

    func testBridgesFailure() async {
        do {
            _ = try await loadValue { completion in
                completion(.failure(BridgeError.failed("nope")))
            }
            XCTFail("expected the error to propagate")
        } catch {
            XCTAssertEqual(error as? BridgeError, .failed("nope"))
        }
    }

    /// The note's claim: a bare continuation ignores cancellation, so the
    /// handler has to be wired explicitly. This asserts the handler fires.
    func testCancellationHandlerRuns() async throws {
        let cancelled = LockedBox(false)

        let task = Task {
            try await loadCancellable(
                start: { _ in /* never completes */ },
                cancel: { cancelled.withLock { $0 = true } }
            )
        }

        // Let the task reach its suspension point before cancelling.
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        _ = try? await task.value

        XCTAssertTrue(cancelled.get(), "onCancel should have fired")
    }
}

// MARK: - Case 07

final class UncheckedSendableTests: XCTestCase {

    func testLockedBoxIsSafeUnderConcurrency() async {
        let box = LockedBox(0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1_000 {
                group.addTask { box.withLock { $0 += 1 } }
            }
        }

        XCTAssertEqual(box.get(), 1_000)
    }

    func testSharedFormatterIsSafeUnderConcurrency() async {
        let formatter = SharedFormatter()

        let results = await withTaskGroup(of: String.self) { group in
            for i in 0..<200 {
                group.addTask { formatter.string(from: i) }
            }
            var all: [String] = []
            for await value in group { all.append(value) }
            return all
        }

        XCTAssertEqual(results.count, 200)
        XCTAssertTrue(results.allSatisfy { !$0.isEmpty })
    }
}

// MARK: - Case 08

final class DeinitTests: XCTestCase {

    @MainActor
    func testExplicitTeardown() {
        let client = PollingClient()
        client.start()
        XCTAssertTrue(client.isRunning)
        client.stop()
        XCTAssertFalse(client.isRunning)
    }

    @MainActor
    func testDeallocationDoesNotTouchIsolatedState() {
        // Constructing and releasing must not trap. The resource lives in a
        // nonisolated box precisely so deinit has nothing isolated to reach.
        for _ in 0..<100 {
            _ = DocumentEditor(descriptor: -1)
        }
        XCTAssertTrue(true, "no crash on deallocation")
    }
}
