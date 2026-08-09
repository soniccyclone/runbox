<#
  Verdicts: the only datum in this system that cannot be regenerated.

  Every measurement can be recomputed by re-running. A human judgment about
  whether something is fun cannot, and run output trees are gitignored and
  routinely deleted. That is the whole reason these tests exist.
#>

function New-VerdictFixture {
    param([string]$Tag)
    $out = New-TempTree "verdict-$Tag"
    New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'floaty' -RunAt '2026-08-01T10:00:00.0000000Z' -Span 117.0 | Out-Null
    New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'stock'  -RunAt '2026-08-01T11:00:00.0000000Z' -Span 138.7 | Out-Null
    New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'poppy'  -RunAt '2026-08-01T12:00:00.0000000Z' -Span 164.7 | Out-Null
    return $out
}

Register-Test 'Verdict :: outlives_the_process_that_recorded_it' {
    $s = $null; $out = New-VerdictFixture 'restart'
    $store = Join-Path $env:TEMP "runbox-store-restart-$PID.json"
    try {
        if (Test-Path $store) { Remove-Item $store -Force }
        $q = "out=$([uri]::EscapeDataString($out))&store=$([uri]::EscapeDataString($store))"

        $s = Start-RunboxServer -Port 7921
        Invoke-Json "$($s.BaseUrl)/api/verdict?$q" -Method POST -Body @{ id = 'g/s/stock'; liked = $true } | Out-Null
        Stop-RunboxServer $s; $s = $null

        $s = Start-RunboxServer -Port 7922
        $stock = @((Invoke-Json "$($s.BaseUrl)/api/runs?$q").Json) | Where-Object { $_.runId -eq 'stock' }
        Assert-Equal 'liked' ([string]$stock.verdict)
    } finally { Stop-RunboxServer $s; Remove-TempTree $out; Remove-Item $store -Force -ErrorAction SilentlyContinue }
}

Register-Test 'Verdict :: belongs_to_one_run_not_to_the_scenario' {
    $s = $null; $out = New-VerdictFixture 'rerun'
    $store = Join-Path $env:TEMP "runbox-store-rerun-$PID.json"
    try {
        if (Test-Path $store) { Remove-Item $store -Force }
        $q = "out=$([uri]::EscapeDataString($out))&store=$([uri]::EscapeDataString($store))"
        $s = Start-RunboxServer -Port 7923
        Invoke-Json "$($s.BaseUrl)/api/verdict?$q" -Method POST -Body @{ id = 'g/s/stock'; liked = $true } | Out-Null

        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'newer' -RunAt '2026-08-01T13:00:00.0000000Z' -Span 150 | Out-Null

        $runs = @((Invoke-Json "$($s.BaseUrl)/api/runs?$q").Json)
        Assert-Equal 'liked' ([string]($runs | Where-Object { $_.runId -eq 'stock' }).verdict)
        Assert-Equal ''      ([string]($runs | Where-Object { $_.runId -eq 'newer' }).verdict) 'a new run starts unmarked'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out; Remove-Item $store -Force -ErrorAction SilentlyContinue }
}

Register-Test 'Verdict :: survives_the_run_tree_being_regenerated' {
    $s = $null; $out = New-VerdictFixture 'regen'
    $store = Join-Path $env:TEMP "runbox-store-regen-$PID.json"
    try {
        if (Test-Path $store) { Remove-Item $store -Force }
        $q = "out=$([uri]::EscapeDataString($out))&store=$([uri]::EscapeDataString($store))"
        $s = Start-RunboxServer -Port 7924
        Invoke-Json "$($s.BaseUrl)/api/verdict?$q" -Method POST -Body @{ id = 'g/s/stock'; liked = $true } | Out-Null

        # Delete and rebuild the whole reproducible output tree, as a clean would.
        [System.IO.Directory]::Delete($out, $true)
        [void][System.IO.Directory]::CreateDirectory($out)
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'stock' -RunAt '2026-08-01T11:00:00.0000000Z' -Span 138.7 | Out-Null

        $stock = @((Invoke-Json "$($s.BaseUrl)/api/runs?$q").Json) | Where-Object { $_.runId -eq 'stock' }
        Assert-Equal 'liked' ([string]$stock.verdict) 'a judgment must not be destroyed by regenerating output'
        Assert-True (Test-Path $store) 'the store must live outside the run tree'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out; Remove-Item $store -Force -ErrorAction SilentlyContinue }
}

Register-Test 'Verdict :: preferred_runs_are_queryable' {
    $s = $null; $out = New-VerdictFixture 'query'
    $store = Join-Path $env:TEMP "runbox-store-query-$PID.json"
    try {
        if (Test-Path $store) { Remove-Item $store -Force }
        $q = "out=$([uri]::EscapeDataString($out))&store=$([uri]::EscapeDataString($store))"
        $s = Start-RunboxServer -Port 7925
        Invoke-Json "$($s.BaseUrl)/api/verdict?$q" -Method POST -Body @{ id = 'g/s/poppy'; liked = $true } | Out-Null

        $pref = @((Invoke-Json "$($s.BaseUrl)/api/preferred/g?$q").Json)
        Assert-Equal 1 $pref.Count
        Assert-Equal 'poppy' ([string]$pref[0].runId)
        Assert-Equal 164.7 ([math]::Round([double]$pref[0].measured, 1)) 'what produced it comes with it'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out; Remove-Item $store -Force -ErrorAction SilentlyContinue }
}

Register-Test 'Verdict :: an_unmade_judgment_is_never_invented' {
    $s = $null; $out = New-VerdictFixture 'nopref'
    $store = Join-Path $env:TEMP "runbox-store-nopref-$PID.json"
    try {
        if (Test-Path $store) { Remove-Item $store -Force }
        $q = "out=$([uri]::EscapeDataString($out))&store=$([uri]::EscapeDataString($store))"
        $s = Start-RunboxServer -Port 7926
        # Nothing marked. Not the newest, not the best-measuring. Nothing.
        Assert-Equal 0 (@((Invoke-Json "$($s.BaseUrl)/api/preferred/g?$q").Json).Count)
    } finally { Stop-RunboxServer $s; Remove-TempTree $out; Remove-Item $store -Force -ErrorAction SilentlyContinue }
}
