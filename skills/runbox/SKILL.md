---
name: runbox
description: REPL-driven game development where the feedback loop is a carousel of recorded runs compared side by side at the same frame. Use when iterating on gameplay feel, tuning a prototype, deciding which of several variants is fun, or setting up a project so gameplay changes can be judged without launching a build each time. Ships a local gallery service that indexes runs, streams clips, and holds two runs frame-locked for comparison.
---

# runbox

Iterate on gameplay by putting recorded runs beside each other at the same frame
and asking a human which one is better.

**Complements `necklace-spec`.** That skill REPLs over code to find out what the
system does. This one REPLs over *runs* to find out how the game feels. Same
discipline, different observable: there, the answer is a number the code returns;
here, it is a judgment only a person can make.

## What this is for

You can generate gameplay code far faster than anyone can evaluate it. The
bottleneck is not authoring, it is the human's judgment about whether something is
fun, and every iteration that makes them launch a build, play it, and try to
remember how the last one felt burns the one scarce resource in the room.

So the loop is: change one thing, capture a run, put it beside the previous run at
the same frame, and ask for a verdict.

Do not use this to decide whether code is *correct*. Correctness is what the test
gate is for, and a run that failed its checks is not a candidate for a taste
judgment.

## The precondition, and it is not optional

**Runs must be deterministic before any of this means anything.** Three things,
all three required:

- a fixed physics tick, not a variable delta
- a seeded generator, with the seed recorded in the run
- input from a recorded tape, not from a human hand

With all three, frame N of two runs is the same moment of the same scenario, so a
difference on screen was caused by the change under test. Without them,
side-by-side playback is theatre: the two runs diverge because the inputs
diverged, and every conclusion drawn from it is noise.

Build this first. Retrofitting determinism after a prototype exists is far worse
than having it from the start, and the whole method rests on it.

## The loop

1. **Establish a baseline.** One capture of the current build. Nothing to compare
   against means nothing to say.
2. **Change exactly one thing.** Two changes at once and the verdict cannot be
   attributed. This is the most common way the method gets wasted.
3. **Capture a run** through the same tape, with a clip.
4. **Open the gallery**, load the two runs into A and B, and look at the frames
   where their events diverge.
5. **Ask for a verdict**, in those words. Not "does this look right" but "which of
   these two do you prefer". A comparison is answerable; an absolute is not.
6. **Record the verdict against the run**, because it is the one datum here that
   cannot be regenerated.

Then repeat. The carousel is a timeline, so the sequence of what changed and when
stays readable without anyone maintaining notes.

## Measurement is the authority; a derived constant is a claim

A prototype declares what it believes about itself. The run measures the same
quantity from its own events. When they disagree, **the run is right**.

This is not hypothetical. In the project this tool was built for, a closed-form
formula computed a jump reach of 126.6px while the running game delivered 138.7px,
because the formula assumes continuous motion and the engine integrates at a fixed
tick. The level's gaps had been sized off the formula, so it was measurably easier
than its own source code claimed and nobody had noticed. Reading the code could not
have revealed it.

Two rules follow, and both have teeth:

**Never fit a calibration constant.** Across three settings that drift ran +11.9%,
+9.6% and +6.8% while the absolute error held near 12px. It was a fixed
discretisation offset, not a ratio, so a constant fitted at one setting is wrong at
every other. Report drift per run and let content be recomputed from the
measurement.

**Adapt content to measured capability, never capability to content.** Resizing
what the game asks of the player converges, because changing a gap does not change
how far anyone can jump. Retuning the player to fit existing content does not
converge, because every correction moves the quantity being measured. A tuner that
edits the controller will oscillate across runs and look like it is working.

## Events are the measurement surface

Everything downstream reads the event stream, so **distinguish event kinds that
mean different things** even when they look identical.

The concrete trap: a respawn puts the player back on the ground, which emits a
landing indistinguishable from a real one. Pairing a jump with the next landing
across a death produced a "jump reach" of 6.7px. Harmless in a report; with a
tuner applying changes unsupervised, that number resizes a level.

Emit a distinct kind for anything the world did *to* the player, and have anything
that pairs events abandon a sequence containing one.

## Installing into a repo

Copy this whole skill directory into the target repo's `.claude/skills/`. Then:

```powershell
.\.claude\skills\runbox\install.ps1
```

It writes a `harness\serve.ps1` wrapper, checks for ffmpeg, and prints what the
project still has to provide. Nothing else is needed: the service is a .NET
file-based app with no project file, and the gallery is two static assets beside it.

The project's only obligation is to write run output in the shape described in
[reference/run-contract.md](reference/run-contract.md). That contract is engine
agnostic. Anything that can write a JSON file and an mp4 can drive this.

## Driving it

```powershell
dotnet run .claude\skills\runbox\tool\serve.cs -- --port 7777 --root .
dotnet run .claude\skills\runbox\tool\serve.cs -- --port 7777 --root . --launch "godot --path {game}"
.\.claude\skills\runbox\tool\export.ps1 -Game <name>
```

`--launch` is a command template with `{game}` standing for the prototype's
directory, so the launch button works with any engine. Omitted, it looks for Godot.

`export.ps1` bakes the current view into a single self-contained file with the
clips inline, for handing to someone who does not have the repo. Roughly 771 clips
fit inside a 16MB page, so the ceiling is not a practical concern. That is an
export, not the daily surface: a page in a browser cannot start a process, so it
can never launch anything.

## What not to do

- **Do not ask for a verdict on one run.** Taste needs a comparison. One run in
  isolation gets you "seems fine", which is worth nothing.
- **Do not vary two things between runs.** The verdict becomes unattributable and
  the run history stops being evidence.
- **Do not compare across scenarios.** Different tapes are different inputs, so
  frame-locking them is meaningless. The tool refuses this; do not work around it.
- **Do not invent a preference.** If nobody marked a run, there is no preferred
  run. Never fall back to the newest or the best-measuring one.
- **Do not put verdicts in reproducible output.** Every measurement can be
  recomputed by re-running. A human judgment cannot, and run output directories get
  deleted routinely.
- **Do not encode clips at a fixed frame rate** when capturing every Nth frame.
  Derive the rate from the capture stride, or video time stops matching physics
  time and frame-locked comparison is quietly wrong while looking fine.
