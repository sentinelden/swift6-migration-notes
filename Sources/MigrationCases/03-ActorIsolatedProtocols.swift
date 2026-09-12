// Case 03, protocol conformance across isolation
//
// The error:
//   error: main actor-isolated instance method 'didUpdate' cannot be used to
//   satisfy nonisolated requirement from protocol 'DataSourceDelegate'
//
// The single most disruptive error in a real migration, because it shows up in
// every delegate protocol written before 2021 and the fix is not local: it
// changes the protocol's contract. See Notes/03-actor-isolated-protocols.md.

import Foundation

// MARK: - Fix 1: isolate the protocol itself

/// If every conformer is UI code, which is true of most delegate protocols in
/// an app target, isolate the protocol. Conformers then get `@MainActor` for
/// free and callers are forced to hop, which is what was happening informally
/// anyway.
@MainActor
public protocol DataSourceDelegate: AnyObject {
    func didUpdate(itemCount: Int)
}

@MainActor
public final class ListViewController: DataSourceDelegate {
    public private(set) var lastCount = 0

    public init() {}

    public func didUpdate(itemCount: Int) {
        lastCount = itemCount
    }
}

// MARK: - Fix 2: make the requirement async

/// When conformers genuinely live on different actors, the requirement has to
/// be `async` so each conformer can be isolated however it likes. Callers pay
/// an `await`, which is the accurate cost: they were always calling across a
/// boundary, the compiler just could not see it.
public protocol EventSink: Sendable {
    func record(_ event: String) async
}

public actor BufferedSink: EventSink {
    private var events: [String] = []

    public init() {}

    public func record(_ event: String) {
        events.append(event)
    }

    public func drain() -> [String] {
        defer { events.removeAll() }
        return events
    }
}

// MARK: - Fix 3: nonisolated, when the work needs no state

/// A requirement that touches no isolated state can be `nonisolated` even on
/// an isolated type. Worth checking for: it is the cheapest fix and it is
/// available more often than people expect.
@MainActor
public final class Formatter2: EventSink {
    public nonisolated let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public nonisolated func record(_ event: String) async {
        // Reads only `identifier`, which is immutable and sendable, so no
        // isolation is required at all.
        _ = "\(identifier): \(event)"
    }
}
