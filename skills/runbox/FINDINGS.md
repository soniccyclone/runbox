# Findings

Why runbox is shaped the way it is. Every rule in `SKILL.md` traces to something
measured here.

This file exists because the rules do not look necessary from the outside. Without
the evidence, a reasonable person simplifies them away and reintroduces the bug.

Measurements come from the project runbox was built for: a Godot 4.7 platformer
prototype mill, 60Hz fixed tick, seeded RNG, input from recorded tapes.

---

## F1. A closed-form constant disagreed with the running game by 9.5%

`MaxJumpDistance` computed horizontal jump reach from a standard projectile
formula: `speed * (v/g + v/(g * fallMultiplier))`. It returned **126.6px**.

Measured from the run's own events, jump at frame 22 and landing at frame 53, the
game delivered **138.7px**.

The measurement was confirmed rather than assumed: 138.7px over 32 real ticks is
260.1 px/s, matching the configured speed of 260 exactly. The formula assumes
continuous motion; the engine integrates at a fixed tick and overshoots it.

**Cost:** the level sized its gaps as fractions of that constant, so its three
jumps were 0.50 / 0.66 / 0.80 of true reach while the source said 0.55 / 0.72 /
0.88. The level was easier than its own code claimed and nobody noticed. Reading
the code could not have revealed it.

**Rule:** measurement is the authority; a derived constant is a claim to be checked.

---

## F2. The drift is a fixed offset, not a ratio

Same tape at three jump strengths:

| run | claimed | measured | drift | absolute error |
|---|---|---|---|---|
| floaty | 104.6 | 117.0 | +11.9% | 12.4px |
| stock | 126.6 | 138.7 | +9.6% | 12.1px |
| poppy | 154.2 | 164.7 | +6.8% | 10.5px |

The percentage falls as the jump grows while the absolute error holds near 12px,
roughly 2.8 ticks of extra airtime regardless of strength. Consistent with a fixed
discretisation offset.

**Cost of getting this wrong:** a calibration constant fitted at `stock` would be
about 3 points wrong at `floaty` and 3 the other way at `poppy`, and would look
correct in whichever run it was fitted to.

**Rule:** report drift per run. Never emit a correction factor. A test greps for
`calibration` and `correctionFactor` and fails if either appears.

---

## F3. A respawn is indistinguishable from a landing

A jump that ended in a pit produced this event stream:

```
frame  61  jump    x=301
frame 116  death   x=539.33
frame 120  land    x=307.67   <- the respawn
```

Naive pairing matched the jump at 61 to the landing at 120 and reported **6.7px**
of jump reach.

Harmless in a report. Destructive once a tuner acts on measurements
unsupervised, because 6.7px would resize a level.

**Rule:** emit a distinct kind for anything the world did *to* the player, and have
anything pairing events abandon a span containing the abort event. Measuring
nothing is correct; measuring something wrong is not.

---

## F4. GIF is four times larger than the frames it encodes

Encoding 111 captured frames, 304KB of PNG:

| format | encode time | size | vs source |
|---|---|---|---|
| mp4 h264 | 0.14s | 15.9KB | 19.1x smaller |
| webm vp9 | 0.19s | 15.7KB | 19.3x smaller |
| **gif** | 0.16s | **1210KB** | **4x LARGER** |

GIF is 76x the mp4 for worse quality, and cannot be range-served, so it cannot be
seeked. Rejected outright.

**Consequence:** clips are cheap enough that showing motion by default costs
nothing. Capture of 111 frames took 3.7s wall including engine startup.

---

## F5. Embedding fits, which is not the same as being right

Base64 inflates a 16KB clip by 33% to 21.3KB. Against a 16MB self-contained page
that is roughly **771 clips**, so embedding everything into one file is viable at
any scale this will see.

It was initially chosen as the primary mechanism on that basis. That was wrong, and
the error is worth recording: *fitting* was mistaken for *being right*.

A page in a browser cannot start a process, so an embedded page can never launch a
prototype, which was a stated requirement. It also rebuilds entirely per run and
uploads unreleased work if published.

**Rule:** the local service is the daily surface. Embedding survives as an export,
for handing someone a copy.

---

## F6. Frame-lock is only meaningful because runs are deterministic

Fixed tick, seeded RNG, and input from a recorded tape. With all three, frame N of
two runs is the same moment of the same scenario, so any difference on screen is
attributable to the change under test.

Without them, two runs diverge because their inputs diverged, and a side-by-side
comparison is theatre that looks exactly like evidence.

**Rule:** determinism is a precondition, not a feature. Comparison across
scenarios is refused for the same reason: different tapes are different inputs.

---

## F7. Sparse captures desynchronised video from their own markers

`capture -Every 3` writes every third physics frame. Encoded at a fixed 30fps
while the client seeks by dividing frame number by the 60Hz tick rate, one second
of video was not one second of physics. Markers and playback drifted apart on every
sparse capture, and the failure looked like working software.

Fixed by deriving the encode rate from the capture stride. Verified: a 112 frame
run is 1.87s of physics and produces a 1.85s clip, agreeing within one stride.

**Worth noting for the browser-harness question:** a headless browser test would
probably not have caught this, because the mismatch sat between the encoder and the
seek arithmetic rather than in the DOM. What catches it is asserting that clip
duration equals frame count over tick rate. That is a cheap server-side check and a
better use of effort than driving a browser.

---

## F8. The first human verdict could not have been measured

Three runs shown side by side. Every automated check passed on all three, all had
zero deaths, and the measurements could separate them only by reach. Asked which
was better, the human picked the strongest jump immediately.

That judgment is the output the whole system exists to produce, and no amount of
telemetry generates it.

**Rule:** verdicts are first-class and stored outside reproducible output. Never
infer a preference from newest or best-measuring. An unmade judgment returns
nothing.

---

## F9. A test that depended on a bug expired when the bug was fixed

The tuner's tests implicitly relied on the prototype still being mis-tuned. The
moment the tuner corrected it for real, there was no drift left, the tuner
correctly did nothing, and the test failed for the best possible reason.

**Rule:** a test must create the condition it exercises. Do not lean on ambient
state that correct behaviour will remove.
