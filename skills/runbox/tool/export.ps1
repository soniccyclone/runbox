<#
.SYNOPSIS
  Bake the current gallery into one self-contained file.

.DESCRIPTION
  The service is the daily surface. This is for handing someone a copy: one file
  that opens on a machine with nothing installed and no network.

  Everything is inlined, including the video. Measured: an mp4 clip is about
  16KB and base64 costs 33%, so roughly 771 clips fit inside a 16MB page. The
  ceiling is not a practical concern, which is why embedding is fine for an
  export even though it was the wrong mechanism for the daily surface.

  The skin comes along unchanged. The pre-2015 finish is a constraint on this
  work, not decoration.

.EXAMPLE
  .\.claude\skills\runbox\tool\export.ps1
  .\.claude\skills\runbox\tool\export.ps1 -Game dashguy -Out .\dashguy-review.html
#>
[CmdletBinding()]
param(
    [string]$Game = '*',
    [string]$Scenario = '*',
    [string]$Out = '',
    [string]$OutRootOverride = ''
)

$ErrorActionPreference = 'Stop'

# Walk up to the repo this is installed in, rather than counting parent
# directories, so the tool works wherever it has been dropped.
function Get-RepoRoot {
    $d = $PSScriptRoot
    while ($d -and -not (Test-Path (Join-Path $d '.git'))) {
        $parent = Split-Path -Parent $d
        if ($parent -eq $d) { break }
        $d = $parent
    }
    if (-not $d -or -not (Test-Path (Join-Path $d '.git'))) { throw "could not find a repo root above $PSScriptRoot" }
    return $d
}

# OutRootOverride names the RUN TREE directly, not a repo containing one, so a
# caller with runs somewhere unusual (a test fixture, a scratch capture) does not
# have to fabricate a .harness-out beneath it.
if ($OutRootOverride) {
    $outRoot = $OutRootOverride
    $root = Split-Path -Parent $OutRootOverride
} else {
    $root = Get-RepoRoot
    $outRoot = Join-Path $root '.harness-out'
}
$galleryDir = Join-Path $PSScriptRoot 'gallery'   # assets sit beside this script
if (-not $Out) { $Out = Join-Path $root 'run-box-export.html' }

# Which events bound the measured span is the prototype's business, declared in
# result.json as measure: { from, to, abortOn, axis }. Defaults keep the
# platformer vocabulary so existing runs still measure.
function Measure-Span($run) {
    if (-not $run -or -not $run.events) { return $null }
    $from    = if ($run.measure -and $run.measure.from)    { $run.measure.from }    else { 'jump' }
    $to      = if ($run.measure -and $run.measure.to)      { $run.measure.to }      else { 'land' }
    $abortOn = if ($run.measure -and $run.measure.abortOn) { $run.measure.abortOn } else { 'death' }
    $axis    = if ($run.measure -and $run.measure.axis)    { $run.measure.axis }    else { 'x' }

    $ev = @($run.events)
    for ($i = 0; $i -lt $ev.Count; $i++) {
        if ($ev[$i].name -ne $from) { continue }
        for ($k = $i + 1; $k -lt $ev.Count; $k++) {
            if ($ev[$k].name -eq $abortOn) { break }   # the span never completed
            if ($ev[$k].name -ne $to) { continue }
            return [double]$ev[$k].$axis - [double]$ev[$i].$axis
        }
    }
    return $null
}

$runs = @()
if (Test-Path $outRoot) {
    foreach ($g in Get-ChildItem $outRoot -Directory -Filter $Game) {
        foreach ($s in Get-ChildItem $g.FullName -Directory -Filter $Scenario) {
            foreach ($r in Get-ChildItem $s.FullName -Directory) {
                $rj = Join-Path $r.FullName 'result.json'
                if (-not (Test-Path $rj)) { continue }
                try { $res = Get-Content $rj -Raw | ConvertFrom-Json } catch { continue }

                $clipPath = Join-Path $r.FullName 'clip.mp4'
                $clipUri = $null
                if (Test-Path $clipPath) {
                    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($clipPath))
                    $clipUri = "data:video/mp4;base64,$b64"
                }
                $measured = Measure-Span $res
                $claimed = if ($res.claims -and $res.claims.reach) { [double]$res.claims.reach } else { $null }

                $runs += [ordered]@{
                    id       = "$($g.Name)/$($s.Name)/$($r.Name)"
                    game     = $g.Name
                    scenario = $s.Name
                    runId    = $r.Name
                    runAt    = if ($res.run_at) { $res.run_at } else { (Get-Item $rj).LastWriteTimeUtc.ToString('o') }
                    frames   = [int]$res.frames
                    passed   = [bool]$res.passed
                    events   = @($res.events)
                    measured = $measured
                    claimed  = $claimed
                    driftPct = if ($measured -and $claimed) { [math]::Round(($measured - $claimed) / $claimed * 100, 1) } else { $null }
                    clip     = $clipUri
                    verdict  = $null
                }
            }
        }
    }
}

if (-not $runs) { Write-Output "no runs to export under $outRoot"; exit 1 }

$html = [System.IO.File]::ReadAllText((Join-Path $galleryDir 'index.html'))
$js = [System.IO.File]::ReadAllText((Join-Path $galleryDir 'gallery.js'))
$payload = ($runs | ConvertTo-Json -Depth 8 -Compress)

# Replace the external script tag with the data and the script inline. A single
# <script src> would be an external reference, which is the one thing an export
# must not contain.
$inline = "<script>window.__RUNS__ = $payload;</script>`n<script>`n$js`n</script>"
$html = $html.Replace('<script src="/gallery.js"></script>', $inline)

[System.IO.File]::WriteAllText($Out, $html, (New-Object System.Text.UTF8Encoding($false)))

$kb = [math]::Round((Get-Item $Out).Length / 1KB, 1)
Write-Output ("exported {0} runs -> {1} ({2} KB)" -f $runs.Count, $Out, $kb)
