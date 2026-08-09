<#
  Scaffolding for the runbox tool's own tests.

  Self-contained on purpose. These must run in the runbox repo with no game, no
  engine and no host project, so every fixture is built here in a temp directory
  and the service is always pointed at it with --out and --root.

  If a test in here needs anything from a host repo, it belongs in that repo's
  suite instead, not this one.
#>

$script:TestRegistry = [System.Collections.Generic.List[object]]::new()

function Register-Test {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Body)
    $script:TestRegistry.Add([pscustomobject]@{ Name = $Name; Body = $Body })
}
function Get-TestRegistry { $script:TestRegistry }

# ---- assertions ---------------------------------------------------------

function Assert-True {
    param([Parameter(Mandatory)]$Condition, [string]$Because = '')
    if (-not $Condition) { throw "expected true$(if($Because){" :: $Because"})" }
}
function Assert-Equal {
    param($Expected, $Actual, [string]$Because = '')
    if ($Expected -ne $Actual) { throw "expected [$Expected] but got [$Actual]$(if($Because){" :: $Because"})" }
}
function Assert-NotEqual {
    param($NotExpected, $Actual, [string]$Because = '')
    if ($NotExpected -eq $Actual) { throw "expected anything but [$NotExpected]$(if($Because){" :: $Because"})" }
}
function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Because = '')
    if ($Haystack -notlike "*$Needle*") { throw "expected to find [$Needle]$(if($Because){" :: $Because"})" }
}
function Assert-NotContains {
    param([string]$Haystack, [string]$Needle, [string]$Because = '')
    if ($Haystack -like "*$Needle*") { throw "expected NOT to find [$Needle]$(if($Because){" :: $Because"})" }
}

# ---- locations ----------------------------------------------------------

# The workshop lives at the repo root and the deliverable lives under
# skills/runbox, so that a consuming project can copy the skill directory whole
# without dragging the tests and the maintainer docs along with it. That split is
# why this is not simply the parent directory.
function Get-RepoRoot  { Split-Path -Parent $PSScriptRoot }
function Get-SkillRoot { Join-Path (Get-RepoRoot) 'skills\runbox' }
function Get-ToolDir   { Join-Path (Get-SkillRoot) 'tool' }
function Get-FixtureClip { Join-Path $PSScriptRoot 'fixtures\sample-clip.mp4' }

# ---- service lifecycle --------------------------------------------------

<#
  Start the service against a caller-supplied root. Always pair with
  Stop-RunboxServer in a finally, or a failing assertion leaves a held port.
#>
function Start-RunboxServer {
    param(
        [Parameter(Mandatory)][int]$Port,
        [string]$Root = '',
        [string]$Launch = ''
    )
    if (-not $Root) { $Root = $env:TEMP }
    $serve = Join-Path (Get-ToolDir) 'serve.cs'
    if (-not (Test-Path $serve)) { throw "no serve.cs at $serve" }

    # MEASURED: PowerShell 5.1's Start-Process -ArgumentList joins the array with
    # spaces and does NOT quote elements that contain them. An unquoted launch
    # template splits into separate tokens, so the service received "mkdir" and
    # silently launched nothing. Quote anything with spaces here, not later.
    $a = @('run', "`"$serve`"", '--', '--port', $Port, '--root', "`"$Root`"")
    if ($Launch) { $a += @('--launch', "`"$Launch`"") }

    $p = Start-Process dotnet -ArgumentList $a -PassThru -WindowStyle Hidden
    $base = "http://127.0.0.1:$Port"
    for ($i = 0; $i -lt 90; $i++) {
        if ($p.HasExited) { throw "service exited early, code $($p.ExitCode)" }
        try {
            $r = Invoke-WebRequest "$base/health" -TimeoutSec 2 -UseBasicParsing
            if ($r.StatusCode -eq 200) { return [pscustomobject]@{ Process = $p; BaseUrl = $base } }
        } catch { Start-Sleep -Milliseconds 600 }
    }
    try { $p.Kill() } catch {}
    throw "service did not answer on $base"
}

function Stop-RunboxServer {
    param($Server)
    if ($null -eq $Server) { return }
    try { Stop-Process -Id $Server.Process.Id -Force -ErrorAction SilentlyContinue } catch {}
}

<#
  MEASURED: PowerShell 5.1's Invoke-WebRequest cannot set a Range header via
  -Headers. It throws "must be modified using the appropriate property or
  method", which is indistinguishable from a server that does not support
  ranges. HttpClient is the only correct way to test this.
#>
function Invoke-RangeRequest {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][int]$From, [Parameter(Mandatory)][int]$To)
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage('GET', $Url)
        $req.Headers.Range = New-Object System.Net.Http.Headers.RangeHeaderValue($From, $To)
        $resp = $client.SendAsync($req).Result
        $bytes = $resp.Content.ReadAsByteArrayAsync().Result
        return [pscustomobject]@{
            Status = [int]$resp.StatusCode; ByteCount = $bytes.Length
            ContentRange = [string]$resp.Content.Headers.ContentRange
        }
    } finally { $client.Dispose() }
}

function Invoke-Json {
    param([Parameter(Mandatory)][string]$Url, [string]$Method = 'GET', $Body = $null)
    $a = @{ Uri = $Url; Method = $Method; UseBasicParsing = $true; TimeoutSec = 25 }
    if ($null -ne $Body) { $a.Body = ($Body | ConvertTo-Json -Depth 6 -Compress); $a.ContentType = 'application/json' }
    $r = Invoke-WebRequest @a
    return [pscustomobject]@{ Status = [int]$r.StatusCode; Json = ($r.Content | ConvertFrom-Json); Raw = $r.Content }
}

# ---- fixtures -----------------------------------------------------------

# ---- installer fixtures -------------------------------------------------

<#
  A project that looks instrumentable: a git repo and nothing else. `git init`
  rather than a bare .git directory, because the installer walks for a real one.
#>
function New-FakeProject {
    param([Parameter(Mandatory)][string]$Path)
    Push-Location $Path
    try { & git init -q 2>&1 | Out-Null } finally { Pop-Location }
}

<# The copied-in shape: <project>\.claude\skills\runbox. #>
function Install-SkillCopy {
    param([Parameter(Mandatory)][string]$Project)
    $dest = Join-Path $Project '.claude\skills\runbox'
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
    Copy-Item (Get-SkillRoot) $dest -Recurse -Force
    return $dest
}

<#
  Run the installer the way a person does: standing in the project. The target is
  resolved from the working directory, so -From is the thing under test as much
  as any argument is.
#>
function Invoke-Installer {
    param(
        [Parameter(Mandatory)][string]$Skill,
        [Parameter(Mandatory)][string]$From,
        [switch]$Force
    )
    Push-Location $From
    try {
        $a = @{}
        if ($Force) { $a.Force = $true }
        & (Join-Path $Skill 'install.ps1') @a
    } finally { Pop-Location }
}

function Get-WrapperServeLine {
    param([Parameter(Mandatory)][string]$WrapperPath)
    $line = @(Get-Content $WrapperPath | Where-Object { $_ -match '^\$serve\s*=' })[0]
    if (-not $line) { throw "no `$serve assignment in $WrapperPath" }
    return $line
}

<#
  Evaluate the wrapper's own path expression, rather than pattern-matching it.
  The question is whether the generated wrapper finds serve.cs at runtime, and
  only evaluating it actually asks that.
#>
function Resolve-WrapperServe {
    param([Parameter(Mandatory)][string]$WrapperPath, [Parameter(Mandatory)][string]$ProjectRoot)
    $expr = (Get-WrapperServeLine $WrapperPath) -replace '^\$serve\s*=\s*', ''
    $root = $ProjectRoot   # the wrapper's own variable, in scope for the eval
    return (Invoke-Expression $expr)
}

# ---- temp trees ---------------------------------------------------------

function New-TempTree {
    param([Parameter(Mandatory)][string]$Tag)
    $p = Join-Path $env:TEMP "runbox-$Tag-$PID-$(Get-Random -Maximum 99999)"
    if ([System.IO.Directory]::Exists($p)) { [System.IO.Directory]::Delete($p, $true) }
    [void][System.IO.Directory]::CreateDirectory($p)
    return $p
}

function Remove-TempTree {
    param([string]$Path)
    if ($Path -and [System.IO.Directory]::Exists($Path)) {
        try { [System.IO.Directory]::Delete($Path, $true) } catch {}
    }
}

<#
  Write one run in the documented contract.

  Span is expressed through the EVENTS rather than as a measured field, because
  that is where the tool reads it from. A fixture that states the answer directly
  would not exercise the measurement path at all.
#>
function New-Run {
    param(
        [Parameter(Mandatory)][string]$OutRoot,
        [Parameter(Mandatory)][string]$Game,
        [Parameter(Mandatory)][string]$Scenario,
        [Parameter(Mandatory)][string]$RunId,
        [string]$RunAt = '',
        [double]$Span = 0,
        [double]$Claim = 0,
        [switch]$Incomplete,
        [switch]$WithClip,
        [switch]$AbortSpan,
        [hashtable]$Measure = $null,
        [string[]]$ExtraEvents = @()
    )
    $dir = Join-Path $OutRoot "$Game\$Scenario\$RunId"
    [void][System.IO.Directory]::CreateDirectory($dir)
    if ($Incomplete) {
        [System.IO.File]::WriteAllBytes((Join-Path $dir 'frame_00001.png'), (New-Object byte[] 8))
        return $dir
    }

    $events = @(@{ frame = 22; name = 'jump'; x = 132.0; y = 383.9 })
    if ($AbortSpan) {
        # A span that never completed: the world intervened. Anything pairing
        # events must abandon this rather than pair across it.
        $events += @{ frame = 40; name = 'death'; x = 500.0; y = 700.0 }
        $events += @{ frame = 44; name = 'land';  x = 138.7; y = 383.9 }
    } else {
        $events += @{ frame = 53; name = 'land'; x = (132.0 + $Span); y = 383.9 }
    }
    foreach ($e in $ExtraEvents) { $events += @{ frame = 70; name = $e; x = 0.0; y = 0.0 } }

    $payload = [ordered]@{
        scenario = $Scenario
        run_at   = if ($RunAt) { $RunAt } else { (Get-Date).ToString('o') }
        frames   = 111
        passed   = $true
        reason   = 'tape exhausted'
        checks   = @(@{ name = 'ran'; ok = $true; detail = '' })
        counts   = @{ jump = 1; land = 1 }
        claims   = @{ reach = $Claim }
        events   = $events
    }
    if ($Measure) { $payload.measure = $Measure }

    [System.IO.File]::WriteAllText((Join-Path $dir 'result.json'),
        ($payload | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

    if ($WithClip) { Copy-Item (Get-FixtureClip) (Join-Path $dir 'clip.mp4') -Force }
    return $dir
}
