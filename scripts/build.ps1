param(
    [string]$Python = "python",
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
if (-not $SkipTests) {
    & $Python -m pytest
    if ($LASTEXITCODE -ne 0) { throw "pytest failed" }
}
Write-Host "No packaged executable is built by default. Use GitHub Releases for known-good packaged sender builds."
