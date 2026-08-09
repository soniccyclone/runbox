# The run contract

Everything runbox needs from a project. Engine agnostic: anything that can write a
JSON file and an mp4 can drive this.

## Layout

```
.harness-out/<game>/<scenario>/<runId>/result.json
.harness-out/<game>/<scenario>/<runId>/clip.mp4      (optional)
```

The `<runId>` level is load-bearing and is the part people leave out. A scenario
has a *history*: one run says whether the prototype works, two say whether a change
helped, and the second question is the one that drives tuning. A flat scenario
directory can only ever hold the latest run.

Use a sortable id (`yyyyMMdd-HHmmssfff` works), but never rely on it for ordering.
Ordering comes from `run_at`.

A directory holding frames but no `result.json` is a run that never finished
writing. It is skipped, not reported as an error, because a capture still in
flight is normal and must not break browsing.

## result.json

```json
{
  "scenario": "jump",
  "label":    "stock",
  "run_at":   "2026-08-08T06:45:44.3241070Z",
  "frames":   112,
  "capture_stride": 1,
  "passed":   true,
  "reason":   "tape exhausted",
  "checks":   [ { "name": "left_the_ground", "ok": true, "detail": "jumps=1" } ],
  "counts":   { "jump": 1, "land": 2 },
  "claims":   { "reach": 138.7 },
  "events":   [
    { "frame": 9,  "name": "land", "x": 80.0,   "y": 383.93 },
    { "frame": 22, "name": "jump", "x": 132.0,  "y": 383.93 },
    { "frame": 53, "name": "land", "x": 270.67, "y": 383.93 }
  ]
}
```

| field | required | meaning |
|---|---|---|
| `run_at` | yes | ISO-8601 UTC. The ordering key. Falls back to file mtime if absent, which is worse. |
| `frames` | yes | Physics ticks the run lasted. Marker positions are `frame / frames`. |
| `passed` | yes | Whether every check passed. A failed run is not a candidate for a taste verdict. |
| `events` | yes | The measurement surface. See below. |
| `label` | no | Short human name for the run. Defaults to `<game> / <scenario>`. |
| `capture_stride` | no | Physics ticks between captured frames. Defaults to `1`. |
| `claims` | no | What the prototype believes about itself. Compared against measurement to produce drift. |
| `counts` | no | Convenience tallies. Deltas are computed from `events`, not from these. |
| `checks` | no | Per-check detail, shown on the card. |
| `reason` | no | Why the run ended. |

## label

Write one if you want to be able to talk about a run.

Runs were originally identified by timestamp, and the timestamp never appeared in
the interface. An agent directing a comparison could not name a run the operator
could see, which made the whole verdict step awkward for a reason that had nothing
to do with the game. Nothing was broken; it was merely unusable, and no automated
test of any kind would have found it.

Keep it short and say what changed: `floaty`, `poppy`, `stock+coyote`. It is what
the card and the diff bay slots are titled.

## capture_stride

Physics ticks between captured frames. Write it whenever it is not 1.

The client steps the video by the largest stride among the loaded runs, so a run
that captured every 3rd tick steps 3 ticks at a time and lands on a frame that
actually exists. Omit it on a sparse capture and the step button advances one tick
into a frame that was never recorded, so the picture does not change and the tool
looks broken while the simulation is fine.

This is the same quantity that sets the encode rate. See **clips** below: get the
two out of agreement and video time stops matching physics time.

**Capturing every frame is the better default.** At roughly 16KB a clip, sparse
capture buys nothing worth the failure mode.

## events

One object per recorded moment: `frame`, `name`, and optionally `x` / `y`.

Event **names are yours**. The tool derives markers, legend entries, and delta rows
from whatever kinds appear in the loaded runs, so a shooter emitting `hit` and
`reload` works exactly as well as a platformer emitting `jump` and `land`. Only
`note` is ignored.

Two rules that matter more than they look:

**Give a distinct name to anything the world did *to* the player.** A respawn puts
the player on the ground and looks exactly like a landing. Pairing a jump with the
next landing across a death yielded a 6.7px "jump reach" in practice, which is
harmless in a report and destructive when a tuner acts on it.

**Record positions if you want reach measured.** Reach is the x-distance between a
start event and the end event that concluded it, skipping any sequence containing a
death.

## measure

Optional. Declares which pair of events bounds the quantity you want measured, so
the tool does not have to know your genre.

```json
"measure": { "from": "fire", "to": "impact", "abortOn": "reload", "axis": "x" }
```

| field | default | meaning |
|---|---|---|
| `from` | `jump` | event that opens the span |
| `to` | `land` | event that closes it |
| `abortOn` | `death` | event meaning the span never completed |
| `axis` | `x` | which recorded coordinate to difference |

Omit it entirely and you get the platformer defaults, which is why existing
platformer runs keep measuring without change. A project whose events are `hit`
and `reload` gets `measured: null` until it declares one, and everything else in
the gallery still works.

## claims

A claim is a derived constant the prototype uses to shape content, recorded so it
can be checked. `claims.reach` is the one the built-in drift endpoint compares
against measured reach.

The point is that a claim is *not trusted*. In the project this came from, a
closed-form jump formula claimed 126.6px while the game delivered 138.7px, and the
level had been sized off the claim.

## clips

`clip.mp4`, h264, beside `result.json`. Optional; runs without one show as cards
with no video and still participate in comparison and drift.

**Encode at `tickRate / captureStride`.** If you capture every 3rd frame of a 60Hz
sim, encode at 20fps. The client seeks by dividing frame number by tick rate, so a
fixed encode rate desynchronises video from its own event markers on every sparse
capture, and the failure looks like working software.

Sanity check: clip duration should equal `frames / tickRate` within one stride.

## Verdicts

Stored by the service outside the run output tree, keyed by
`<game>/<scenario>/<runId>`. Nothing for the project to implement, but do not put
run output anywhere a verdict store would be deleted with it. Every measurement can
be recomputed by re-running; a human judgment cannot.
