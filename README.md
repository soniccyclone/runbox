# runbox

Compare recorded game runs side by side, at the same frame, and decide which one
is more fun.

A local service that indexes your prototype's runs, streams their clips, and holds
two of them frame-locked in a diff bay so a human can give a verdict. Built for
iterating on game feel, where the bottleneck is not writing code but judging it.

Engine agnostic. Nothing here knows what a game is. If your project can write a
JSON file and an mp4, it can drive this.

**[Live demo](https://soniccyclone.github.io/runbox/demo.html)** ·
**[Site](https://soniccyclone.github.io/runbox/)**

The demo is not a mock-up. It is a real export, produced by `export.ps1` from
three real runs, so it is the same artefact you get from your own.

---

## Install

**Windows only for now.** The service and gallery are portable; `install.ps1` and
the generated harness are not.

Two steps. The first puts the skill where your agent will read it:

```
npx github:soniccyclone/runbox init
```

It detects what the repo already uses, asks which agents to install for, and
writes to each one's own directory:

| agent | project | global |
|---|---|---|
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| Cursor | `.cursor/skills/` | `~/.cursor/skills/` |
| GitHub Copilot | `.github/skills/` | `~/.copilot/skills/` |
| opencode | `.opencode/skills/` | `~/.config/opencode/skills/` |

Pass `--agent claude --agent cursor` to skip the prompt, or `--global` to install
for every project at once. Rerunning is also the update path: it always writes the
current skills.

The second step wires the harness into the project whose runs you want to compare:

```powershell
cd <your-game>
.\.claude\skills\runbox\install.ps1 -Launch "godot --path {game}"
.\harness\serve.ps1
```

That writes a `harness\serve.ps1` wrapper, adds run output to your `.gitignore`,
and prints what your project still owes. It takes its target from your working
directory rather than from where the skill sits, so a `--global` install works the
same as a local one. It refuses to run inside this repo, because that would
install runbox into its own source.

Requires the .NET SDK (10.x, for file-based apps). `init` checks for it before
writing anything, because a skill whose service cannot start is worse than no
skill. ffmpeg is optional and only warned about: without it runs index fine and
simply have no video.

There is nothing to build. The service is a single `.cs` file with no project file,
and the gallery is two static assets beside it.

## What your project has to provide

```
.harness-out/<game>/<scenario>/<runId>/result.json
.harness-out/<game>/<scenario>/<runId>/clip.mp4      (optional)
```

```json
{
  "run_at": "2026-08-08T06:45:44Z",
  "frames": 112,
  "passed": true,
  "events": [
    { "frame": 22, "name": "jump", "x": 132.0, "y": 383.9 },
    { "frame": 53, "name": "land", "x": 270.7, "y": 383.9 }
  ]
}
```

That is the whole obligation. Event names are yours: markers, the legend and the
delta table are all derived from whatever kinds your runs contain, so `hit` and
`reload` work exactly as well as `jump` and `land`.

Full contract, including `claims`, `measure` and `counts`:
[skills/runbox/reference/run-contract.md](skills/runbox/reference/run-contract.md).

## The one hard requirement

**Runs must be deterministic.** Fixed tick, seeded generator, recorded input, all
three.

With them, frame N of two runs is the same moment of the same scenario, so any
difference you see was caused by the change under test. Without them the two runs
diverge because their inputs diverged, and a side-by-side is theatre that looks
exactly like evidence.

This is far cheaper to build in from the start than to retrofit.

## What you get

- **A carousel** of every run, newest first, with each run's clip as its cover.
- **A diff bay** holding two runs, played from one transport, seeking together.
- **Event markers** on the scrubber, per slot, clickable to jump both runs to that
  frame.
- **Deltas** between the two runs, signed B minus A, over whatever your project
  records.
- **Drift**: what a prototype claims about itself against what its runs measured.
- **Verdicts**: mark the run you preferred; it outlives restarts and regenerated
  output.
- **Launch**: start a prototype from the gallery, via a command template.
- **Export**: bake the current view into one self-contained file with the clips
  inline, for handing to someone who does not have the repo.

## Method

The tool is half of it. [skills/runbox/SKILL.md](skills/runbox/SKILL.md) carries
the method: change exactly one thing per run, measure rather than derive, never fit
a calibration constant, adapt content to measured capability and never the reverse,
and treat the human verdict as the one datum that cannot be regenerated.

Every one of those rules came from something that went wrong. The evidence is in
[skills/runbox/FINDINGS.md](skills/runbox/FINDINGS.md).

## Repository layout

Two audiences, and the directory boundary is what keeps them apart.

```
skills/runbox/     the payload, delivered whole into an agent's skills directory
  SKILL.md           the method, for an agent using runbox
  FINDINGS.md        the evidence behind the rules; ships on purpose
  install.ps1  reference/  tool/

bin/  src/          the deposit CLI: agent targets, toolchain gate, copy
site/              the published site: org sources, skin, demo runs
AGENTS.md          invariants and traps, for an agent developing runbox
test.ps1  tests/   the maintainer gate
```

`AGENTS.md` must never reach a consuming project: delivered there it is
instructions addressed to a different job, telling an agent how to maintain runbox
when it should be using it. `skills/` is the entire payload, so that cannot happen
by forgetting to update an exclusion list. A test asserts it.

## Developing runbox

```powershell
.\test.ps1
```

Forty self-contained integration tests. No game, no engine, no host project
required. CI runs them on `windows-latest` under Windows PowerShell 5.1, which is
deliberate: the traps recorded in `AGENTS.md` do not all reproduce on 7.

Read [AGENTS.md](AGENTS.md) first. It lists the invariants that look arbitrary and
are not, and the traps this codebase has already fallen into.

## Design in one line

Measurement is the authority, a derived constant is a claim, and the only thing a
machine cannot produce is whether it was fun.

## License

Apache 2.0. See [LICENSE](LICENSE).
