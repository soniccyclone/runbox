# Working on runbox itself

> **Scope: the runbox repository only.**
>
> This file governs an agent developing runbox. It lives at the repo root, outside
> `skills/runbox/`, so it is **not** installed into projects that consume the
> skill. If you are reading this inside a game project, something copied more than
> the deliverable and you should ignore this file entirely.

Instructions for an agent **maintaining** runbox. If you are *using* runbox to
iterate on a game, read `SKILL.md` instead; this file will mislead you.

Those are two different jobs and they want different things. A user of the skill
needs the method. A maintainer needs to know which parts look arbitrary and are
load-bearing, which traps this codebase has already fallen into, and what is
deliberately absent.

## Test before you believe anything

```powershell
.\test.ps1                 # all of it
.\test.ps1 -Area Analysis  # one file
.\test.ps1 -Name '*drift*' # one case
```

Thirty-four integration tests, self-contained. Every case builds its own run tree
in a temp directory and points the service at it with `--out`, so the suite runs
in this repo with no game, no engine, and nothing installed but .NET.

**If a test needs a host project, it is in the wrong repo.** A host repo tests its
integration with runbox. This tests runbox.

The suite is the specification. `skills/runbox/reference/run-contract.md` describes
the contract in prose, but the tests are what actually holds it.

CI runs the same suite on `windows-latest` pinned to `shell: powershell`. That pin
is load-bearing: Windows PowerShell 5.1 is what Windows ships, and several traps
below do not reproduce under 7. A suite green only on `pwsh` is green on a machine
users do not have.

## Layout: the deliverable and the workshop

Two audiences, kept apart by where files live rather than by a list someone has to
remember to update.

```
.claude-plugin/    plugin.json and marketplace.json. The repo root is the plugin.

skills/runbox/     ships. Copied whole into <project>/.claude/skills/runbox
  SKILL.md  FINDINGS.md  install.ps1  reference/  tool/

AGENTS.md          stays. So do README.md, test.ps1, tests/, .github/
```

Claude Code discovers skills at `.claude/skills/<name>/SKILL.md`, so the installed
shape is fixed. Putting the deliverable in its own directory makes the installed
shape a subtree of the repo shape, and the separation survives someone adding a
file without thinking about packaging.

**A plugin install copies the whole repo into the plugin cache**, workshop and
all, so `AGENTS.md` is present on disk there. It is not *loaded*: only `skills/`,
`agents/`, `commands/` and hooks are components, and `claude plugin details`
reports one skill and nothing else. The directory split is still what keeps this
file out of a project that copied the skill in, which is the case that matters.

Verify packaging changes with the real tool rather than by reading the manifests:

```powershell
claude plugin validate .claude-plugin/plugin.json
claude plugin validate .claude-plugin/marketplace.json
claude plugin marketplace add ./   # then install, check details, then remove
```

`FINDINGS.md` ships on purpose. The rules in `SKILL.md` read as arbitrary without
their evidence, and an agent that cannot see why "never emit a calibration
constant" exists will eventually fit one.

**Anything new goes at the root unless a consuming project needs it at runtime.**
When adding to `skills/runbox/`, ask whether it makes sense to an agent who has
only that directory and a game.

## Invariants. Do not relax these without evidence

Each of these looks like it could be simplified. Each has a real incident behind
it, recorded in `FINDINGS.md`.

**Path containment compares resolved paths, never inspects the string for `..`.**
Encoded and mixed-separator forms defeat string inspection. The clip route is the
only path between an HTTP request and the filesystem.

**Launch validates against the real directory listing, not by cleaning the name.**
That route is the only place this service executes anything. Sanitising is a
guessing game; an enumeration is not.

**Drift is reported per run and no correction factor is ever emitted.** Measured
across three settings it ran +11.9%, +9.6%, +6.8% while the absolute error held
near 12px. It is a fixed offset, so a constant fitted at one setting is wrong
everywhere else. A test greps the response for `calibration` and `correctionFactor`
and fails if either appears. That test is not paranoia.

**A span containing its abort event measures nothing, rather than something wrong.**
Pairing across a death reported 6.7px of "jump reach" in the field. Harmless in a
report, destructive when a tuner acts on it.

**Comparison across scenarios is refused.** Different tapes are different inputs,
so frame-locking them is meaningless. Do not add a "compare anyway" escape hatch.

**Verdicts live outside the run tree.** Every measurement can be recomputed by
re-running; a human judgment cannot, and run trees are gitignored and deleted
routinely.

**A first run reports no delta, not a delta of zero.** Zero reads as "no change",
which is a different claim from "nothing to compare against".

**The installer takes its target from the working directory, never from
`$PSScriptRoot`.** Installed as a plugin the skill is not inside the project at
all, so walking up from the script finds the plugin cache. Walking up from where
the operator is standing finds the project under both installs. A test covers each
shape, including one that copies the skill outside the project on purpose.

**The generated wrapper is relative when the skill is inside the project and
absolute when it is not.** Relative survives the project being cloned elsewhere;
a plugin path has no relative form. The wrapper checks that its `serve.cs` still
exists and throws if not, because a plugin path carries a version and an update
invalidates it. Failing loudly there is the point: the alternative is running a
version of the service nobody chose.

**Nothing uploads anything.** The whole point is that unreleased game design stays
on the machine that produced it. The export is a local file. If a change would
send a run anywhere, it is the wrong change.

## Traps this codebase has already hit

All of these compiled or looked fine and failed at runtime.

**Anonymous-type JSON results return 500.** `Results.Json(new {...})` and
`Results.NotFound(new {...})` compile with only IL2026/IL3050 warnings, then fail
when the route is called, because reflection-based serialisation is unavailable
here. Six routes broke at once with bare 500s and no stack, because logging
providers are cleared. **Build every response as a `JsonNode` and return it via the
`Json()` helper.** Never reintroduce `Results.Json`.

**PowerShell 5.1 cannot set a `Range` header** via `Invoke-WebRequest -Headers`. It
throws in a way indistinguishable from a server with no range support. Use
`Invoke-RangeRequest`, which goes through `HttpClient`.

**PowerShell 5.1's `Start-Process -ArgumentList` does not quote array elements
containing spaces.** An unquoted launch template split into tokens and the service
silently launched nothing. Quote anything with spaces before it reaches
`Start-Process`.

**`cmd /c` with a quoted command string does nothing useful.** The launcher uses
raw `Arguments`, not `ArgumentList`, precisely because `ArgumentList` quotes the
command and cmd then tries to read it as an executable name.

**`Set-Content -Encoding utf8` writes a BOM** in PowerShell 5.1, and
`Get-Content -Raw` decodes BOM-less files using the system ANSI codepage. Both
corrupt round-trips silently. Use `[IO.File]::ReadAllText` / `WriteAllText` with an
explicit `UTF8Encoding($false)`.

**`$PSCommandPath` inside a function resolves to the file that DEFINED it**, not
the caller. Deriving a repo root by counting parent directories from it produced
`harness\harness\serve.cs`. Walk up to `.git` instead.

**Double rounding plus round-half-to-even loses a digit.** Rounding 11.8547 to
11.85 server-side, then to one place client-side, yields 11.8 rather than 11.9.
Report at working precision and round once, at the point of display.

**A file-based app runs from a generated temp directory.** `AppContext.BaseDirectory`
points there, not at the source, so gallery assets are located via `CallerFilePath`,
which is baked in at compile time.

## Deliberately absent

Do not add these without a reason that did not exist before.

- **No browser test harness. This question is settled; do not reopen it without
  new evidence.** It was open until the manual pass ran, and the pass answered it.
  Both defects it found (F9) sat outside the DOM: frame stepping did nothing
  visible because the capture stride was not exposed, which a server-side
  assertion catches earlier and cheaper, and runs could not be referred to at all,
  which is human factors that no automated test finds because nothing was broken.
  With F7, where a frame-lock bug lived between the encoder and the seek
  arithmetic, the pattern holds: this tool's failures sit **between** components,
  in encode rates, strides and naming. Spend the effort on contract assertions,
  and re-run the manual pass whenever the interface changes shape.
- **No authentication, no multi-user, no remote access.** It binds to `127.0.0.1`
  and is a single-operator tool.
- **No live reload.** The page re-reads the index on load. Refresh is fine, and a
  websocket is a moving part that buys little.
- **No database.** The filesystem is the index. Runs are files; scanning them is
  fast enough and survives anything.
- **No engine SDK dependency.** The contract is a JSON file and an mp4. Keep it
  that way; that is what makes this portable.

## Changing the run contract

The contract is what host projects depend on, so treat additions as cheap and
changes as expensive.

- **Adding an optional field** is free. Default it so existing runs keep working.
- **Changing a default** is a breaking change even when nothing errors, because a
  host repo's numbers move silently. The platformer defaults on `measure` exist for
  exactly this reason.
- **Removing a field** needs a version note in
  `skills/runbox/reference/run-contract.md`.

Update the contract doc and the tests in the same commit as the code. The doc is
what people read; the tests are what holds.

## Style

Match what is there. Comments explain *why*, especially where a line looks
replaceable but is not, and several carry the measurement that justified them.
Keep those. They are the difference between a maintainer trusting a rule and
"simplifying" it back into a bug.
