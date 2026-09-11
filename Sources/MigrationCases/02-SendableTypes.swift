// Case 02 — non-Sendable types crossing an isolation boundary
//
// The error:
//   error: capture of 'user' with non-Sendable type 'User' in a '@Sendable'
//   closure
//
// See Notes/02-sendable-types.md.

import Foundation

// MARK: - Fix 1: make the value actually sendable

/// A struct of sendable stored properties is `Sendable` automatically inside
/// its own module. The conformance is spelled out here because the type is
/// `public`: cross-module inference does not apply, and a public type that
/// callers cannot send is a source-breaking surprise later.
public struct User: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let joinedAt: Date

    public init(id: UUID, name: String, joinedAt: Date) {
        self.id = id
        self.name = name
        self.joinedAt = joinedAt
    }
}

// MARK: - Fix 2: a reference type that is genuinely immutable

/// A final class with only `let` properties of sendable type is safe to share,
/// and the compiler can verify that — no `@unchecked` required. Reaching for
/// `@unchecked Sendable` here is the most common unnecessary use of it.
public final class ImmutableSession: Sendable {
    public let token: String
    public let expiresAt: Date

    public init(token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }
}

// MARK: - Fix 3: don't send the object, send what you need from it

/// Often the closure needed two fields, not the whole object graph. Extracting
/// them before the boundary removes the problem instead of annotating around
/// it, and usually makes the code clearer besides.
public func summarise(users: [User]) async -> [String] {
    let names = users.map(\.name)          // [String] is Sendable
    return await withTaskGroup(of: String.self) { group in
        for name in names {
            group.addTask { name.uppercased() }
        }
        var result: [String] = []
        for await value in group {
            result.append(value)
        }
        return result.sorted()
    }
}
