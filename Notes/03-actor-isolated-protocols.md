# 03: Protocol conformance across isolation

```
error: main actor-isolated instance method 'didUpdate' cannot be used to
satisfy nonisolated requirement from protocol 'DataSourceDelegate'
```

The most disruptive error in a real migration, because it appears in every delegate protocol written before 2021 and the fix is not local: it changes the protocol's contract, so it ripples to every conformer and caller.

## Why the compiler is right

A nonisolated requirement promises "callable from anywhere." A `@MainActor` method cannot keep that promise. The protocol was making a guarantee its conformers could not honour.

## The fixes

**1. Isolate the protocol.** If every conformer is UI code (true of most app-target delegate protocols) put `@MainActor` on the protocol. Conformers inherit it; callers are forced to hop, which is what was happening informally anyway.

**2. Make the requirement `async`.** When conformers genuinely live on different actors, this lets each one be isolated however it likes. Callers pay an `await`: the accurate cost of a boundary they were already crossing.

**3. Make the member `nonisolated`.** Available more often than people expect: a requirement that touches no isolated state needs no isolation. Cheapest fix; check for it first.

## The escape hatch and why it is a trap

Sprinkling `assumeIsolated` or `MainActor.assumeIsolated` at conformance sites converts a compile-time guarantee into a runtime trap. It is correct only where you can prove the caller is already on that actor, and if you can prove it, option 1 usually expresses it better.

## What changes at runtime

Option 1: callers off the main actor now suspend. Option 2: same. Option 3: nothing.

Watch for delegate callbacks that used to fire synchronously and now land a turn later. Code that read state immediately after invoking a delegate may now read it before the delegate ran.

→ Compiled examples: [`03-ActorIsolatedProtocols.swift`](../Sources/MigrationCases/03-ActorIsolatedProtocols.swift)
