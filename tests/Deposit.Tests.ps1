<#
  The deposit CLI: what `npx github:soniccyclone/runbox init` does.

  runbox is a skill first and a Windows tool second, so the skill has to reach
  whichever agent the project actually uses. Each target owns its own path, and
  getting one wrong means the skill is installed and invisible.

  These drive the real CLI rather than importing its modules. What matters is
  where files land on disk, and only running it answers that.
#>

Register-Test 'Deposit :: lands in the directory the agent reads' {
    $proj = New-TempTree 'dep-one'
    try {
        New-FakeProject $proj
        Invoke-Deposit -In $proj -Agents claude | Out-Null
        Assert-True (Test-Path (Join-Path $proj '.claude\skills\runbox\SKILL.md')) 'Claude Code reads .claude\skills'
    } finally { Remove-TempTree $proj }
}

Register-Test 'Deposit :: every agent gets its own path' {
    $proj = New-TempTree 'dep-many'
    try {
        New-FakeProject $proj
        Invoke-Deposit -In $proj -Agents claude, cursor, copilot, opencode | Out-Null

        # Copilot is the one that differs from its own detection marker: it is
        # detected by files in .github but reads skills from .github\skills.
        foreach ($p in @('.claude\skills\runbox', '.cursor\skills\runbox',
                         '.github\skills\runbox', '.opencode\skills\runbox')) {
            Assert-True (Test-Path (Join-Path $proj "$p\SKILL.md")) "$p must carry the skill"
        }
    } finally { Remove-TempTree $proj }
}

Register-Test 'Deposit :: ships the deliverable and nothing else' {
    $proj = New-TempTree 'dep-payload'
    try {
        New-FakeProject $proj
        Invoke-Deposit -In $proj -Agents claude | Out-Null
        $dest = Join-Path $proj '.claude\skills\runbox'

        # AGENTS.md is instructions for maintaining runbox. Delivered into a game
        # project it tells an agent to do the wrong job entirely. Nothing named
        # here is excluded by a list any more; the payload boundary is the whole
        # mechanism, so this is what guards it.
        foreach ($leak in @('AGENTS.md', 'README.md', 'test.ps1', 'tests', 'package.json', 'src', 'bin')) {
            Assert-True (-not (Test-Path (Join-Path $dest $leak))) "$leak is the workshop and must not ship"
        }

        # FINDINGS.md is the deliberate exception: the rules in SKILL.md read as
        # arbitrary without it, and an agent that cannot see why will fit a
        # calibration constant eventually.
        foreach ($want in @('SKILL.md', 'FINDINGS.md', 'install.ps1', 'reference\run-contract.md', 'tool\serve.cs')) {
            Assert-True (Test-Path (Join-Path $dest $want)) "$want is part of the deliverable"
        }
    } finally { Remove-TempTree $proj }
}

Register-Test 'Deposit :: rerunning is the update path' {
    $proj = New-TempTree 'dep-update'
    try {
        New-FakeProject $proj
        Invoke-Deposit -In $proj -Agents claude | Out-Null

        $skill = Join-Path $proj '.claude\skills\runbox\SKILL.md'
        [IO.File]::WriteAllText($skill, 'stale', (New-Object System.Text.UTF8Encoding($false)))
        Invoke-Deposit -In $proj -Agents claude | Out-Null

        Assert-NotContains ([IO.File]::ReadAllText($skill)) 'stale' 'the payload is ours, so a rerun replaces it'
    } finally { Remove-TempTree $proj }
}

Register-Test 'Deposit :: leaves other skills in the directory alone' {
    $proj = New-TempTree 'dep-neighbours'
    try {
        New-FakeProject $proj
        $other = Join-Path $proj '.claude\skills\something-else'
        [void][System.IO.Directory]::CreateDirectory($other)
        [IO.File]::WriteAllText((Join-Path $other 'SKILL.md'), 'not ours', (New-Object System.Text.UTF8Encoding($false)))

        Invoke-Deposit -In $proj -Agents claude | Out-Null

        Assert-Contains ([IO.File]::ReadAllText((Join-Path $other 'SKILL.md'))) 'not ours' 'only the directories we ship are touched'
    } finally { Remove-TempTree $proj }
}

Register-Test 'Deposit :: refuses an agent it does not know' {
    $proj = New-TempTree 'dep-unknown'
    try {
        New-FakeProject $proj
        $r = Invoke-Deposit -In $proj -Agents 'emacs' -AllowFailure
        Assert-NotEqual 0 $r.ExitCode 'an unknown target must not silently install nowhere'
        Assert-Contains $r.Output 'unknown target'
    } finally { Remove-TempTree $proj }
}
