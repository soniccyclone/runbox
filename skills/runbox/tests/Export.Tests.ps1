<#
  Export: one file that opens on a machine with nothing installed and no network.

  Any external reference at all breaks that, silently, and only for the person it
  was sent to. Which is why these look for them rather than trusting the writer.
#>

function Invoke-Export {
    param([string]$OutRoot, [string]$File, [string]$Game = '*')
    $script = Join-Path (Get-ToolDir) 'export.ps1'
    & $script -Game $Game -Out $File -OutRootOverride $OutRoot 2>&1 | Out-Null
}

Register-Test 'Export :: contains_no_external_references' {
    $out = New-TempTree 'exp-refs'
    $file = Join-Path $env:TEMP "runbox-export-refs-$PID.html"
    try {
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'r1' -Span 117 -WithClip | Out-Null
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'r2' -Span 138.7 -WithClip | Out-Null
        Invoke-Export -OutRoot $out -File $file
        Assert-True (Test-Path $file) 'the export must be written'

        $html = [System.IO.File]::ReadAllText($file)
        # data: URIs contain no host, so strip them before looking for anything
        # that would actually hit the network.
        $stripped = [regex]::Replace($html, 'data:[a-z]+/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=]+', 'DATAURI')
        foreach ($pat in @('http://', 'https://', 'src="//', 'href="//', '<script src=')) {
            Assert-NotContains $stripped $pat "an export must not reference [$pat]"
        }
    } finally { Remove-TempTree $out; Remove-Item $file -Force -ErrorAction SilentlyContinue }
}

Register-Test 'Export :: carries_the_clips_inline' {
    $out = New-TempTree 'exp-clips'
    $file = Join-Path $env:TEMP "runbox-export-clips-$PID.html"
    try {
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'r1' -Span 117 -WithClip | Out-Null
        Invoke-Export -OutRoot $out -File $file
        $html = [System.IO.File]::ReadAllText($file)
        Assert-True (([regex]::Matches($html, 'data:video/mp4;base64,')).Count -ge 1) 'at least one clip embedded'
        Assert-Contains $html 'window.__RUNS__' 'run data baked in, not fetched'
    } finally { Remove-TempTree $out; Remove-Item $file -Force -ErrorAction SilentlyContinue }
}

Register-Test 'Export :: keeps_the_finish' {
    $out = New-TempTree 'exp-skin'
    $file = Join-Path $env:TEMP "runbox-export-skin-$PID.html"
    try {
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'r1' -Span 117 | Out-Null
        Invoke-Export -OutRoot $out -File $file
        $html = [System.IO.File]::ReadAllText($file)
        Assert-Contains $html '-webkit-box-reflect' 'Cover Flow reflections'
        Assert-Contains $html 'repeating-linear-gradient' 'brushed metal chassis'
        Assert-Contains $html '--amber' 'amber VFD palette'
        Assert-Contains $html 'Lucida Grande' 'pre-2015 type stack'
    } finally { Remove-TempTree $out; Remove-Item $file -Force -ErrorAction SilentlyContinue }
}

Register-Test 'Export :: refuses_when_there_is_nothing_to_export' {
    $out = New-TempTree 'exp-empty'
    $file = Join-Path $env:TEMP "runbox-export-empty-$PID.html"
    try {
        Invoke-Export -OutRoot $out -File $file
        Assert-True (-not (Test-Path $file)) 'an empty export is worse than none; it looks like a working page with no runs'
    } finally { Remove-TempTree $out; Remove-Item $file -Force -ErrorAction SilentlyContinue }
}
