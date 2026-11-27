param([switch]$Quick)
$ErrorActionPreference = 'Stop'
$migrationWorkspace = Split-Path -Parent $PSScriptRoot
$migrationPython = Join-Path $migrationWorkspace 'tools/python/python.exe'
if (-not (Test-Path -LiteralPath $migrationPython)) { throw 'Bundled Windows Python is missing. Extract the entire ZIP.' }
$migrationArguments = @((Join-Path $PSScriptRoot 'verify_workspace.py'))
if ($Quick) { $migrationArguments += '--quick' }
& $migrationPython @migrationArguments
if ($LASTEXITCODE -ne 0) { throw 'Workspace integrity check failed. See the report above.' }
