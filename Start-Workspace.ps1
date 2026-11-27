param([switch]$SkipGit)
$ErrorActionPreference = 'Stop'
$migrationWorkspace = $PSScriptRoot
Set-Location -LiteralPath $migrationWorkspace
$migrationTools = @("$migrationWorkspace/tools/python", "$migrationWorkspace/tools/node", "$migrationWorkspace/tools/poppler") | Where-Object { Test-Path -LiteralPath $_ }
if ($migrationTools.Count -gt 0) {
    $env:PATH = ($migrationTools -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH
}
if (-not $SkipGit) {
    if (-not (Test-Path -LiteralPath (Join-Path $migrationWorkspace '.git'))) {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            & git init --initial-branch=main $migrationWorkspace
            if ($LASTEXITCODE -ne 0) { throw 'Git initialization failed.' }
        } else {
            Write-Warning 'Git is not installed. Install it before starting development.'
        }
    }
}
Write-Host "Workspace: $migrationWorkspace"
Write-Host "Optional local tool folders found: $($migrationTools.Count)"
Write-Host 'Next: read README.md and CONTRIBUTING.md; run scripts/Check-Workspace.ps1.'
