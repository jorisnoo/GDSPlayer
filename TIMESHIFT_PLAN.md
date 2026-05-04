# Time-shift the GDS.FM stream to the listener's local clock

## Context

GDS.FM broadcasts live from Zürich (Europe/Zurich, CET/CEST). For listeners in other timezones the schedule lands at the wrong hour — the morning show airs at 01:00 in California. The goal is to make the broadcast "follow the listener's clock" so a Zürich-morning show plays during the listener's morning regardless of where they are.

The chosen architecture: a dedicated server in a new repo records the Icecast stream into a rolling buffer and serves per-client time-shifted MP3 streams to every GDSPlayer client. No buffering happens on the listener's Mac. The Mac app's only change is picking a different stream URL based on the listener's timezone.

This is feasible: the upstream is plain Icecast 320 kbps MP3 (`Server: Icecast 2.4.0-kh15`, `Content-Type: audio/mpeg`, frame-aligned MP3 starting `0xFFFB`), so recording is just appending bytes and re-emitting them paced at 40 KB/s.

## Architecture

Two repos:

- **`gds-timeshift-server`** (new) — single Go binary. Maintains one upstream audio connection and a separate metadata poller. Segments the MP3 frame stream into 60-second files on disk; appends every unique track/show change to a time-indexed metadata log. Exposes paced HTTP MP3 endpoints **and** time-shifted `live-info-v2`-shaped metadata per timezone. Buffer depth ≥30h to span the global UTC+14 ↔ UTC−12 range.
- **`GDSPlayer`** (this repo) — adds a "Sync to my timezone" preference. When enabled, computes the listener's offset from Europe/Zurich and points `RadioPlayer` at the timeshift server for **both** the audio stream and the now-playing metadata, so the menubar tooltip / now-playing card matches what the listener is actually hearing. Everything else (recovery, NWPathMonitor reconnect, MPNowPlaying integration) reused unchanged.

## Server: `gds-timeshift-server`

### Stack
- Go 1.22+. One goroutine per client is the natural model; standard library covers HTTP + filesystem.
- `ffmpeg` as a child process for the ingest segmenter (`-c copy -f segment -segment_time 60`). Battle-tested, frame-aware, no need to roll our own MP3 frame parser.
- Deployment target: any Linux VM with ≥5 GB disk and stable bandwidth. ~40 KB/s per concurrent listener for egress.

### Components

1. **Ingester** — supervises a long-running `ffmpeg -i https://gdsfm.out.airtime.pro/gdsfm_a -c copy -f segment -segment_time 60 -strftime 1 seg-%s.mp3`. On exit (network drop, upstream reset) reconnects with exponential backoff capped at 30s. Mirrors the recovery logic we just shipped in `RadioPlayer.swift`. Logs every gap with start/end timestamps.

2. **Janitor** — every 60s, deletes segments older than 30h (`seg-<unix-seconds>.mp3` filename gives the wall-clock timestamp directly). Also prunes metadata log entries older than 30h.

3. **Metadata recorder** — independent goroutine, polls `https://gdsfm.airtime.pro/api/live-info-v2?timezone=utc` every 10s. On any change to `(shows.current.name, tracks.current.metadata.artist_name, tracks.current.metadata.track_title)`, appends a row to an in-memory ring `{ts: time.Time, payload: rawLiveInfoJSON}`. Persisted as a JSONL append-only file `metadata.log` for crash recovery. ~30h × 6 polls/min × ~10 changes/h ≈ a few hundred entries; no need for a database. The full upstream JSON is stored verbatim so the time-shifted endpoint can echo it back unmodified.

4. **`GET /stream?tz=<IANA>`** — handler:
   - Resolves the IANA name → current offset minutes from Europe/Zurich. DST is handled by Go's `time.LoadLocation` (so a Zürich listener crossing into CEST and a New York listener crossing into EDT both stay in sync without code changes).
   - Computes target wall-clock = `time.Now() - offset`.
   - Opens the segment containing that timestamp at the right byte position, then walks forward through segments concatenated as one MP3 frame stream.
   - Paces output: writes one MP3 frame per `1152 / 44100 ≈ 26ms` tick (or one second's worth of bytes per second of wall-clock — simpler and good enough). Without pacing the client would drain the buffer instantly and the time-shift would collapse.
   - Sends Icecast-style response headers (`Content-Type: audio/mpeg`, `Cache-Control: no-cache`, optional `icy-name`) so `AVPlayer` treats it identically to the upstream.

5. **`GET /stream?offset_minutes=<int>`** — same, but explicit offset for testing.

6. **`GET /live-info-v2?tz=<IANA>`** — time-shifted metadata. Resolves the offset, finds the latest metadata entry with `ts <= now() - offset`, and returns the stored upstream JSON verbatim so the existing client decoder works unchanged. If no entry exists yet (cold start), proxies the upstream `live-info-v2` so the client always gets a valid payload. Same query-param shape as `/stream`.

7. **`GET /live`** — proxy of the upstream Icecast stream. Same content the app uses today; gives us a single host for both modes and a fallback when the requested offset is beyond the buffer.

8. **`GET /health`** — JSON with: oldest segment timestamp, newest segment timestamp, segment count, ingest reconnect count, metadata entries count, current upstream-audio and upstream-metadata connections y/n. Used by external monitoring (Oh Dear, Flare).

### Edge cases
- **Buffer cold start**: for the first 30h after deploy, listeners requesting deep negative offsets hit segments that don't exist yet. Respond 503 with `Retry-After: 60`, or transparently fall through to `/live` (preferred for v1 — listener gets audio, just not yet shifted).
- **Upstream gap**: when the ingester is reconnecting, the ring has a hole that arrives at every offset stream eventually. Detect (segment timestamps non-contiguous) and either insert silence frames or skip the gap. v1: skip; document the discontinuity in `/health`.
- **Fractional timezones** (UTC+5:30, +9:30, etc.): the per-client cursor handles these naturally because the offset is computed in minutes, not hours.

## Client: `GDSPlayer`

### Files to change
- `GDSPlayer/Services/RadioPlayer.swift:31-32` — make both `streamURL` and `apiURL` computed instead of `let`. Reads `PreferencesManager.shared.syncToLocalTime` and `TimeZone.current` and returns either the upstream URLs or the timeshift-server URLs. Both must flip together so audio and metadata stay aligned.
- `GDSPlayer/Services/PreferencesManager.swift` — add `syncToLocalTime: Bool` (default false until the server is in production). Pattern matches existing `selectedMusicService` and `clickToPlay` properties.
- `GDSPlayer/GDSPlayerApp.swift:494-549` — extend the Settings submenu with a "Sync to my timezone" toggle item, modeled on the existing `clickToPlayItem` (line 531).

### URL construction
```
let identifier = TimeZone.current.identifier
let host = "https://timeshift.gds.fm"
streamURL = URL(string: "\(host)/stream?tz=\(identifier)")!
apiURL    = URL(string: "\(host)/live-info-v2?tz=\(identifier)")!
```
If `syncToLocalTime` is off or `TimeZone.current.identifier == "Europe/Zurich"`, fall back to the existing upstream URLs — no point routing Zürich listeners through the proxy.

### Reused machinery
- All the recovery work just added (`handleStreamFailure`, `scheduleReconnect`, `NWPathMonitor` in `RadioPlayer.swift`) keeps working unchanged. The timeshift server emits an Icecast-compatible MP3 stream, so `AVPlayer` treats it identically to the upstream.
- `Analytics.playbackStarted()` / `playbackStopped()` keep firing on user intent only (already separated from reconnect path in the recent refactor).
- `fetchTrackInfo()` (`RadioPlayer.swift:311`) keeps the same JSON shape and polling cadence; only the URL changes. `MPNowPlayingInfoCenter` updates inherit the corrected metadata for free.

### Toggle visibility & rollout
- Default off. Hidden behind a debug build flag until the server is reachable in production, so the App Store build doesn't ship a feature pointing at a non-existent host.

## Verification

### Server
- Local smoke test: run the binary, let it ingest for 90s, then `curl -o out.mp3 'http://localhost:8080/stream?offset_minutes=-1'` for 30s. `ffprobe out.mp3` should show ~30s of MP3 at 320 kbps.
- Pacing check: above curl should take ≈30s wall-clock, not <1s. If it returns instantly, pacing is broken.
- Concurrency: run 50 parallel curls at random offsets between -1m and -25h. CPU and disk read rate should stay flat; egress = 50 × 40 KB/s = 2 MB/s.
- Recovery: kill the upstream connection (e.g. block the host with pf), watch ingester logs for backoff reconnect, confirm `/health` reports the gap and resumes.
- Buffer aging: after 30h of uptime, oldest segment in `/health` should track ~30h behind newest, and the janitor should be deleting ~1 segment/minute.

### Client
- Build with toggle off → identical behavior to current main branch.
- Build with toggle on, change machine TZ to `America/Los_Angeles`, hit play → AVPlayer connects to `/stream?tz=America/Los_Angeles`. The audio heard at 09:00 PT should match what was airing on Zürich time 8 (or 9) hours earlier — sanity-check by comparing to the live track metadata around that wall-clock.
- Pull wifi mid-playback → recovery path reconnects to the timeshift server, not the upstream. Verify by inspecting `URLSession`/AVPlayer logs.
- Toggle on then off mid-playback → stream switches to live URL on next `play()`; verify by leaving the menu open and checking the track info update.
- Metadata correctness: with toggle on in a non-Zürich TZ, capture the menubar tooltip / now-playing card and the audio simultaneously. Confirm artist/title in the card matches the artist/title actually heard (within one polling interval). Then disable the toggle and confirm the card immediately resyncs to the live upstream metadata.

## Out of scope for v1
- Pause/resume with the time-shift cursor held still (would require per-session state and rate decoupling on the server).
- Show-picker UI driven by `airtime.pro/api/week-info`.
- Multi-region server failover.
