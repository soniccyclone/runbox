<#
  The installer is the whole of "installable", so it is tested like a surface
  rather than trusted like a script.

  The case that earns most of this file is the plugin one. Installed as a plugin
  the skill sits outside the project entirely, so a target derived from the
  script's own location lands in the plugin cache and the generated wrapper
  points at a path that does not exist. Both shapes are exercised here.
#>

Register-Test 'Install :: targets the project the caller is standing in' {
    $proj = New-TempTree 'inst-cwd'
    try {
        New-FakeProject $proj
        $skill = Install-SkillCopy $proj
        Invoke-Installer -Skill $skill -From $proj | Out-Null

        Assert-True (Test-Path (Join-Path $proj 'harness\serve.ps1')) 'the wrapper belongs to the project, not to the skill'
    } finally { Remove-TempTree $proj }
}

Register-Test 'Install :: a copied-in skill is referenced relatively' {
    $proj = New-TempTree 'inst-rel'
    try {
        New-FakeProject $proj
        $skill = Install-SkillCopy $proj
        Invoke-Installer -Skill $skill -From $proj | Out-Null

        $wrapper = Join-Path $proj 'harness\serve.ps1'
        $line = Get-WrapperServeLine $wrapper
        # Relative so the project survives being cloned to another path.
        Assert-Contains $line 'Join-Path' 'a skill inside the project must not be pinned to this machine'
        Assert-NotContains $line $proj 'an absolute project path would not survive a clone'
        Assert-True (Test-Path (Resolve-WrapperServe $wrapper $proj)) 'and it still has to resolve'
    } finally { Remove-TempTree $proj }
}

Register-Test 'Install :: a skill outside the project is referenced absolutely' {
    $proj = New-TempTree 'inst-abs'
    $cache = New-TempTree 'inst-cache'
    try {
        New-FakeProject $proj
        # What a plugin install looks like: the skill is not in the project at all.
        $skill = Join-Path $cache 'runbox'
        Copy-Item (Get-SkillRoot) $skill -Recurse
        Invoke-Installer -Skill $skill -From $proj | Out-Null

        $wrapper = Join-Path $proj 'harness\serve.ps1'
        $resolved = Resolve-WrapperServe $wrapper $proj
        Assert-True (Test-Path $resolved) 'a plugin-installed skill has no relative form, so the wrapper must carry the real path'
        Assert-Contains $resolved $cache 'and it must point back at the plugin, not into the project'
    } finally { Remove-TempTree $proj; Remove-TempTree $cache }
}

Register-Test 'Install :: refuses to install runbox into runbox' {
    $threw = $false
    try {
        Invoke-Installer -Skill (Get-SkillRoot) -From (Get-RepoRoot) | Out-Null
    } catch { $threw = $true; Assert-Contains $_.Exception.Message 'runbox repo' }
    Assert-True $threw 'installing into the source tree is never what anyone meant'
}

Register-Test 'Install :: writes gitignore without disturbing what is there' {
    $proj = New-TempTree 'inst-gi'
    try {
        New-FakeProject $proj
        # No trailing newline: the case that silently glues entries together.
        $gi = Join-Path $proj '.gitignore'
        [IO.File]::WriteAllText($gi, "node_modules/", (New-Object System.Text.UTF8Encoding($false)))

        $skill = Install-SkillCopy $proj
        Invoke-Installer -Skill $skill -From $proj | Out-Null

        $lines = @(Get-Content $gi)
        Assert-True ($lines -contains 'node_modules/') 'existing entries survive'
        Assert-True ($lines -contains '.harness-out/') 'run output is ignored'
        Assert-True ($lines -contains '.harness-verdicts.json') 'verdicts are ignored'
    } finally { Remove-TempTree $proj }
}

Register-Test 'Install :: is safe to run twice' {
    $proj = New-TempTree 'inst-twice'
    try {
        New-FakeProject $proj
        $skill = Install-SkillCopy $proj
        Invoke-Installer -Skill $skill -From $proj | Out-Null
        Invoke-Installer -Skill $skill -From $proj | Out-Null

        $gi = Join-Path $proj '.gitignore'
        $n = @(Get-Content $gi | Where-Object { $_ -eq '.harness-out/' }).Count
        Assert-Equal 1 $n 'a re-run must not keep appending the same entry'
    } finally { Remove-TempTree $proj }
}

Register-Test 'Install :: will not clobber an edited wrapper without -Force' {
    $proj = New-TempTree 'inst-force'
    try {
        New-FakeProject $proj
        $skill = Install-SkillCopy $proj
        Invoke-Installer -Skill $skill -From $proj | Out-Null

        $wrapper = Join-Path $proj 'harness\serve.ps1'
        [IO.File]::WriteAllText($wrapper, "# hand-edited", (New-Object System.Text.UTF8Encoding($false)))

        Invoke-Installer -Skill $skill -From $proj | Out-Null
        Assert-Contains ([IO.File]::ReadAllText($wrapper)) 'hand-edited' 'an existing wrapper is the operator''s, not ours'

        Invoke-Installer -Skill $skill -From $proj -Force | Out-Null
        Assert-NotContains ([IO.File]::ReadAllText($wrapper)) 'hand-edited' '-Force is what replacing it looks like'
    } finally { Remove-TempTree $proj }
}
