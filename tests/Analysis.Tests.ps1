<#
  Timeline ordering, comparison rules, drift, and the genre-agnostic vocabulary.

  These encode the findings that motivated the tool. Read FINDINGS.md before
  changing any assertion in here; several look arbitrary and are not.
#>

Register-Test 'Analysis :: orders_by_recorded_time_not_directory_name' {
    $s = $null; $out = New-TempTree 'order'
    try {
        # Names deliberately disagree with chronology. Sorting by name inverts this.
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'aaa' -RunAt '2026-08-01T10:00:00.0000000Z' -Span 100 | Out-Null
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'zzz' -RunAt '2026-07-01T10:00:00.0000000Z' -Span 90  | Out-Null
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'mmm' -RunAt '2026-09-01T10:00:00.0000000Z' -Span 120 | Out-Null

        $s = Start-RunboxServer -Port 7911
        $runs = @((Invoke-Json "$($s.BaseUrl)/api/runs?out=$([uri]::EscapeDataString($out))").Json)
        Assert-Equal 'mmm' $runs[0].runId
        Assert-Equal 'aaa' $runs[1].runId
        Assert-Equal 'zzz' $runs[2].runId
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Analysis :: predecessor_is_the_same_scenario_only' {
    $s = $null; $out = New-TempTree 'prev'
    try {
        New-Run -OutRoot $out -Game 'g' -Scenario 'jump'  -RunId 'r1' -RunAt '2026-08-01T10:00:00.0000000Z' -Span 117   | Out-Null
        # A different scenario run BETWEEN the two. Different tape, different
        # input, therefore not a predecessor of anything in the first scenario.
        New-Run -OutRoot $out -Game 'g' -Scenario 'smoke' -RunId 's1' -RunAt '2026-08-01T11:00:00.0000000Z' -Span 5     | Out-Null
        New-Run -OutRoot $out -Game 'g' -Scenario 'jump'  -RunId 'r2' -RunAt '2026-08-01T12:00:00.0000000Z' -Span 138.7 | Out-Null

        $s = Start-RunboxServer -Port 7912
        $runs = @((Invoke-Json "$($s.BaseUrl)/api/runs?out=$([uri]::EscapeDataString($out))").Json)
        $r2 = $runs | Where-Object { $_.runId -eq 'r2' }
        Assert-Equal 'r1' $r2.prevRunId
        Assert-Equal 21.7 ([math]::Round([double]$r2.deltaMeasured, 1))
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Analysis :: first_run_reports_no_delta_rather_than_zero' {
    $s = $null; $out = New-TempTree 'firstrun'
    try {
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'only' -Span 100 | Out-Null
        $s = Start-RunboxServer -Port 7913
        $only = @((Invoke-Json "$($s.BaseUrl)/api/runs?out=$([uri]::EscapeDataString($out))").Json)[0]
        Assert-Equal $null $only.prevRunId
        # Zero would read as "no change". Nothing to compare against is different.
        Assert-Equal $null $only.deltaMeasured
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Analysis :: refuses_to_compare_different_scenarios' {
    $s = $null; $out = New-TempTree 'mismatch'
    try {
        New-Run -OutRoot $out -Game 'g' -Scenario 'jump'  -RunId 'r1' -Span 138.7 | Out-Null
        New-Run -OutRoot $out -Game 'g' -Scenario 'smoke' -RunId 's1' -Span 5     | Out-Null
        $s = Start-RunboxServer -Port 7914
        $q = "out=$([uri]::EscapeDataString($out))&a=g/jump/r1&b=g/smoke/s1"
        $res = Invoke-Json "$($s.BaseUrl)/api/compare?$q"
        Assert-Equal $false $res.Json.comparable 'frame-locking is only meaningful within one scenario'
        Assert-Contains ([string]$res.Json.reason) 'scenario'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Analysis :: delta_rows_come_from_this_projects_event_names' {
    $s = $null; $out = New-TempTree 'vocab'
    try {
        # No platformer vocabulary required. A shooter emitting these must work.
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'r1' -Span 100 -ExtraEvents @('reload','wave_cleared') | Out-Null
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'r2' -Span 120 -ExtraEvents @('reload','wave_cleared') | Out-Null

        $s = Start-RunboxServer -Port 7915
        $q = "out=$([uri]::EscapeDataString($out))&a=g/s/r1&b=g/s/r2"
        $res = Invoke-Json "$($s.BaseUrl)/api/compare?$q"
        $metrics = @($res.Json.rows | ForEach-Object { $_.metric })
        Assert-True ($metrics -contains 'reload') 'rows must follow the runs, not a baked-in list'
        Assert-True ($metrics -contains 'wave_cleared')
        Assert-True ($metrics -notcontains 'note') 'note carries no gameplay meaning'
        $row = $res.Json.rows | Where-Object { $_.metric -eq 'measured' }
        Assert-Equal 20 ([math]::Round([double]$row.delta, 1)) 'signed B minus A'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Analysis :: measured_span_bounds_are_declarable' {
    $s = $null; $out = New-TempTree 'measure'
    try {
        # A project whose span is not jump-to-land declares its own bounds.
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'r1' -Span 100 `
            -ExtraEvents @('reload') -Measure @{ from='jump'; to='reload'; abortOn='gameover'; axis='y' } | Out-Null
        $s = Start-RunboxServer -Port 7916
        $run = @((Invoke-Json "$($s.BaseUrl)/api/runs?out=$([uri]::EscapeDataString($out))").Json)[0]
        # jump y=383.9 -> reload y=0.0 on the y axis.
        Assert-Equal -383.9 ([math]::Round([double]$run.measured, 1)) 'bounds and axis both come from the run'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Analysis :: an_aborted_span_measures_nothing' {
    $s = $null; $out = New-TempTree 'abort'
    try {
        # The span never completed; the world intervened. Pairing across it
        # produced a 6.7px "jump reach" in the field, which is harmless in a
        # report and destructive when a tuner acts on it.
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'r1' -AbortSpan -Claim 126.6 | Out-Null
        $s = Start-RunboxServer -Port 7917
        $run = @((Invoke-Json "$($s.BaseUrl)/api/runs?out=$([uri]::EscapeDataString($out))").Json)[0]
        Assert-Equal $null $run.measured 'no measurement at all, rather than a wrong one'
        Assert-Equal $null $run.driftPct 'and therefore no drift'
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}

Register-Test 'Analysis :: drift_is_per_run_and_never_one_factor' {
    $s = $null; $out = New-TempTree 'drift'
    try {
        # Real values from three jump strengths. The percentage falls while the
        # absolute error holds near 12px: a fixed discretisation offset, not a
        # ratio. A constant fitted at one setting is wrong at every other.
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'floaty' -RunAt '2026-08-01T10:00:00.0000000Z' -Span 117.0 -Claim 104.6 | Out-Null
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'stock'  -RunAt '2026-08-01T11:00:00.0000000Z' -Span 138.7 -Claim 126.6 | Out-Null
        New-Run -OutRoot $out -Game 'g' -Scenario 's' -RunId 'poppy'  -RunAt '2026-08-01T12:00:00.0000000Z' -Span 164.7 -Claim 154.2 | Out-Null

        $s = Start-RunboxServer -Port 7918
        $res = Invoke-Json "$($s.BaseUrl)/api/drift/g?out=$([uri]::EscapeDataString($out))"
        $by = @{}; foreach ($d in @($res.Json.runs)) { $by[$d.runId] = $d }

        Assert-Equal 11.9 ([math]::Round([double]$by['floaty'].driftPct, 1))
        Assert-Equal 9.6  ([math]::Round([double]$by['stock'].driftPct, 1))
        Assert-Equal 6.8  ([math]::Round([double]$by['poppy'].driftPct, 1))

        Assert-NotContains $res.Raw 'calibration' 'no calibration constant may ever be emitted'
        Assert-NotContains $res.Raw 'correctionFactor'

        $pcts = @($res.Json.runs | ForEach-Object { [double]$_.driftPct })
        $spread = ($pcts | Measure-Object -Maximum).Maximum - ($pcts | Measure-Object -Minimum).Minimum
        Assert-True ($spread -gt 2.0) "percentages must not be constant (spread $spread); a fixed offset is not a ratio"
        foreach ($d in @($res.Json.runs)) {
            $a = [math]::Round([double]$d.driftAbs, 1)
            Assert-True ($a -gt 9.0 -and $a -lt 13.5) "absolute error $a should sit near 12px at every strength"
        }
    } finally { Stop-RunboxServer $s; Remove-TempTree $out }
}
