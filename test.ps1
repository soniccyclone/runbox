<#
.SYNOPSIS
  runbox's own gate. Verifies the tool against the contract it publishes.

.DESCRIPTION
  Self-contained: every case builds its own run tree in a temp directory and
  points the service at it. No game, no engine, no host project required, so
  this runs in the runbox repo on a machine with nothing installed but .NET.

  A host repo's own suite tests its integration with runbox. This tests runbox.
  If a case here needs something from a host repo, it is in the wrong file.

.EXAMPLE
  .\test.ps1
  .\test.ps1 -Area Analysis
  .\test.ps1 -Name '*drift*'
#>
[CmdletBinding()]
param([string]$Area = '*', [string]$Name = '*')

$ErrorActionPreference = 'Stop'
$testDir = Join-Path $PSScriptRoot 'tests'

. (Join-Path $testDir '_lib.ps1')

$files = Get-ChildItem $testDir -Filter "$Area.Tests.ps1" -ErrorAction SilentlyContinue | Sort-Object Name
if (-not $files) { Write-Output "no test files matched '$Area'"; exit 0 }
foreach ($f in $files) { . $f.FullName }

$cases = Get-TestRegistry | Where-Object { $_.Name -like $Name }
if (-not $cases) { Write-Output "no tests matched '$Name'"; exit 0 }

$pass = 0; $fail = 0
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($c in $cases) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $c.Body
        $sw.Stop()
        Write-Output ("  PASS  {0,-58} {1,5}ms" -f $c.Name, $sw.ElapsedMilliseconds)
        $pass++
    } catch {
        $sw.Stop()
        $msg = $_.Exception.Message -replace '\s+', ' '
        if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) + ' ...' }
        Write-Output ("  FAIL  {0,-58} {1,5}ms" -f $c.Name, $sw.ElapsedMilliseconds)
        Write-Output ("        {0}" -f $msg)
        $failures.Add("$($c.Name): $msg")
        $fail++
    }
}

Write-Output ""
Write-Output ("=== runbox: {0} passed, {1} failed ===" -f $pass, $fail)
if ($fail -gt 0) { foreach ($x in $failures) { Write-Output "  - $x" }; exit 1 }
exit 0
