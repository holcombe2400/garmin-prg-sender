param(
    [string]$Address = "F0:99:19:75:41:3E",
    [switch]$ConfirmUnpair
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$Sender = Join-Path $ProjectRoot "send_prg.py"

if (-not (Test-Path -LiteralPath $Python)) {
    throw "Python environment not found: $Python"
}
if (-not (Test-Path -LiteralPath $Sender)) {
    throw "Sender entry point not found: $Sender"
}

Write-Host "== Cached Fenix =="
& $Python -B $Sender "--list-windows-ble" "--name" "fenix" "--connect-timeout" "5"
if ($LASTEXITCODE -ne 0) {
    throw "Cached Fenix listing failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "== Windows pairing reset =="
$args = @(
    "--unpair-windows-ble",
    "--address", $Address,
    "--connect-timeout", "10"
)
if ($ConfirmUnpair) {
    $args += "--confirm-unpair"
}
& $Python -B $Sender @args
if ($LASTEXITCODE -ne 0) {
    throw "Windows pairing reset failed with exit code $LASTEXITCODE"
}

if ($ConfirmUnpair) {
    Write-Host ""
    Write-Host "Next:"
    Write-Host "1. On the watch, open Pair Phone."
    Write-Host "2. In Windows Bluetooth settings, Add device > Bluetooth."
    Write-Host "3. Choose fenix 6 Pro and accept any code on both devices."
    Write-Host "4. Run .\scripts\try-watch-upload.ps1 again."
} else {
    Write-Host ""
    Write-Host "Dry run only. To remove the Windows pairing entry, run:"
    Write-Host ".\scripts\reset-watch-pairing.ps1 -ConfirmUnpair"
}
