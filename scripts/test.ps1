param(
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
& $Python -m pytest
if ($LASTEXITCODE -ne 0) { throw "pytest failed" }
