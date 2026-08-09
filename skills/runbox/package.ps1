<#
.SYNOPSIS
  Stage the installable deliverable, without the maintainer's half of the repo.

.DESCRIPTION
  The runbox repo holds two things with different audiences:

    the DELIVERABLE  what gets installed into a game project, for an agent
                     USING runbox to iterate on gameplay
    the WORKSHOP     tests, findings, and maintainer instructions, for an agent
                     DEVELOPING runbox

  Only the first ships. The layouts differ because Claude Code discovers skills at
  .claude/skills/<name>/SKILL.md, so the installed shape is fixed and cannot also
  be the repo shape without dragging the workshop along.

  AGENTS.md is the reason this matters rather than being tidiness. Installed into
  a game project it is instructions addressed to a different job, telling an agent
  how to maintain runbox when it should be using it.

  FINDINGS.md is the deliberate exception: it ships. The rules in SKILL.md look
  arbitrary without their evidence, and an agent that cannot see why will
  eventually simplify one away.

.EXAMPLE
  .\package.ps1
  .\package.ps1 -To C:\code\my-game\.claude\skills\runbox
#>
[CmdletBinding()]
param(
    [string]$To = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dest = if ($To) { $To } else { Join-Path $src 'dist\runbox' }

# What an installed skill needs, and nothing else.
$include = @(
    'SKILL.md',
    'FINDINGS.md',
    'install.ps1',
    'reference',
    'tool'
)

# Named rather than inferred, so adding a workshop file does not silently ship it.
$exclude = @(
    'AGENTS.md',      # addressed to a maintainer; misleads a consuming agent
    'README.md',      # the repo's front door, not the skill's
    'test.ps1',       # the maintainer gate
    'tests',          # needs no game, but belongs to the repo
    'package.ps1',
    'dist',
    'LICENSE'         # stays with the repo; consuming projects have their own
)

if ((Test-Path $dest) -and -not $Force -and $To) {
    throw "$dest already exists. Pass -Force to overwrite."
}
if (Test-Path $dest) { [System.IO.Directory]::Delete((Resolve-Path $dest), $true) }
[void][System.IO.Directory]::CreateDirectory($dest)

foreach ($item in $include) {
    $from = Join-Path $src $item
    if (-not (Test-Path $from)) { throw "deliverable is missing $item" }
    Copy-Item $from (Join-Path $dest $item) -Recurse -Force
}

# Belt and braces: prove nothing from the workshop rode along.
foreach ($item in $exclude) {
    $leaked = Join-Path $dest $item
    if (Test-Path $leaked) { throw "PACKAGING BUG: $item reached the deliverable" }
}

$files = @(Get-ChildItem $dest -Recurse -File)
$bytes = ($files | Measure-Object Length -Sum).Sum

Write-Output "packaged -> $dest"
Write-Output ("  {0} files, {1:N0} KB" -f $files.Count, ($bytes / 1KB))
Write-Output ""
foreach ($f in $files | Sort-Object FullName) {
    Write-Output ("  " + $f.FullName.Replace("$dest\", ""))
}
Write-Output ""
Write-Output "Install by copying that directory to <target-repo>\.claude\skills\runbox,"
Write-Output "then running install.ps1 inside the target."
