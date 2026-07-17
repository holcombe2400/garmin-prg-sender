param(
    [string]$Address = "F0:99:19:75:41:3E",
    [string]$Name = "",
    [string]$WinrtServices = "cached",
    [string]$OutDir = "",
    [string[]]$Triggers = @("none", "new-download", "device-disconnect", "sync-install-type0", "sync-install-type1", "sync-install-type2", "archive-created-file", "archive-created-file-number", "sync-install-type0-8byte", "sync-install-type1-8byte", "sync-install-type2-8byte"),
    [string]$NamePrefix = "BLE Probe",
    [string]$Device = "fenix6pro",
    [int]$ConnectTimeout = 75,
    [int]$Timeout = 30,
    [int]$SyncTimeout = 20,
    [double]$VerifyDelay = 10,
    [int]$ProgressStep = 10,
    [int]$UploadRetries = 5,
    [switch]$StopOnRegistered,
    [switch]$ShowInstalledApps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\fresh-ble-experiments"
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

$validTriggers = @(
    "none",
    "new-download",
    "device-disconnect",
    "sync-install-type0",
    "sync-install-type1",
    "sync-install-type2",
    "archive-created-file",
    "archive-created-file-number",
    "sync-install-type0-8byte",
    "sync-install-type1-8byte",
    "sync-install-type2-8byte"
)
$Triggers = @(
    foreach ($trigger in $Triggers) {
        foreach ($part in ([string]$trigger).Split(",")) {
            $part.Trim()
        }
    }
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach ($trigger in $Triggers) {
    if ($validTriggers -notcontains $trigger) {
        throw "Unsupported trigger '$trigger'. Valid triggers: $($validTriggers -join ', ')"
    }
}

$session = Join-Path $OutDir ("ble-experiment-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$probeRoot = Join-Path $session "probes"
$runRoot = Join-Path $session "runs"
New-Item -ItemType Directory -Force -Path $probeRoot, $runRoot | Out-Null

Write-Host "Fresh BLE CIQ probe experiment: $session"
if (-not [string]::IsNullOrWhiteSpace($Address)) {
    Write-Host "BLE target address: $Address"
} else {
    Write-Host "BLE target name: $Name"
}
Write-Host "Triggers: $($Triggers -join ', ')"
Write-Host ""

$summary = @()
foreach ($trigger in $Triggers) {
    Write-Host "=== BLE trigger: $trigger ==="
    $beforeProbeDirs = @{}
    foreach ($dir in Get-ChildItem -LiteralPath $probeRoot -Directory) {
        $beforeProbeDirs[$dir.FullName] = $true
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $generator -OutputRoot $probeRoot -NamePrefix $NamePrefix -Device $Device
    if ($LASTEXITCODE -ne 0) {
        throw "Probe generation failed for trigger '$trigger' with exit code $LASTEXITCODE."
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
        throw "Could not find generated probe directory for trigger '$trigger'."
    }
    $metadataPath = Join-Path $probeDir.FullName "metadata.json"
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        throw "Could not find generated probe metadata for trigger '$trigger'."
    }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    $prg = [string]$metadata.prg_path
    if (-not (Test-Path -LiteralPath $prg)) {
        throw "Generated PRG was not found: $prg"
    }

    $safeTrigger = $trigger -replace "[^A-Za-z0-9_.-]", "_"
    $safeBase = ([string]$metadata.file_base) -replace "[^A-Za-z0-9_.-]", "_"
    $stdoutLog = Join-Path $runRoot "$safeTrigger-$safeBase-output.txt"
    $packetLog = Join-Path $runRoot "$safeTrigger-$safeBase-packets.jsonl"

    $args = @(
        "-B",
        $sender,
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
        $trigger,
        "--verify-delay",
        [string]$VerifyDelay,
        "--progress-step",
        [string]$ProgressStep,
        "--upload-retries",
        [string]$UploadRetries,
        "--verify-app-id",
        [string]$metadata.app_id,
        "--verify-app-name",
        [string]$metadata.app_name,
        "--packet-log",
        $packetLog,
        "--packet-log-bytes",
        "256",
        "--debug"
    )
    if (-not [string]::IsNullOrWhiteSpace($Address)) {
        $args += @("--address", $Address)
    } elseif (-not [string]::IsNullOrWhiteSpace($Name)) {
        $args += @("--name", $Name)
    } else {
        throw "Provide -Address or -Name."
    }
    if ($ShowInstalledApps) {
        $args += "--show-installed-apps"
    }

    Write-Host "App name: $($metadata.app_name)"
    Write-Host "App id:   $($metadata.app_id)"
    Write-Host "PRG:      $prg"
    Write-Host "Output:   $stdoutLog"
    Write-Host "Packets:  $packetLog"

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $python @args 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $output | Tee-Object -FilePath $stdoutLog

    $registered = $false
    $queryFailed = $false
    foreach ($line in $output) {
        $text = [string]$line
        if ($text -match "Transfer succeeded and app is registered") {
            $registered = $true
        }
        if ($text -match "Unable to query installed apps") {
            $queryFailed = $true
        }
    }

    $row = [pscustomobject]@{
        trigger = $trigger
        exit_code = $exitCode
        registered = $registered
        query_failed = $queryFailed
        app_name = [string]$metadata.app_name
        app_id = [string]$metadata.app_id
        file_base = [string]$metadata.file_base
        prg_path = $prg
        output_log = $stdoutLog
        packet_log = $packetLog
    }
    $summary += $row
    $summary | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $session "summary.json") -Encoding UTF8
    $summary | Format-Table -AutoSize | Out-String | Set-Content -Path (Join-Path $session "summary.txt") -Encoding UTF8

    if ($registered) {
        Write-Host "Registered after trigger '$trigger'."
        if ($StopOnRegistered) {
            break
        }
    } elseif ($queryFailed) {
        Write-Host "Installed-app query failed after trigger '$trigger'."
    } else {
        Write-Host "Not registered after trigger '$trigger'."
    }
    Write-Host ""
}

Write-Host "BLE experiment complete: $session"
Write-Host "Summary:"
$summary | Format-Table -AutoSize
