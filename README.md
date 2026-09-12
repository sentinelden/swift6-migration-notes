# swift6-migration-notes

> Real Swift 6 strict-concurrency migration cases, from migrating twelve production SDKs. Every fix here compiles under Swift 6 language mode, so none of it can quietly go stale.

[![CI](https://github.com/sentinelden/swift6-migration-notes/actions/workflows/ci.yml/badge.svg)](https://github.com/sentinelden/swift6-migration-notes/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Swift 6.0+](https://img.shields.io/badge/swift-6.0+-orange.svg)](https://swift.org)

## Why this exists

Concurrency advice rots faster than almost any other documentation. Diagnostics change between toolchains, and guidance that was right in 5.10 becomes wrong without anyone noticing, which is how a blog post from two years ago talks you into `@unchecked Sendable` on a type that would now be `Sendable` for free.

So every fix in these notes has a **compiled counterpart** in [`Sources/MigrationCases/`](Sources/MigrationCases/), built under Swift 6 language mode with full strict concurrency. CI fails the day an example stops being true. Where a note makes a claim about *runtime behaviour* (that an actor is not a serial queue, that a bare continuation ignores cancellation), there is a test demonstrating it.

## The cases

| | Case | The error, or the trap |
| --- | --- | --- |
| 01 | [Global mutable state](Notes/01-global-mutable-state.md) | `global variable is not concurrency-safe` |
| 02 | [Non-Sendable types](Notes/02-sendable-types.md) | `capture of 'x' with non-Sendable type` |
| 03 | [Actor-isolated protocols](Notes/03-actor-isolated-protocols.md) | `cannot be used to satisfy nonisolated requirement` |
| 04 | [Capturing self in a Task](Notes/04-task-capture.md) | Compiles, then reorders your program |
| 05 | [Serial queue → actor](Notes/05-queue-to-actor.md) | Actors are reentrant. Queues are not. |
| 06 | [Bridging completion handlers](Notes/06-continuation-bridging.md) | Continuations ignore cancellation |
| 07 | [`@unchecked Sendable`](Notes/07-unchecked-sendable.md) | When it is a fact, when it is a wish |
| 08 | [`deinit` and isolation](Notes/08-deinit-and-isolation.md) | `deinit` is never isolated, on any type |

Each note follows the same shape: the diagnostic, why the compiler is right, the fixes in the order worth trying, the escape hatch and why it is a trap, and what actually changes at runtime.

## The three that cost the most

If you read only part of this, read these: they are the ones where the code compiles and the behaviour changed.

**[05, actors are reentrant.](Notes/05-queue-to-actor.md)** An actor releases isolation at every `await`. A check-then-act that a serial queue made atomic is no longer atomic. Ten concurrent callers all miss the cache and all fetch. There is a test in this repo demonstrating exactly that, and the fix.

**[04, `Task {}` inherits isolation but not ordering.](Notes/04-task-capture.md)** Code that relied on a serial queue for sequencing compiles clean and runs out of order. No error, no warning, only shows up under load.

**[06, continuations do not observe cancellation.](Notes/06-continuation-bridging.md)** The obvious wrapper produces a task that ignores `cancel()` and hangs forever. `withTaskCancellationHandler` is necessary but not sufficient: cancellation and completion race, so a single-resume guard is required.

## Running it

```sh
swift build     # every example, Swift 6 language mode, strict concurrency
swift test      # 16 tests, including the reentrancy and cancellation demonstrations
```

Requires Swift 6.0 or later.

## The order that made migration tractable

Doing this across twelve SDKs, the sequence that worked:

1. **Turn on strict concurrency as a warning first** (`-strict-concurrency=complete` in Swift 5 mode). Get the full error count before changing the language mode. It is going to be large; seeing it is better than discovering it.
2. **Fix leaves first, not the app.** Modules with no dependencies migrate cleanly. Migrating the app first means fighting diagnostics that come from code you have not touched yet.
3. **Sort by fix category, not by file.** Every `let`-not-`var` global is the same five-second edit. Batching them clears a surprising fraction of the count and leaves the genuinely hard cases visible.
4. **Do `@unchecked Sendable` last, and audit it.** It is available from day one, which is the problem. `grep -rn "@unchecked Sendable"` at the end and justify each one, or you will have shipped a migration that only silenced the compiler.
5. **Treat every new `await` as a behaviour change.** Most are harmless. The ones that are not will be in check-then-act code and in anything that depended on ordering.

## Contributing

Cases welcome, with the same shape: a real diagnostic you hit, a compiled fix, and (where it makes a claim about runtime behaviour) a test that demonstrates it. Prose without a compiled counterpart is what this repository exists to avoid.

Under-covered: `AsyncSequence` conformances, `@preconcurrency import` and when to remove it, isolated deinit in Swift 6.1+, and distributed actors.

## License

MIT. See [`LICENSE`](LICENSE).

## Who writes this

[Sentinel Den](https://sentinelden.com), iOS security research and runtime-defense SDKs from Vancouver, BC. These notes came out of migrating our own SDKs to Swift 6, twelve times over, and wishing someone had written them down first.
