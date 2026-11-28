# 1255: plays and skips go through a local outbox

## Decision

- Every play/skip is stored locally first, online or not, and removed only after
  the server accepts it. A crash or failed request during an upload loses nothing.
- Uploads are serial and in time order; a failure stops the drain.
- A non-2xx reply to `POST /history` counts as a failure.
- Retries are safe: the server's database ignores a duplicate
  (sha1, time, fully played) event.
- Clearing the audio cache keeps pending history.

## Consequences

- An entry the server always rejects would hold back the ones after it.
- There is no retry timer. A failed upload is retried at the next online
  play/skip or the next `Client` start.
