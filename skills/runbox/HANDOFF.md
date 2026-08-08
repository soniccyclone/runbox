# Handoff: standing runbox up as its own repository

For the agent maintaining the runbox repo. Written by the agent that built it, in
the project it was extracted from. Everything below is either done, or a task with
the reasoning attached.

Delete this file once the repo is established. It describes a transition, not a
steady state, and stale transition docs are worse than none.

---

## Where this came from

runbox was built inside a Godot prototype mill to solve one problem: gameplay code
can be generated far faster than anyone can judge whether it is fun, so the
bottleneck is a human's attention, not authoring. The tool exists to spend that
attention well.

It was then made engine-agnostic and verified against a synthetic non-Godot project
emitting `hit` / `reload` / `wave_cleared`. Nothing in the tool knows what a game is.

**Read `FINDINGS.md` before changing anything.** Nine findings, each tied to a rule
that looks arbitrary without it. That file is the reason the rules survive contact
with a reasonable person trying to simplify them.

## What already exists and works

- **The tool**: `tool/serve.cs` (a .NET file-based app, no csproj), `tool/gallery/`
  (two static assets), `tool/export.ps1`.
- **25 self-contained integration tests**, `.\test.ps1`. Every case builds its own
  run tree in a temp directory. No game, no engine, nothing installed but the .NET
  SDK. A committed 7KB fixture clip means ffmpeg is not needed to run them.
- **Docs**: `SKILL.md` (method, for a using agent), `AGENTS.md` (invariants and
  traps, for you), `FINDINGS.md` (evidence), `README.md` (front door),
  `reference/run-contract.md` (what host projects must write).
- **`install.ps1`**: wires runbox into a consuming repo.
- **`package.ps1`**: stages the deliverable, excluding the workshop. Verified: 8
  files, 87KB, and it throws if a workshop file leaks in.

Both gates were green at handoff: 25 runbox tests, plus 29 harness tests and a
clean gameplay run in the host project.

---

## The split, and why it is not housekeeping

Claude Code discovers skills at `.claude/skills/<name>/SKILL.md`. That path is
fixed, so the **installed** shape cannot also be the **repo** shape without
dragging the maintainer's half into every project that installs the skill.

Two audiences, two sets of files:

| ships | stays in this repo |
|---|---|
| `SKILL.md` | `AGENTS.md` |
| `FINDINGS.md` | `README.md` |
| `install.ps1` | `test.ps1`, `tests/` |
| `reference/` | `package.ps1` |
| `tool/` | `LICENSE`, CI config |

**`AGENTS.md` must never ship.** Installed into a game repo it is instructions
addressed to a different job, telling an agent how to maintain runbox when it
should be using it. That is the failure this split exists to prevent, and it is why
`package.ps1` names its exclusions explicitly rather than inferring them: adding a
workshop file should never silently ship it.

**`FINDINGS.md` ships on purpose.** The rules in `SKILL.md` read as arbitrary
without their evidence. A using agent that cannot see why "never emit a calibration
constant" exists will eventually fit one.

## Layout

Flat. Deliverable files at the repo root alongside the workshop:

```
runbox/
  README.md  LICENSE  AGENTS.md  FINDINGS.md
  test.ps1  tests/  package.ps1
  SKILL.md  install.ps1  reference/  tool/
```

Do not nest the deliverable under `skill/`. The existing paths already assume flat:
`tests/_lib.ps1` resolves the tool as `../tool`, and `tool/serve.cs` finds its
gallery assets beside itself via `CallerFilePath`. Nesting means editing both for
no gain.

---

## Tasks

### 1. `install.ps1` should write `.gitignore`, not warn about it

It currently prints "add to .gitignore" and moves on. It should append
`.harness-out/` and `.harness-verdicts.json` when absent. That is the difference
between a clean install and a consumer's first commit full of run output.

### 2. Guard `install.ps1` against being run in this repo

`Get-RepoRoot` walks up to `.git`. Run inside runbox itself it finds runbox's own
root and installs into the source. Refuse when the resolved root contains
`SKILL.md` at its top level, with a message saying the installer belongs in the
target project.

### 3. CI

GitHub Actions, `windows-latest`, running `.\test.ps1`. The suite needs only the
.NET SDK, so this is cheap and it is what keeps the invariants from rotting. The
tests bind to ports in the 7900 range; if the runner is noisy, take the port from
an environment variable in `tests/_lib.ps1`.

PowerShell 5.1 versus 7 matters here. The traps in `AGENTS.md` were found on 5.1,
which is what Windows ships. If CI runs `pwsh`, some will not reproduce and the
suite will pass on a machine users cannot match. Pin `shell: powershell` for at
least one job.

### 4. `NOTICE`

Conventional alongside Apache 2.0. Optional.

### 5. Decide about the browser harness, once

The playback layer is JavaScript and is deliberately untested; the data layer is
tested instead. That decision is recorded in `AGENTS.md` under deliberately absent,
and F7 in `FINDINGS.md` is the one frame-lock bug found in practice, which a DOM
test would also have missed because it sat between the encoder and the seek
arithmetic.

There is an open manual smoke test in the originating project. If it turns up bugs
a harness would have caught, that is the evidence to build one, and those bugs are
its first cases. If it turns up nothing, record that and stop revisiting it.

---

## Verifying you have not broken anything

```powershell
.\test.ps1                    # 25, all green
.\package.ps1                 # 8 files, throws if a workshop file leaks
```

Then the end-to-end check that actually matters, because it is the one that caught
two real defects while the tests were being written:

1. `git init` a throwaway directory.
2. Copy `dist/runbox` into `<throwaway>/.claude/skills/runbox`.
3. Run `install.ps1` there.
4. Write two runs by hand per `reference/run-contract.md`, using event names from
   a genre that is **not** a platformer.
5. Start the service and confirm the delta rows come back named after *those*
   events.

If step 5 shows `jump` or `land`, something has been hardcoded back in.

## The invariants, in one line each

Full reasoning in `AGENTS.md`; evidence in `FINDINGS.md`.

- Path containment compares resolved paths, never inspects the string for `..`.
- Launch validates against the real directory listing, never by cleaning a name.
- Drift is per run; no correction factor is ever emitted.
- A span containing its abort event measures nothing, not something wrong.
- Comparison across scenarios is refused.
- Verdicts live outside the run tree.
- A first run reports no delta, not zero.
- Nothing uploads anything, ever.
