# 06 — Bridging completion handlers

```
error: passing closure as a 'sending' parameter risks causing data races
```

## The straightforward part

`withCheckedThrowingContinuation` is the right tool. Use the **checked** variant in production, not just in debug: it traps on double-resume and warns on a leaked continuation, and both are easy to introduce when converting a callback with several exit paths. The unchecked variant saves an allocation and costs you the diagnostic that finds the bug.

## The part every example omits

**A continuation does not observe cancellation.** The obvious wrapper produces a task that ignores `cancel()` and never completes. Not a leak — a hang. It will not surface until something upstream starts cancelling, which is usually a `SwiftUI` `.task` modifier on a view someone scrolled away from.

`withTaskCancellationHandler` is necessary but not sufficient, because **cancellation and completion race**:

- The legacy callback can fire at the same moment `onCancel` runs. Resuming a checked continuation twice is a hard trap.
- Cancellation can arrive *before* the continuation is installed, leaving a continuation nobody ever resumes.

Both paths need to go through one lock-protected slot, where the first to arrive wins and the second is dropped. That is roughly thirty lines, and it is why "just wrap it in a continuation" is bad advice for a cancellable API.

## On `Result<T, any Error>`

It is not `Sendable`, because `any Error` is not. Two ways out:

- `sending` on the parameter — the caller gives up its copy at the call.
- Constrain the failure to `Error & Sendable` — better when you control the legacy API's error type.

→ Compiled example including the single-resume guard: [`06-ContinuationBridging.swift`](../Sources/MigrationCases/06-ContinuationBridging.swift)
