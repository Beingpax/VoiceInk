# Recorder redesign, Observation / Swift 6 migration, and an insights dashboard

This branch does three things that grew out of one another: it modernises the
codebase's concurrency and observation, rebuilds the recorder around a new
"ambient" surface, and turns the dashboard from a set of counters into something
that answers questions.

It is large — **215 files, ~10.6k lines** — and I would completely understand a
request to split it. A suggested split is at the bottom, along with the parts I
think are least defensible. Everything here builds clean, passes 155 tests, and
merges into `main` without conflicts as of `upstream/main` @ `dfe88ad`.

---

## 1. Observation and Swift 6 strict concurrency

`ObservableObject` / `@Published` → `@Observable` across 38 types, and strict
concurrency turned on.

This is the change with the widest blast radius and the least visible payoff, so
it is worth saying what it actually bought. Two crashes in this repo were
concurrency bugs that strict checking makes impossible to write:

- **`AudioDeviceManager` trapped on every audio device change.** A CoreAudio
  property listener fires on a HAL queue and called into main-actor state, which
  under Swift 6 is a hard trap rather than a race. Fixed by making the listener
  `nonisolated` and hopping explicitly.
- **A SwiftUI/AppKit teardown race** threw from
  `_postWindowNeedsUpdateConstraints` when a window was released while a
  `GraphHost` transaction was still queued.

Observation also removed a real performance problem — see §4.

Where the escape hatches are used they are commented with the reason.
`nonisolated(unsafe)` appears in exactly one place on purpose (`Task.cancel()`
from a `deinit`, which is documented safe from any thread).

## 2. Ambient recorder

A third recorder style alongside Mini and Notch, where **the display border is
the instrument** and there is no panel at all.

The governing rule is that the frame never says two things at once: an arbiter
picks the single most important state and the whole border says only that, so
there is no legend to learn. Colour carries *what*, thickness carries *how loud*.

- **The voice crest.** The waveform is folded into the top edge of the frame
  rather than floating under it, tracing the notch silhouette across the middle
  and settling to the depth of the side wash at the corners. Newest audio sits
  at the centre and older audio is pushed outward, so speech appears to be
  emitted by the hardware.
- **Processing replays the take.** While transcribing, the crest stops being a
  live meter and becomes the recording being read back, lit outward as work
  completes. Determinate when there is prediction history for the model,
  honestly indeterminate when there is not.
- **Two palettes.** A glow cannot be added to something already at full
  brightness, so the light-background scheme inverts the approach entirely:
  deeper colours, tighter blur, a contour that carries the shape. Colours were
  chosen by measured contrast, not by eye — see §5.
- **Click-through.** The window is display-sized, so it ignores mouse events by
  default and accepts them only while something is genuinely clickable.

## 3. Dashboard insights

The dashboard counted words, minutes and sessions. Those go up, and knowing they
went up changes nothing. Each insight added here exists because there is a
decision behind it.

| Insight | The decision it drives |
| --- | --- |
| Speaking pace | Turns the time-saved claim into arithmetic you can check |
| Wait, split by stage | Transcription and enhancement are the only two levers and need opposite fixes |
| Reliability | A model failing a fraction of takes is costing re-dictations invisibly |
| Enhancement impact | Whether the AI pass is earning its latency and cost |
| Re-dictation rate | The closest thing to accuracy available without asking the user |
| Where words land | Which apps deserve their own mode |

Presented as an overview of summary cards, each opening its own detail.

Three fields were added to `SessionMetric` to support this
(`targetBundleIdentifier`, `wasUndone`, `dictionaryHitCount`). All optional or
defaulted, so SwiftData migrates in place; existing rows carry nils and the UI
distinguishes "not measured" from "measured zero".

Two notes on the arithmetic, both of which are tested:

- Pace is total words over total seconds, not a mean of per-take rates — a
  two-word correction must not weigh the same as a five-minute dictation.
- Reliability excludes cancellations from the denominator. Abandoning a take is
  a decision, not a malfunction.

Nothing renders below a threshold of takes. A confident number computed from
three samples is worse than no number, because it teaches people to distrust the
rest of the screen.

## 4. Performance

Profiled with `sample` over live takes rather than estimated.

The ambient surface put **16.8% of one core** in the SwiftUI render path, of
which only 3.5% was drawing — **12.2% was `AG::Graph::UpdateStack::update`**,
SwiftUI walking its graph 30 times a second to rediscover that only the waveform
had moved. That is a scope problem: audio-rate state lived on the view that
builds the whole surface.

Moving it to an `@Observable` model read only by the leaf that draws it took
AttributeGraph to **5.7%**. It also removed a stall — before the change, 245
samples were the main thread blocked in `RB::SurfacePool::wait_image_queue`,
starved of render surfaces by redundant frames. Idle cost is zero.

Measured on a `-Onone` local build, so these are ceilings.

## 5. Tests

**17 lines of template → 155 tests.** They cover the pure logic, and they are
weighted toward the things that actually broke during development rather than
toward coverage:

- Input health thresholds, calibrated from logged hardware (a whisper peaks at
  0.41; room tone stays under 0.15).
- The density ratchet, the silence watch, the processing estimate.
- The ambient state/caption arbiter, which had two silent failures.
- Both colour palettes, held to **4.5:1 contrast** against their own background
  and **20 ΔE** separation under simulated deuteranopia. The light scheme was
  wrong twice before this test existed; it averaged 3.4:1 on white.
- Window lifecycle: a window told to go away must stay away, including past the
  watchdog's next tick.

`make test` runs them.

---

## Merge with upstream

`upstream/main` landed a license/keychain change while this was in flight;
fourteen files conflicted along the same seam. Upstream's semantics were kept
wholesale and re-expressed in this branch's idiom, never the reverse. Three
upstream additions needed adjusting to compile under strict concurrency (a
mutable static cache moved into an actor, a nonisolated `deinit`, a
non-`Sendable` `UserDefaults`). Details are in the merge commit.

## Reviewing this

Commits are self-contained and each explains *why* rather than what. Suggested
reading order:

1. `refactor: migrate to Observation and enable Swift 6 strict concurrency`
2. The ambient recorder commits (`AmbientRecorderView`, `AmbientVoiceCrest`,
   `AmbientPresentation`)
3. `perf(ambient): narrow render scope`
4. The dashboard insight commits

## What I would push back on myself

- **The size.** This should probably be three PRs: the Observation/Swift 6
  migration, the ambient recorder, and the dashboard. They are separable, and I
  am happy to split them.
- **The typing-speed comparison** uses a fixed 40 wpm yardstick. The speaking
  figure is measured; that one is not. It is labelled, but it is still a
  hardcoded constant in a screen otherwise built from real data.
- **Group 3 insights start from zero.** Destination, undo and dictionary data
  cannot be backfilled, so those cards are empty until new takes accumulate.
- **Ambient has no test coverage above the unit level.** The window lifecycle is
  tested; how the surface actually looks and behaves during a take is not, and
  most bugs found during development were visual and invisible to tests.
- **`RecorderUIManager` is still untestable** — it cannot be constructed without
  the engine, so the panel-teardown ordering that caused a real bug is verified
  by reading rather than by a test.
