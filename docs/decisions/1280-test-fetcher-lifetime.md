# 1280: test fixtures keep the TrackFetcher alive

## Decision

- A test fixture that builds an `AsyncAudioPlayer` must keep its `TrackFetcher`
  alive for the whole test. The player only holds it weakly.
- `FakeAudioPlayer.retainedFetcher` does this; `AsyncAudioPlayer` is unchanged.

## Consequences

- A fixture that forgets this gets nil track lookups (`trackNotFound`, empty
  queues) rather than a clear error.
