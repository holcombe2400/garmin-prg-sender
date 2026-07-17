param(
    [ValidateSet("Before", "After")]
    [string]$Phase = "Before",
    [string]$ExperimentDir = "",
    [string]$Prg = "",
    [string]$DevicePattern = "fenix|Garmin",
    [string]$OutDir = "",
    [string]$NamePrefix = "PhysicalUnplug Probe",
    [string]$Device = "fenix6pro",
    [int]$TimeoutSeconds = 180,
    [int]$EventLookbackMinutes = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\physical-unplug-trigger-captures"
}

$collectScript = Join-Path $scriptRoot "Collect-GarminAppsSnapshotMtp.ps1"
$installScript = Join-Path $scriptRoot "Install-GarminPrgMtp.ps1"
$compareScript = Join-Path $scriptRoot "Compare-GarminAppsSnapshots.py"
$probeScript = Join-Path $scriptRoot "New-CiqInstallProbe.ps1"
$wpdScript = Join-Path $scriptRoot "Invoke-WpdDeviceCommand.ps1"

function Find-Python {
    $candidates = @(
        (Join-Path $projectRoot ".runtime\Scripts\python.exe"),
        (Join-Path $projectRoot ".venv\Scripts\python.exe"),
        "C:\Users\holco\Documents\Codex\2026-07-14\lo\work\garmin_sender_venv\Scripts\python.exe",
        "python"
    )
    foreach ($candidate in $candidates) {
        if (($candidate -eq "python") -or (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    throw "Python was not found. Expected .runtime, .venv, or python on PATH."
}

function Write-TextLog {
    param([string]$Message)
    $line = "{0:O} {1}" -f (Get-Date), $Message
    Write-Host $line
    Add-Content -Path $script:TextLog -Value $line
}

function Save-Json {
    param(
        [string]$Name,
        [object]$Value
    )
    $Value | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $script:Session $Name) -Encoding UTF8
}

function Write-ChildOutput {
    param(
        [string]$Name,
        [object[]]$Output
    )
    $path = Join-Path $script:Session "$Name-output.txt"
    @($Output) | ForEach-Object { [string]$_ } | Set-Content -Path $path -Encoding UTF8
    foreach ($line in @($Output | Select-Object -Last 12)) {
        Write-TextLog "[$Name] $line"
    }
}

function Get-GarminPnpSnapshot {
    try {
        return @(Get-PnpDevice |
            Where-Object {
                $_.FriendlyName -match "Garmin|fenix|MTP|Portable|WPD" -or
                $_.InstanceId -match "VID_091E|GARMIN"
            } |
            Select-Object Status, Class, FriendlyName, InstanceId)
    } catch {
        return @([pscustomobject]@{ error = $_.Exception.Message })
    }
}

function Get-WpdSnapshot {
    if (-not (Test-Path -LiteralPath $wpdScript)) {
        return @([pscustomobject]@{ error = "WPD helper not found: $wpdScript" })
    }
    $rows = & powershell -NoProfile -ExecutionPolicy Bypass -File $wpdScript -Command ListRootObjects -DevicePattern $DevicePattern 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @([pscustomobject]@{ error = (@($rows) -join "`n") })
    }
    return @($rows)
}

function Get-UsbEventRows {
    param(
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    $providers = @(
        "Microsoft-Windows-Kernel-PnP",
        "Microsoft-Windows-UserPnp",
        "Microsoft-Windows-DriverFrameworks-UserMode",
        "Microsoft-Windows-USB-USBHUB3",
        "Microsoft-Windows-USB-UCX",
        "Service Control Manager"
    )
    try {
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = $StartTime; EndTime = $EndTime } -ErrorAction Stop)
    } catch {
        return @([pscustomobject]@{ error = $_.Exception.Message })
    }

    return @($events |
        Where-Object {
            $provider = [string]$_.ProviderName
            $message = [string]$_.Message
            ($providers -contains $provider) -or
            $message -match "VID_091E|Garmin|fenix|MTP|WPD|Portable Device|USB"
        } |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message)
}

function Get-OperationalUsbEventRows {
    param(
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    $logs = @(
        "Microsoft-Windows-Kernel-PnP/Configuration",
        "Microsoft-Windows-Kernel-PnP/Device Management",
        "Microsoft-Windows-UserPnp/DeviceInstall",
        "Microsoft-Windows-WPD-MTPClassDriver/Operational",
        "Microsoft-Windows-WPD-CompositeClassDriver/Operational",
        "Microsoft-Windows-DeviceSetupManager/Admin",
        "Microsoft-Windows-DeviceSetupManager/Operational",
        "Microsoft-Windows-Storage-ClassPnP/Operational",
        "Microsoft-Windows-USB-USBXHCI-Operational"
    )

    $rows = @()
    foreach ($log in $logs) {
        try {
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $StartTime; EndTime = $EndTime } -ErrorAction Stop)
            foreach ($event in $events) {
                $rows += [pscustomobject]@{
                    LogName = $log
                    TimeCreated = $event.TimeCreated
                    ProviderName = $event.ProviderName
                    Id = $event.Id
                    LevelDisplayName = $event.LevelDisplayName
                    Message = $event.Message
                }
            }
        } catch {
            $rows += [pscustomobject]@{
                LogName = $log
                TimeCreated = $null
                ProviderName = "QUERY_ERROR"
                Id = 0
                LevelDisplayName = "Error"
                Message = $_.Exception.Message
            }
        }
    }

    return @($rows | Where-Object {
        ([string]$_.ProviderName) -eq "QUERY_ERROR" -or
        ([string]$_.Message) -match "VID_091E|Garmin|fenix|MTP|WPD|USB|Portable|SWD\\WPDBUSENUM" -or
        ([string]$_.ProviderName) -match "Kernel-PnP|WPD"
    })
}

function Save-SetupApiTail {
    param([string]$Name)
    $path = "C:\Windows\INF\setupapi.dev.log"
    $dest = Join-Path $script:Session $Name
    if (-not (Test-Path -LiteralPath $path)) {
        "setupapi.dev.log not found: $path" | Set-Content -Path $dest -Encoding UTF8
        return
    }
    try {
        $lines = Get-Content -LiteralPath $path -Tail 2500 -ErrorAction Stop
        $interesting = @($lines | Where-Object { $_ -match "VID_091E|Garmin|fenix|WPD|MTP|Portable" })
        if ($interesting.Count -gt 0) {
            $interesting | Set-Content -Path $dest -Encoding UTF8
        } else {
            $lines | Set-Content -Path $dest -Encoding UTF8
        }
    } catch {
        "Could not read setupapi.dev.log: $($_.Exception.Message)" | Set-Content -Path $dest -Encoding UTF8
    }
}

function Run-Snapshot {
    param([string]$Name)
    $path = Join-Path $script:Session $Name
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $collectScript -DevicePattern $DevicePattern -SnapshotDir $path -Label $Name -TimeoutSeconds $TimeoutSeconds 2>&1
    Write-ChildOutput "snapshot-$Name" $output
    if ($LASTEXITCODE -ne 0) {
        throw "Snapshot '$Name' failed with exit code $LASTEXITCODE."
    }
    return $path
}

function New-ProbeIfNeeded {
    if (-not [string]::IsNullOrWhiteSpace($Prg)) {
        return $Prg
    }
    if (-not (Test-Path -LiteralPath $probeScript)) {
        throw "No PRG supplied and probe generator not found: $probeScript"
    }
    $probeRoot = Join-Path $script:Session "generated-probe"
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $probeScript -OutputRoot $probeRoot -NamePrefix $NamePrefix -Device $Device 2>&1
    Write-ChildOutput "generate-probe" $output
    if ($LASTEXITCODE -ne 0) {
        throw "Probe generation failed with exit code $LASTEXITCODE."
    }
    $metadata = Get-ChildItem -LiteralPath $probeRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "metadata.json" } |
        Where-Object { Test-Path -LiteralPath $_ } |
        ForEach-Object { Get-Item -LiteralPath $_ } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $metadata) {
        throw "Probe metadata was not generated under: $probeRoot"
    }
    Copy-Item -LiteralPath $metadata.FullName -Destination (Join-Path $script:Session "target-metadata.json") -Force
    $data = Get-Content -LiteralPath $metadata.FullName -Raw | ConvertFrom-Json
    return [string]$data.prg_path
}

function Get-TargetMetadata {
    param([string]$PrgPath)
    $target = [ordered]@{
        prg = $PrgPath
        filename = if ($PrgPath) { [System.IO.Path]::GetFileNameWithoutExtension($PrgPath) } else { "" }
        name = ""
        uuid = ""
    }
    if ([string]::IsNullOrWhiteSpace($PrgPath)) {
        return [pscustomobject]$target
    }
    $metadataPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PrgPath)) "metadata.json"
    if (Test-Path -LiteralPath $metadataPath) {
        try {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
            if ($metadata.app_name) { $target["name"] = [string]$metadata.app_name }
            if ($metadata.app_id) { $target["uuid"] = [string]$metadata.app_id }
            if ($metadata.app_id_dashed) { $target["uuid_dashed"] = [string]$metadata.app_id_dashed }
        } catch {
            Write-TextLog "Could not parse target metadata: $($_.Exception.Message)"
        }
    }
    return [pscustomobject]$target
}

function Compare-Snapshots {
    param(
        [string]$Before,
        [string]$After,
        [object]$Target
    )
    $python = Find-Python
    $diffJson = Join-Path $script:Session "before-to-after-physical-unplug-diff.json"
    $diffText = Join-Path $script:Session "before-to-after-physical-unplug-diff.txt"
    $args = @(
        $compareScript,
        $Before,
        $After,
        "--json",
        $diffJson,
        "--text",
        $diffText
    )
    if ($Target.filename) {
        $args += @("--target-filename", $Target.filename)
    }
    if ($Target.name) {
        $args += @("--target-name", $Target.name)
    }
    if ($Target.uuid) {
        $args += @("--target-uuid", $Target.uuid)
    }
    $output = & $python @args 2>&1
    Write-ChildOutput "compare-before-after" $output
    if ($LASTEXITCODE -ne 0) {
        throw "Snapshot comparison failed with exit code $LASTEXITCODE."
    }
}

function Write-RunInstructions {
    param([object]$Target)
    $afterCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminPhysicalUnplugTriggerCapture.ps1 -Phase After -ExperimentDir `"$script:Session`""
    $lines = @(
        "Physical unplug trigger capture BEFORE phase is complete.",
        "",
        "Target:",
        "  name: $($Target.name)",
        "  uuid: $($Target.uuid)",
        "  file: $($Target.filename)",
        "",
        "Next:",
        "1. Physically unplug the watch.",
        "2. Write down whether the watch shows the loading/indexing screen and the approximate time.",
        "3. Wait until the watch finishes.",
        "4. Reconnect the watch.",
        "5. Run:",
        "   $afterCommand"
    )
    $lines | Set-Content -Path (Join-Path $script:Session "NEXT-STEPS.txt") -Encoding UTF8
    foreach ($line in $lines) {
        Write-Host $line
    }
}

if ($Phase -eq "Before") {
    foreach ($path in @($collectScript, $installScript, $compareScript)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Required script not found: $path"
        }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $script:Session = Join-Path $OutDir ("physical-unplug-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $script:Session | Out-Null
    $script:TextLog = Join-Path $script:Session "record.txt"

    $started = (Get-Date).AddMinutes(-1 * [Math]::Max(0, $EventLookbackMinutes))
    Save-Json "session.json" ([ordered]@{
        phase = "Before"
        session = $script:Session
        started_at = (Get-Date).ToString("O")
        event_start_at = $started.ToString("O")
        device_pattern = $DevicePattern
    })
    Write-TextLog "Physical unplug trigger capture BEFORE phase started."
    Write-TextLog "Session: $script:Session"

    Save-Json "pnp-before-stage.json" (Get-GarminPnpSnapshot)
    Save-Json "wpd-before-stage.json" (Get-WpdSnapshot)
    Save-Json "events-before-stage.json" (Get-UsbEventRows $started (Get-Date))
    Save-Json "operational-events-before-stage.json" (Get-OperationalUsbEventRows $started (Get-Date))
    Save-SetupApiTail "setupapi-before-stage.txt"

    $targetPrg = New-ProbeIfNeeded
    $target = Get-TargetMetadata $targetPrg
    Save-Json "target.json" $target

    $before = Run-Snapshot "before"
    Save-Json "paths.json" ([ordered]@{
        before_snapshot = $before
    })

    Write-TextLog "Staging PRG over MTP: $targetPrg"
    $installLogs = Join-Path $script:Session "stage-copy"
    $stageOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -Prg $targetPrg -DevicePattern $DevicePattern -LogDir $installLogs -Copy -TimeoutSeconds $TimeoutSeconds 2>&1
    Write-ChildOutput "stage-copy" $stageOutput
    if ($LASTEXITCODE -ne 0) {
        throw "MTP staging failed with exit code $LASTEXITCODE."
    }

    $staged = Run-Snapshot "after-stage-before-unplug"
    Save-Json "paths.json" ([ordered]@{
        before_snapshot = $before
        staged_snapshot = $staged
    })
    Save-Json "pnp-after-stage.json" (Get-GarminPnpSnapshot)
    Save-Json "wpd-after-stage.json" (Get-WpdSnapshot)
    Save-Json "events-after-stage.json" (Get-UsbEventRows $started (Get-Date))
    Save-Json "operational-events-after-stage.json" (Get-OperationalUsbEventRows $started (Get-Date))
    Save-SetupApiTail "setupapi-after-stage.txt"
    Write-RunInstructions $target
    Write-TextLog "BEFORE phase complete."
    return
}

if ([string]::IsNullOrWhiteSpace($ExperimentDir)) {
    throw "Provide -ExperimentDir from the BEFORE phase when running -Phase After."
}
if (-not (Test-Path -LiteralPath $ExperimentDir)) {
    throw "ExperimentDir does not exist: $ExperimentDir"
}
foreach ($path in @($collectScript, $compareScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

$script:Session = (Resolve-Path -LiteralPath $ExperimentDir).Path
$script:TextLog = Join-Path $script:Session "record.txt"
Write-TextLog "Physical unplug trigger capture AFTER phase started."

$sessionJson = Join-Path $script:Session "session.json"
$eventStart = (Get-Date).AddMinutes(-30)
if (Test-Path -LiteralPath $sessionJson) {
    try {
        $sessionData = Get-Content -LiteralPath $sessionJson -Raw | ConvertFrom-Json
        if ($sessionData.event_start_at) {
            $eventStart = [datetime]$sessionData.event_start_at
        }
    } catch {
        Write-TextLog "Could not parse session.json: $($_.Exception.Message)"
    }
}

Save-Json "pnp-after-replug.json" (Get-GarminPnpSnapshot)
Save-Json "wpd-after-replug.json" (Get-WpdSnapshot)
Save-Json "events-after-replug.json" (Get-UsbEventRows $eventStart (Get-Date))
Save-Json "operational-events-after-replug.json" (Get-OperationalUsbEventRows $eventStart (Get-Date))
Save-SetupApiTail "setupapi-after-replug.txt"

$after = Run-Snapshot "after-replug"
$pathsPath = Join-Path $script:Session "paths.json"
$before = Join-Path $script:Session "before"
if (Test-Path -LiteralPath $pathsPath) {
    try {
        $paths = Get-Content -LiteralPath $pathsPath -Raw | ConvertFrom-Json
        if ($paths.before_snapshot) {
            $before = [string]$paths.before_snapshot
        }
    } catch {
        Write-TextLog "Could not parse paths.json: $($_.Exception.Message)"
    }
}

$targetPath = Join-Path $script:Session "target.json"
if (Test-Path -LiteralPath $targetPath) {
    $target = Get-Content -LiteralPath $targetPath -Raw | ConvertFrom-Json
} else {
    $target = [pscustomobject]@{ filename = ""; name = ""; uuid = "" }
}
Compare-Snapshots $before $after $target

Write-TextLog "AFTER phase complete."
Write-TextLog "Session: $script:Session"
