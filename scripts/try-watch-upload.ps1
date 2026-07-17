param(
    [string]$Address = "F0:99:19:75:41:3E",
    [string]$PrgPath = "C:\Users\holco\OneDrive\Documents\Vpet Garmin Fenix 6\apps\dpower\bin\DPowerLCD_fenix6pro.prg",
    [int]$WaitSeconds = 300
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$Sender = Join-Path $ProjectRoot "send_prg.py"
$LogDir = Join-Path $ProjectRoot "logs"
$PacketLog = Join-Path $LogDir ("upload-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".jsonl")

function Invoke-SenderStep {
    param(
        [string]$Label,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "== $Label =="
    & $Python -B $Sender @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

try {
    if (-not (Test-Path -LiteralPath $Python)) {
        throw "Python environment not found: $Python"
    }
    if (-not (Test-Path -LiteralPath $Sender)) {
        throw "Sender entry point not found: $Sender"
    }
    if (-not (Test-Path -LiteralPath $PrgPath)) {
        throw "PRG not found: $PrgPath"
    }
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

    Invoke-SenderStep "List cached Fenix" @(
        "--list-windows-ble",
        "--name", "fenix",
        "--connect-timeout", "5"
    )

    Invoke-SenderStep "Wait for live Garmin GATT" @(
        "--wait-live",
        "--address", $Address,
        "--connect-timeout", "20",
        "--wait-seconds", "$WaitSeconds",
        "--retry-seconds", "5"
    )

    Invoke-SenderStep "Probe Garmin GFDI" @(
        "--probe-gfdi",
        "--address", $Address,
        "--winrt-services", "cached",
        "--connect-timeout", "75",
        "--debug"
    )

    Invoke-SenderStep "Send PRG" @(
        "--file", $PrgPath,
        "--address", $Address,
        "--winrt-services", "cached",
        "--connect-timeout", "75",
        "--timeout", "30",
        "--sync-timeout", "20",
        "--post-sync-delay", "8",
        "--progress-step", "5",
        "--upload-retries", "5",
        "--packet-log", $PacketLog,
        "--debug"
    )

    if (Test-Path -LiteralPath $PacketLog) {
        Write-Host ""
        Write-Host "== Packet log summary =="
        & $Python -B $Sender "--summarize-log" $PacketLog
    }

    Write-Host ""
    Write-Host "Upload script completed."
    Write-Host "Packet log: $PacketLog"
} catch {
    if (Test-Path -LiteralPath $PacketLog) {
        Write-Host ""
        Write-Host "== Packet log summary =="
        & $Python -B $Sender "--summarize-log" $PacketLog
    } else {
        Write-Host ""
        Write-Host "No packet log was created. If this failed while waiting for live Garmin GATT, try:"
        Write-Host ".\scripts\reset-watch-pairing.ps1 -ConfirmUnpair"
    }
    Write-Error $_
    exit 1
}
