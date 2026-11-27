param([switch]$Quick)
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$repositoryPython = Get-Command python -ErrorAction SilentlyContinue
if ($repositoryPython) {
    $repositoryPythonPath = $repositoryPython.Source
} elseif (Test-Path -LiteralPath (Join-Path $repositoryRoot 'tools/python/python.exe')) {
    $repositoryPythonPath = Join-Path $repositoryRoot 'tools/python/python.exe'
} else {
    throw 'Python 3.12 is required. Bundled document tools are optional.'
}
if ($Quick) { Write-Host '-Quick is retained for compatibility; portable checks always run in full.' }
Push-Location -LiteralPath $repositoryRoot
try {
    & $repositoryPythonPath -m unittest discover -s tests -v
    if ($LASTEXITCODE -ne 0) { throw 'Repository tests failed.' }
    & $repositoryPythonPath scripts/check_repository.py
    if ($LASTEXITCODE -ne 0) { throw 'Repository content check failed.' }
    & $repositoryPythonPath scripts/check_project_links.py --all
    if ($LASTEXITCODE -ne 0) { throw 'Project link check failed.' }
} finally {
    Pop-Location
}
