# 02 — Non-Sendable types crossing an isolation boundary

```
error: capture of 'user' with non-Sendable type 'User' in a '@Sendable' closure
```

## Why the compiler is right

`Sendable` means "safe to hand to another isolation domain." A class with mutable state is not, because two domains could mutate it at once. A struct of sendable parts is, because each domain gets its own copy.

## The fixes

**1. Make the value actually sendable.** A struct whose stored properties are all `Sendable` conforms automatically *within its own module*. Across modules, inference does not apply — so declare the conformance explicitly on public types, or callers get a type they cannot send and you get a source-breaking change later when you add it.

**2. A `final class` with only `let` properties.** This is `Sendable` and the compiler can verify it — no `@unchecked` needed. This is the most common unnecessary use of `@unchecked Sendable`.

**3. Don't send the object; send what you need from it.** Often the closure wanted two fields, not the object graph. Extracting them before the boundary removes the problem rather than annotating around it, and usually reads better.

```swift
let names = users.map(\.name)   // [String] is Sendable
```

## The escape hatch and why it is a trap

`@unchecked Sendable` on the class makes the error go away and keeps the race. See [07](07-unchecked-sendable.md) for when it is honest.

## What changes at runtime

Option 1 and 2: nothing. Option 3: you may copy a little more, and you stop retaining an object graph across a suspension point — usually a win.

→ Compiled examples: [`02-SendableTypes.swift`](../Sources/MigrationCases/02-SendableTypes.swift)
