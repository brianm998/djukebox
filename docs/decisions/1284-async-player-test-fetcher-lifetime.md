# 1284: Tests keep the TrackFetcher alive; AsyncAudioPlayer stays weak

## Decision
`AsyncAudioPlayer.fetcher` stays `weak`. A test that builds a player keeps the
fetcher alive itself: `makePlayer` returns it and the test holds it with
`withExtendedLifetime`.

## Why
`TrackFetcher.queues` owns the player, so a strong reference back would keep both
alive forever. The failure was in the test fixture, not in production code. Task
#1321 had already landed this fix, so a second owner on `FakeAudioPlayer` was
not added.
