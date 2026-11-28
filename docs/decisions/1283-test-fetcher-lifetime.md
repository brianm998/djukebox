# 1283: Test fixtures own the TrackFetcher their players hold weakly

## Decision
- A test fixture that builds an `AsyncAudioPlayer` or `HistoryFetcher` keeps a
  strong reference to its `TrackFetcher` for as long as the test uses them
  (`FakeAudioPlayer.fetcherOwner`).
- `AsyncAudioPlayer.fetcher` and `HistoryFetcher.trackFetcher` stay `weak`.

## Why
In the app `TrackFetcher.queues` owns the player, which holds the history
fetcher. Strong references back would be a retain cycle.
