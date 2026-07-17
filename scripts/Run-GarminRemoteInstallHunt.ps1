param(
    [string]$Address = "F0:99:19:75:41:3E",
    [int]$ListenSeconds = 300,
    [string]$OutDir = "",
    [string]$Python = "",
    [ValidateSet("auto", "cached", "uncached")]
    [string]$WinRtServices = "uncached",
    [double]$Timeout = 5.0,
    [double]$ConnectTimeout = 75.0,
    [int]$PacketLogBytes = 2048,
    [switch]$SetupEvents,
    [switch]$NoPhoneEvents,
    [switch]$NoHttpUnknown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\remote-install-hunts"
}

function Find-Python {
    if (-not [string]::IsNullOrWhiteSpace($Python)) {
        return $Python
    }
    $candidates = @(
        (Join-Path $projectRoot ".runtime\Scripts\python.exe"),
        (Join-Path $projectRoot ".venv\Scripts\python.exe"),
        "python"
    )
    foreach ($candidate in $candidates) {
        if (($candidate -eq "python") -or (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    throw "Python was not found. Expected .runtime, .venv, or python on PATH."
}

function Write-SessionFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    $Lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$session = Join-Path $OutDir ("remote-install-hunt-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $session | Out-Null

$packetLog = Join-Path $session "protobuf-packets.jsonl"
$transcript = Join-Path $session "protobuf-listen-transcript.txt"
$summary = Join-Path $session "packet-summary.txt"
$interesting = Join-Path $session "interesting-lines.txt"
$nextSteps = Join-Path $session "NEXT-STEPS.txt"
$pythonExe = Find-Python
$sendPrg = Join-Path $projectRoot "send_prg.py"

if (-not (Test-Path -LiteralPath $sendPrg)) {
    throw "send_prg.py was not found: $sendPrg"
}

Write-SessionFile $nextSteps @(
    "Remote install hunt session: $session",
    "",
    "During the listener window, try to provoke Connect IQ/app-management traffic from the watch:",
    "- start a manual sync from the watch if available",
    "- open Phone/Connect controls and trigger sync/reconnect",
    "- open a Connect IQ app/widget that can fetch phone data",
    "- open CIQ-related app/widget settings on the watch",
    "- avoid USB during this run unless deliberately testing USB+BLE interaction",
    "- if -SetupEvents was used, this run also sent PAIR_COMPLETE and SETUP_WIZARD_COMPLETE",
    "",
    "Success signs in interesting-lines.txt:",
    "- CONNECT_IQ_HTTP_SERVICE with Http.RawRequest URL",
    "- DATA_TRANSFER_SERVICE DataDownloadRequest/DataDownloadResponse",
    "- GENERIC_ITEM_TRANSFER_SERVICE",
    "- CONNECT_IQ_INSTALLED_APPS_SERVICE messages beyond our own query traffic",
    "- unknown Smart fields clustered around app-management actions"
)

Write-Host "Garmin remote install hunt session:"
Write-Host "  $session"
Write-Host ""
Write-Host "When it connects, use the watch to provoke sync / Connect IQ / phone-data actions."
Write-Host "The listener will run for $ListenSeconds seconds."
Write-Host ""

$args = @(
    "-B",
    $sendPrg,
    "--protobuf-listen",
    "--address",
    $Address,
    "--winrt-services",
    $WinRtServices,
    "--connect-timeout",
    ([string]$ConnectTimeout),
    "--timeout",
    ([string]$Timeout),
    "--listen-seconds",
    ([string]$ListenSeconds),
    "--packet-log",
    $packetLog,
    "--packet-log-bytes",
    ([string]$PacketLogBytes),
    "--debug"
)
if (-not $NoPhoneEvents) {
    $args += "--listen-phone-events"
}
if ($SetupEvents) {
    $args += "--listen-setup-events"
}
if (-not $NoHttpUnknown) {
    $args += "--listen-http-unknown"
}

Write-Host "Running protobuf listener..."
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & $pythonExe @args 2>&1 | Tee-Object -FilePath $transcript
    $listenExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}

if (Test-Path -LiteralPath $packetLog) {
    Write-Host ""
    Write-Host "Summarizing packet log..."
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $pythonExe -B $sendPrg --summarize-log $packetLog 2>&1 | Tee-Object -FilePath $summary
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
} else {
    "Packet log was not created." | Set-Content -LiteralPath $summary -Encoding UTF8
}

$interestingRegex = "CONNECT_IQ|DATA_TRANSFER|GENERIC_ITEM_TRANSFER|INSTALLED_APPS|Http\.Raw|DataDownload|url=|Smart field (2|3|4|7|31)|UNKNOWN_SERVICE|UNKNOWN_STATUS"
$interestingLines = @()
if (Test-Path -LiteralPath $transcript) {
    $interestingLines = @(Get-Content -LiteralPath $transcript | Where-Object { $_ -match $interestingRegex })
}
if ($interestingLines.Count -eq 0) {
    $interestingLines = @(
        "No obvious Connect IQ HTTP/data-transfer/generic-item-transfer lines were found.",
        "Check protobuf-listen-transcript.txt and protobuf-packets.jsonl for the full capture."
    )
}
$interestingLines | Set-Content -LiteralPath $interesting -Encoding UTF8

Write-Host ""
Write-Host "Remote install hunt complete."
Write-Host "  transcript:  $transcript"
Write-Host "  packet log:  $packetLog"
Write-Host "  summary:     $summary"
Write-Host "  interesting: $interesting"
Write-Host "  next steps:  $nextSteps"
exit $listenExit
