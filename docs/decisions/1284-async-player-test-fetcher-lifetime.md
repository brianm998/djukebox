# 1284: Test fixtures own the TrackFetcher; AsyncAudioPlayer stays weak

## Decision
`AsyncAudioPlayer.fetcher` stays `weak`. A test that builds a player keeps the
fetcher alive itself, through `FakeAudioPlayer.fetcherOwner`.

## Why
`TrackFetcher.queues` owns the player, so a strong reference back would keep both
alive forever. The failure was in the test fixture, not in production code.
