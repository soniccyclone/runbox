<#
  The service contract: what a host repo is entitled to rely on.

  Every case builds its own run tree. Nothing here knows what a game is.
#>

Register-Test 'Service :: answers_on_the_configured_port' {
    $s = $null
    try {
        $s = Start-RunboxServer -Port 7901
        Assert-Equal 200 ([int](Invoke-WebRequest "$($s.BaseUrl)/health" -UseBasicParsing).StatusCode)
    } finally { Stop-RunboxServer $s }
}

Register-Test 'Service :: indexes_runs_and_skips_incomplete_ones' {
    $s = $null; $out = New-TempTree 'index'
    try {
        New-Run -OutRoot $out -Game 'alpha' -Scenario 'a' -RunId 'r1' -Span 100 | Out-Null
        New-Run -OutRoot $out -Game 'beta'  -Scenario 'b' -RunId 'r1' -Span 120 | Out-Null
        # Frames written, result.json never arrived: a capture still in flight.
        New-Run -OutRoot $out -Game 'gamma' -Scenario 'c' -RunId 'r1' -Incomplete | Out-Null

        $s = Start-RunboxServer -Port 7902
        $res = Invoke-Json "$($s.BaseUrl)/api/runs?out=$([uri]::EscapeDataString($out))"
        Assert-Equal 2 (@($res.Json).Count) 'an unfinished run is omitted, not an error'
        Assert-NotContains $res.Raw 'gamma' 'the unfinished run must not appear at all'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Service :: survives_a_malformed_result_json' {
    $s = $null; $out = New-TempTree 'malformed'
    try {
        New-Run -OutRoot $out -Game 'alpha' -Scenario 'a' -RunId 'good' -Span 100 | Out-Null
        $bad = Join-Path $out 'alpha\a\broken'
        [void][System.IO.Directory]::CreateDirectory($bad)
        [System.IO.File]::WriteAllText((Join-Path $bad 'result.json'), '{ this is not json')

        $s = Start-RunboxServer -Port 7903
        $res = Invoke-Json "$($s.BaseUrl)/api/runs?out=$([uri]::EscapeDataString($out))"
        Assert-Equal 200 $res.Status 'one corrupt file must not take down browsing'
        Assert-Equal 1 (@($res.Json).Count) 'the corrupt run is skipped like an incomplete one'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Service :: clips_serve_partial_content' {
    $s = $null; $out = New-TempTree 'range'
    try {
        New-Run -OutRoot $out -Game 'alpha' -Scenario 'a' -RunId 'r1' -Span 100 -WithClip | Out-Null
        $size = (Get-Item (Get-FixtureClip)).Length

        $s = Start-RunboxServer -Port 7904
        $url = "$($s.BaseUrl)/clip/alpha/a/r1/clip.mp4?out=$([uri]::EscapeDataString($out))"
        $r = Invoke-RangeRequest -Url $url -From 1000 -To 1999
        Assert-Equal 206 $r.Status 'seeking inside a clip depends on 206, not 200'
        Assert-Equal 1000 $r.ByteCount
        Assert-Equal "bytes 1000-1999/$size" $r.ContentRange
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Service :: refuses_to_serve_outside_the_run_tree' {
    $s = $null; $out = New-TempTree 'escape'
    try {
        New-Run -OutRoot $out -Game 'alpha' -Scenario 'a' -RunId 'r1' -Span 100 | Out-Null
        # A canary above the run tree, which must stay unreachable.
        [System.IO.File]::WriteAllText((Join-Path $out '..\runbox-canary.txt'), 'CANARY-SECRET')

        $s = Start-RunboxServer -Port 7905
        $q = "?out=$([uri]::EscapeDataString($out))"
        foreach ($e in @('/clip/../runbox-canary.txt',
                         '/clip/alpha/a/r1/..%2F..%2F..%2Frunbox-canary.txt',
                         '/clip/alpha/a/r1/..%5C..%5C..%5Crunbox-canary.txt')) {
            $status = 0; $body = ''
            try { $r = Invoke-WebRequest "$($s.BaseUrl)$e$q" -UseBasicParsing -TimeoutSec 10; $status = [int]$r.StatusCode; $body = $r.Content }
            catch { $status = [int]$_.Exception.Response.StatusCode }
            Assert-NotEqual 200 $status "escape [$e] must not succeed"
            Assert-NotContains $body 'CANARY-SECRET' "escape [$e] must not leak contents"
        }
    } finally {
        Stop-RunboxServer $s
        Remove-Item (Join-Path $out '..\runbox-canary.txt') -Force -ErrorAction SilentlyContinue
        Remove-TempTree $out
    }
}

Register-Test 'Service :: serves_the_gallery_with_its_finish' {
    $s = $null
    try {
        $s = Start-RunboxServer -Port 7906
        $page = (Invoke-WebRequest "$($s.BaseUrl)/" -UseBasicParsing).Content
        # The pre-2015 finish is a constraint, not decoration. These three are its
        # load-bearing markers.
        Assert-Contains $page '-webkit-box-reflect' 'Cover Flow reflections'
        Assert-Contains $page 'repeating-linear-gradient' 'brushed metal chassis'
        Assert-Contains $page '--amber' 'amber VFD palette'
        Assert-Equal 200 ([int](Invoke-WebRequest "$($s.BaseUrl)/gallery.js" -UseBasicParsing).StatusCode)
    } finally { Stop-RunboxServer $s }
}

Register-Test 'Service :: launch_runs_the_template_for_a_real_game' {
    $s = $null; $root = New-TempTree 'launchok'
    try {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'games\demo'))
        # The template is handed to a shell as one argument, so it deliberately
        # contains no redirection, pipes or quotes. Proving those survive nested
        # quoting is not this test's job; proving the template runs is.
        $marker = Join-Path $root 'launched-marker'
        $s = Start-RunboxServer -Port 7907 -Root $root -Launch "mkdir $marker"
        $res = Invoke-Json "$($s.BaseUrl)/api/launch/demo" -Method POST
        Assert-Equal 200 $res.Status
        Assert-True ($res.Json.pid -gt 0) 'a real process id must come back'
        Start-Sleep -Milliseconds 1500
        Assert-True (Test-Path $marker) 'the launch template must actually have run'
    } finally { Stop-RunboxServer $s; Remove-TempTree $root }
}

Register-Test 'Service :: launch_refuses_anything_not_in_the_games_directory' {
    $s = $null; $root = New-TempTree 'launchbad'
    try {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $root 'games\demo'))
        $marker = Join-Path $root 'should-not-exist.txt'
        # Validation is against the real directory listing, not string cleaning,
        # because this route is the only place the service executes anything.
        $s = Start-RunboxServer -Port 7908 -Root $root -Launch "echo pwned > `"$marker`""
        foreach ($bad in @('nosuchgame', '..%2F..%2FWindows', '..%5Cdemo', '%2E%2E%2Fdemo')) {
            $status = 0
            try { $status = [int](Invoke-WebRequest "$($s.BaseUrl)/api/launch/$bad" -Method POST -UseBasicParsing -TimeoutSec 10).StatusCode }
            catch { $status = [int]$_.Exception.Response.StatusCode }
            Assert-NotEqual 200 $status "[$bad] must be refused"
        }
        Start-Sleep -Milliseconds 800
        Assert-True (-not (Test-Path $marker)) 'nothing may execute for a refused name'
    } finally { Stop-RunboxServer $s; Remove-TempTree $root }
}
