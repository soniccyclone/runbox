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

Forty integration tests, self-contained. Every case builds its own run tree
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
skills/            THE PAYLOAD. Everything in here is delivered, verbatim.
  runbox/            SKILL.md  FINDINGS.md  install.ps1  reference/  tool/

bin/  src/          the deposit CLI. Ships in the npm package, not to projects.
AGENTS.md          stays. So do README.md, test.ps1, tests/, .github/
```

Agents disagree about where skills live, so `src/targets.js` owns one path per
agent and `src/install.js` copies the payload into each. Detection ranks the
selection list and never gates it: somebody installing runbox before their editor
must not be locked out.

**`skills/` is the payload boundary, and it is the whole packaging mechanism.**
There is no exclusion list to keep in sync, which is exactly why there used to be
bugs here. Anything you add outside `skills/` stays in the repo; anything you add
inside it reaches every project that installs runbox. `Deposit :: ships the
deliverable and nothing else` is the test that holds this, and it names both
directions.

**Adding an agent** means a `TARGETS` entry with its own `skillsDir`,
`globalSkillsDir` and `detect` markers, plus a line in the README table and the
path assertion in `Deposit :: every agent gets its own path`. Copilot is the one
worth reading first: it is detected by files under `.github` but reads skills from
`.github/skills`, so detection and destination are genuinely different fields.

**`init` gates on the toolchain before writing anything.** Depositing a skill
whose service cannot start leaves an agent following instructions that fail for
reasons the method has nothing to do with. Windows and .NET 10 are hard failures;
ffmpeg is a warning, because runs index fine without clips.

`FINDINGS.md` ships on purpose. The rules in `SKILL.md` read as arbitrary without
their evidence, and an agent that cannot see why "never emit a calibration
constant" exists will eventually fit one.

**Anything new goes at the root unless a consuming project needs it at runtime.**
When adding to `skills/runbox/`, ask whether it makes sense to an agent who has
only that directory and a game.

## The site

`site/build.sh` publishes to GitHub Pages. Every page with substance is generated
from a file that ships, so the site cannot drift: the method page is `SKILL.md`
and the contract page is `run-contract.md`, both via pandoc, and **the demo is a
real `export.ps1` run** over the committed `site/demo-runs`. If the gallery
changes, the demo changes with it; if the exporter breaks, the build fails.

The demo numbers are F2 from `FINDINGS.md`, and the clips encode the reach they
claim: airtime is `reach / speed`, so the horizontal distance on screen is the
measured value in the delta table. Do not replace them with prettier footage that
means nothing.

`site/build.el` carries the skin, and it is **not a free choice**. The gallery
commits to one finish and says so in its own comment. The site wears the same
palette, lifted from the gallery's `:root`. Keep the two in step.

Requires emacs, pandoc and pwsh. Nothing on Windows has all three, so verify in a
container rather than trusting CI:

```sh
docker run --rm -v "//c/path/to/runbox:/src:ro" runbox-site \
  sh -c 'cp -r /src /build && cd /build && sh site/build.sh && tar cf - -C /build/site www' > site.tar
node site/check.js <extracted>/www
```

Build into a copy, not the bind mount: output written into a mounted Windows
directory comes back with ownership the container cannot then delete.

`site/check.js` runs before deploy and asserts what rots silently. Add to it when
you add a page.

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

**`install.ps1` takes its target from the working directory, never from
`$PSScriptRoot`.** After a `--global` deposit the skill lives in the home
directory, not in the project, so walking up from the script finds the wrong repo
or none. Walking up from where the operator is standing finds the project under
either deposit. A test covers each shape.

**The generated wrapper is relative when the skill is inside the project and
absolute when it is not.** Relative survives the project being cloned elsewhere;
a path outside the project has no relative form. The wrapper checks that its
`serve.cs` still exists and throws if not, because a global skill can be moved or
updated out from under it. Failing loudly there is the point: the alternative is
running a version of the service nobody chose.

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

**`2>&1` on a native executable throws under `ErrorActionPreference = 'Stop'`.**
PowerShell 5.1 wraps each stderr line in a `NativeCommandError` record, so a CLI
writing a perfectly good diagnostic to stderr is indistinguishable from a crash.
Testing that `init` rejects an unknown agent failed for exactly this reason while
the CLI was correct. `Invoke-Deposit` redirects both streams to files through
`Start-Process` instead.

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
