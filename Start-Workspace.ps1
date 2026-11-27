param([switch]$SkipGit)
$ErrorActionPreference = 'Stop'
$migrationWorkspace = $PSScriptRoot
Set-Location -LiteralPath $migrationWorkspace
$migrationTools = @("$migrationWorkspace/tools/python", "$migrationWorkspace/tools/node", "$migrationWorkspace/tools/poppler")
$env:PATH = ($migrationTools -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH
if (-not $SkipGit) {
    if (-not (Test-Path -LiteralPath (Join-Path $migrationWorkspace '.git'))) {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            & git init --initial-branch=codex/competition $migrationWorkspace
            if ($LASTEXITCODE -ne 0) { throw 'Git initialization failed.' }
        } else {
            Write-Warning 'Git is not installed. Install it before starting development.'
        }
    }
}
Write-Host "Workspace: $migrationWorkspace"
Write-Host 'Bundled Python, Node and Poppler are on PATH in this PowerShell session.'
Write-Host 'Next: read AGENTS.md and handoff/接手说明.md; check Godot and model access.'
