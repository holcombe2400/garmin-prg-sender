param(
    [string]$Address = "F0:99:19:75:41:3E",
    [string]$Name = "",
    [ValidateSet("auto", "cached", "uncached")]
    [string]$WinrtServices = "uncached",
    [ValidateSet("sync-install-type0", "none")]
    [string]$PostUploadTrigger = "none",
    [string]$OutDir = "",
    [string]$NamePrefix = "PhoneSync Probe",
    [string]$Device = "fenix6pro",
    [int]$ConnectTimeout = 75,
    [int]$Timeout = 30,
    [int]$SyncTimeout = 20,
    [int]$ProgressStep = 5,
    [int]$UploadRetries = 5,
    [int]$PacketLogBytes = 256,
    [int]$PreflightTimeout = 20,
    [switch]$SkipPreflight,
    [switch]$WaitForPhoneSync,
    [switch]$ShowInstalledApps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\phone-sync-stage-experiments"
}

$generator = Join-Path $scriptRoot "New-CiqInstallProbe.ps1"
$sender = Join-Path $projectRoot "send_prg.py"
$python = Join-Path $projectRoot ".runtime\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) {
    $python = Join-Path $projectRoot ".venv\Scripts\python.exe"
}
foreach ($path in @($generator, $sender, $python)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file not found: $path"
    }
}
if ([string]::IsNullOrWhiteSpace($Address) -and [string]::IsNullOrWhiteSpace($Name)) {
    throw "Provide -Address or -Name."
}

function Save-Json {
    param(
        [string]$Path,
        [object]$Value
    )
    $Value | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function Save-Lines {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    $Lines | Set-Content -Path $Path -Encoding UTF8
}

function Add-TargetArgs {
    param([string[]]$CommandArgs)
    if (-not [string]::IsNullOrWhiteSpace($Address)) {
        return $CommandArgs + @("--address", $Address)
    }
    return $CommandArgs + @("--name", $Name)
}

$session = Join-Path $OutDir ("phone-sync-stage-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$probeRoot = Join-Path $session "probe"
$runRoot = Join-Path $session "run"
New-Item -ItemType Directory -Force -Path $probeRoot, $runRoot | Out-Null

Write-Host "Phone-sync stage experiment: $session"
if (-not [string]::IsNullOrWhiteSpace($Address)) {
    Write-Host "BLE target address: $Address"
} else {
    Write-Host "BLE target name: $Name"
}
Write-Host "Post-upload trigger: $PostUploadTrigger"
Write-Host ""

$preflightOutputPath = Join-Path $runRoot "preflight-winrt-diagnostic.txt"
if (-not $SkipPreflight -and -not [string]::IsNullOrWhiteSpace($Address)) {
    Write-Host "Preflight: checking Windows pairing/live GATT before building a fresh probe..."
    $preflightArgs = @(
        "-B",
        $sender,
        "--winrt-diagnostic",
        "--address",
        $Address,
        "--connect-timeout",
        [string]$PreflightTimeout,
        "--debug"
    )
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $preflightOutput = & $python @preflightArgs 2>&1
        $preflightExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $preflightOutput | Tee-Object -FilePath $preflightOutputPath
    $preflightText = $preflightOutput -join "`n"
    $notPaired = $preflightText -match "Is paired:\s*False"
    $gattUnreachable = $preflightText -match "Live GATT services:\s*unreachable"
    $liveGattSuccess = $preflightText -match "Live GATT services:\s*Status:\s*success"
    if (-not $liveGattSuccess) {
        $failedPath = Join-Path $session "PRECHECK-FAILED.txt"
        Save-Lines $failedPath @(
            "Windows BLE preflight failed before generating a fresh probe.",
            "",
            "Why this matters:",
            "  The PC must be paired to the watch and able to open live GATT before it can stage the PRG.",
            "  The iPhone/Garmin Connect pairing is used after staging, to trigger Connect IQ registration.",
            "",
            "Observed:",
            "  Preflight exit code: $preflightExitCode",
            "  Is paired false: $notPaired",
            "  Live GATT unreachable: $gattUnreachable",
            "  Live GATT success: $liveGattSuccess",
            "",
            "Recommended sequence:",
            "  1. Temporarily stop the iPhone from owning the watch BLE connection.",
            "     Best options: Settings > Bluetooth > fenix > Forget This Device, or fully turn off Bluetooth in Settings.",
            "  2. Pair the fenix to Windows Bluetooth.",
            "  3. Rerun this script.",
            "  4. After staging succeeds, pair/reconnect the iPhone in Garmin Connect and sync.",
            "",
            "Preflight log:",
            "  $preflightOutputPath"
        )
        Save-Json (Join-Path $session "summary.json") ([ordered]@{
            created_at = (Get-Date).ToString("O")
            session = $session
            stage_succeeded = $false
            preflight_exit_code = $preflightExitCode
            preflight_not_paired = $notPaired
            preflight_gatt_unreachable = $gattUnreachable
            preflight_live_gatt_success = $liveGattSuccess
            preflight_output = $preflightOutputPath
            precheck_failed = $failedPath
        })
        Write-Host ""
        Write-Host "Preflight failed before generating a fresh probe."
        Write-Host "Details: $failedPath"
        exit 2
    }
    if ($notPaired) {
        Write-Host "Preflight passed: live GATT is reachable even though Windows reports Is paired False."
    } else {
        Write-Host "Preflight passed."
    }
    Write-Host ""
} elseif (-not $SkipPreflight) {
    Write-Host "Preflight skipped because -Address was not supplied. Name-based runs will be checked during staging."
    Write-Host ""
}

$generatorOutputPath = Join-Path $runRoot "probe-generation-output.txt"
$beforeProbeDirs = @{}
foreach ($dir in Get-ChildItem -LiteralPath $probeRoot -Directory -ErrorAction SilentlyContinue) {
    $beforeProbeDirs[$dir.FullName] = $true
}

Write-Host "Generating fresh install-proof PRG..."
$generatorOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $generator -OutputRoot $probeRoot -NamePrefix $NamePrefix -Device $Device 2>&1
$generatorExitCode = $LASTEXITCODE
$generatorOutput | Tee-Object -FilePath $generatorOutputPath
if ($generatorExitCode -ne 0) {
    throw "Probe generation failed with exit code $generatorExitCode. See $generatorOutputPath"
}

$probeDir = Get-ChildItem -LiteralPath $probeRoot -Directory |
    Where-Object { -not $beforeProbeDirs.ContainsKey($_.FullName) } |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1
if ($null -eq $probeDir) {
    $probeDir = Get-ChildItem -LiteralPath $probeRoot -Directory |
        Sort-Object CreationTime -Descending |
        Select-Object -First 1
}
if ($null -eq $probeDir) {
    throw "Could not find generated probe directory."
}

$metadataPath = Join-Path $probeDir.FullName "metadata.json"
if (-not (Test-Path -LiteralPath $metadataPath)) {
    throw "Could not find generated probe metadata: $metadataPath"
}
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$prg = [string]$metadata.prg_path
if (-not (Test-Path -LiteralPath $prg)) {
    throw "Generated PRG was not found: $prg"
}

$safeBase = ([string]$metadata.file_base) -replace "[^A-Za-z0-9_.-]", "_"
$stageOutputPath = Join-Path $runRoot "$safeBase-stage-output.txt"
$packetLogPath = Join-Path $runRoot "$safeBase-stage-packets.jsonl"
$packetSummaryPath = Join-Path $runRoot "$safeBase-stage-packet-summary.txt"
$nextStepsPath = Join-Path $session "NEXT-STEPS.txt"
$summaryPath = Join-Path $session "summary.json"

Write-Host ""
Write-Host "Staging fresh PRG for Garmin Connect phone sync..."
Write-Host "App name: $($metadata.app_name)"
Write-Host "App id:   $($metadata.app_id_dashed)"
Write-Host "PRG:      $prg"
Write-Host "Packets:  $packetLogPath"

$stageArgs = @(
    "-B",
    $sender,
    "--stage-for-garmin-connect",
    "--file",
    $prg,
    "--winrt-services",
    $WinrtServices,
    "--connect-timeout",
    [string]$ConnectTimeout,
    "--timeout",
    [string]$Timeout,
    "--sync-timeout",
    [string]$SyncTimeout,
    "--post-upload-trigger",
    $PostUploadTrigger,
    "--progress-step",
    [string]$ProgressStep,
    "--upload-retries",
    [string]$UploadRetries,
    "--verify-app-id",
    [string]$metadata.app_id_dashed,
    "--verify-app-name",
    [string]$metadata.app_name,
    "--packet-log",
    $packetLogPath,
    "--packet-log-bytes",
    [string]$PacketLogBytes,
    "--debug"
)
$stageArgs = Add-TargetArgs $stageArgs

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $stageOutput = & $python @stageArgs 2>&1
    $stageExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
$stageOutput | Tee-Object -FilePath $stageOutputPath

if (Test-Path -LiteralPath $packetLogPath) {
    $summaryOutput = & $python -B $sender --summarize-log $packetLogPath 2>&1
    $summaryOutput | Tee-Object -FilePath $packetSummaryPath
}

$stageSucceeded = $stageExitCode -eq 0 -and (($stageOutput -join "`n") -match "PRG staged for Garmin Connect phone sync")
$summary = [ordered]@{
    created_at = (Get-Date).ToString("O")
    session = $session
    app_name = [string]$metadata.app_name
    app_id = [string]$metadata.app_id_dashed
    file_base = [string]$metadata.file_base
    prg_path = $prg
    prg_size = if ($metadata.PSObject.Properties.Name -contains "prg_size") { [int64]$metadata.prg_size } else { $null }
    post_upload_trigger = $PostUploadTrigger
    stage_exit_code = $stageExitCode
    stage_succeeded = $stageSucceeded
    generator_output = $generatorOutputPath
    stage_output = $stageOutputPath
    packet_log = $packetLogPath
    packet_summary = if (Test-Path -LiteralPath $packetSummaryPath) { $packetSummaryPath } else { $null }
    next_steps = $nextStepsPath
}

Save-Lines $nextStepsPath @(
    "Phone-sync stage experiment",
    "",
    "Experiment folder:",
    $session,
    "",
    "Staged app to look for:",
    "  Name: $($metadata.app_name)",
    "  UUID: $($metadata.app_id_dashed)",
    "  File: $($metadata.file_base)",
    "  PRG:  $prg",
    "",
    "Result:",
    "  Stage exit code: $stageExitCode",
    "  Stage succeeded: $stageSucceeded",
    "  Post-upload trigger: $PostUploadTrigger",
    "",
    "If staging failed before progress reached 100%:",
    "  - The watch must be paired to Windows Bluetooth for the PC staging step.",
    "  - Garmin Connect phone pairing is only needed after staging, for the install/registration sync.",
    "  - If the output mentions WinRT, GATT, CancelledError, or TimeoutError, put the watch in pairing mode, pair it in Windows, then rerun this script.",
    "",
    "Next steps on the phone/watch:",
    "  1. Open Garmin Connect on the paired phone.",
    "  2. Make sure this watch connects to the phone.",
    "  3. Force a sync or wait for Garmin Connect to sync.",
    "  4. Watch for: Garmin Connect IQ - $($metadata.app_name) has been installed to your device.",
    "  5. If it installs, rerun this script with -PostUploadTrigger none to test whether the extra trigger is needed.",
    "",
    "Verification command:",
    "  .\.runtime\Scripts\python.exe -B .\send_prg.py --query-installed-apps --address `"$Address`" --winrt-services $WinrtServices --connect-timeout $ConnectTimeout --timeout $Timeout --verify-app-id `"$($metadata.app_id_dashed)`" --verify-app-name `"$($metadata.app_name)`" --debug",
    "",
    "Logs:",
    "  Stage output: $stageOutputPath",
    "  Packet log:   $packetLogPath",
    "  Summary:      $packetSummaryPath"
)

if ($WaitForPhoneSync -and $stageSucceeded) {
    Write-Host ""
    Write-Host "Open Garmin Connect, sync the watch, and watch for the install message."
    Read-Host "Press Enter after Garmin Connect sync finishes"

    $verifyOutputPath = Join-Path $runRoot "$safeBase-verify-output.txt"
    $verifyPacketLogPath = Join-Path $runRoot "$safeBase-verify-packets.jsonl"
    $verifyArgs = @(
        "-B",
        $sender,
        "--query-installed-apps",
        "--winrt-services",
        $WinrtServices,
        "--connect-timeout",
        [string]$ConnectTimeout,
        "--timeout",
        [string]$Timeout,
        "--verify-app-id",
        [string]$metadata.app_id_dashed,
        "--verify-app-name",
        [string]$metadata.app_name,
        "--packet-log",
        $verifyPacketLogPath,
        "--packet-log-bytes",
        [string]$PacketLogBytes,
        "--debug"
    )
    $verifyArgs = Add-TargetArgs $verifyArgs
    if ($ShowInstalledApps) {
        $verifyArgs += "--show-installed-apps"
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $verifyOutput = & $python @verifyArgs 2>&1
        $verifyExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $verifyOutput | Tee-Object -FilePath $verifyOutputPath
    $registered = (($verifyOutput -join "`n") -match ([regex]::Escape([string]$metadata.app_name) + " is registered"))

    $summary["verify_exit_code"] = $verifyExitCode
    $summary["verify_registered"] = $registered
    $summary["verify_output"] = $verifyOutputPath
    $summary["verify_packet_log"] = $verifyPacketLogPath

    Write-Host ""
    if ($registered) {
        Write-Host "Phone-sync proof succeeded: $($metadata.app_name) is registered."
    } else {
        Write-Host "Phone-sync proof not confirmed yet: $($metadata.app_name) was not reported registered."
    }
}

Save-Json $summaryPath $summary

Write-Host ""
Write-Host "Experiment folder: $session"
Write-Host "Next steps:        $nextStepsPath"
Write-Host "Summary:           $summaryPath"
if (-not $stageSucceeded) {
    Write-Host "Stage did not complete cleanly. See $stageOutputPath"
    exit $stageExitCode
}
exit 0
