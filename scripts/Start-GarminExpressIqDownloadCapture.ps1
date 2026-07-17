param(
    [string]$CaptureScript = "",
    [string]$OutDir = "",
    [int]$TimeoutSeconds = 300,
    [int]$PollMilliseconds = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($CaptureScript)) {
    $CaptureScript = Join-Path $scriptRoot "Capture-GarminExpressIqDownloads.ps1"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\garmin-express-iq-download-captures"
}
if (-not (Test-Path -LiteralPath $CaptureScript)) {
    throw "Capture script not found: $CaptureScript"
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$runDir = Join-Path $OutDir ("active-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$stdout = Join-Path $runDir "watcher-output.txt"
$stderr = Join-Path $runDir "watcher-error.txt"
$childOutDir = Join-Path $runDir "captures"
New-Item -ItemType Directory -Force -Path $childOutDir | Out-Null

$childLines = @(
    '$ErrorActionPreference = "Stop"',
    "& $(ConvertTo-PowerShellLiteral $CaptureScript) -OutDir $(ConvertTo-PowerShellLiteral $childOutDir) -TimeoutSeconds $TimeoutSeconds -PollMilliseconds $PollMilliseconds"
)
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($childLines -join "`r`n")))

$process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$record = [pscustomobject]@{
    started_at = (Get-Date).ToString("O")
    pid = $process.Id
    run_dir = $runDir
    capture_script = (Resolve-Path -LiteralPath $CaptureScript).Path
    capture_out_dir = $childOutDir
    stdout = $stdout
    stderr = $stderr
    timeout_seconds = $TimeoutSeconds
    poll_milliseconds = $PollMilliseconds
}
$record | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $runDir "process.json") -Encoding UTF8

Write-Host "Started Garmin Express IQ download capture."
Write-Host "PID: $($process.Id)"
Write-Host "Run folder: $runDir"
Write-Host "Now install one IQ Store app in Garmin Express while this watcher is running."
Write-Host "After Express finishes syncing, inspect watcher-output.txt and captures\capture-*\captures.json."
