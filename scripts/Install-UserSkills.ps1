param([string]$Destination)
$ErrorActionPreference = 'Stop'
$migrationWorkspace = Split-Path -Parent $PSScriptRoot
if (-not $Destination) {
    $migrationCodexDirectory = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $Destination = Join-Path $migrationCodexDirectory 'skills'
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
foreach ($migrationSkill in Get-ChildItem -LiteralPath (Join-Path $migrationWorkspace '.agents/skills') -Directory) {
    $migrationTarget = Join-Path $Destination $migrationSkill.Name
    if (Test-Path -LiteralPath $migrationTarget) {
        Write-Host "Kept existing skill: $($migrationSkill.Name)"
    } else {
        Copy-Item -LiteralPath $migrationSkill.FullName -Destination $migrationTarget -Recurse
        Write-Host "Installed: $($migrationSkill.Name)"
    }
}
Write-Host 'Reopen the workspace in the Agent client to refresh skill discovery.'
