# Working on runbox itself

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

Twenty-five integration tests, self-contained. Every case builds its own run tree
in a temp directory and points the service at it with `--out`, so the suite runs
in this repo with no game, no engine, and nothing installed but .NET.

**If a test needs a host project, it is in the wrong repo.** A host repo tests its
integration with runbox. This tests runbox.

The suite is the specification. `reference/run-contract.md` describes the contract
in prose, but the tests are what actually holds it.

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

- **No browser test harness.** The playback layer is JavaScript, and a headless
  browser is a large dependency. The data layer is tested instead, and the one
  frame-lock bug found in practice was an encoder/arithmetic mismatch a DOM test
  would also have missed. See `FINDINGS.md`.
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
- **Removing a field** needs a version note in `reference/run-contract.md`.

Update the contract doc and the tests in the same commit as the code. The doc is
what people read; the tests are what holds.

## Style

Match what is there. Comments explain *why*, especially where a line looks
replaceable but is not, and several carry the measurement that justified them.
Keep those. They are the difference between a maintainer trusting a rule and
"simplifying" it back into a bug.
