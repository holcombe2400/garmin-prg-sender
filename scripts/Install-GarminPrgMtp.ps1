param(
    [string]$Prg = "",
    [string]$DevicePattern = "fenix|Garmin",
    [string]$LogDir = "",
    [switch]$Copy,
    [switch]$WaitForDisconnect,
    [switch]$WaitForReconnect,
    [int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($Prg)) {
    $Prg = Join-Path $projectRoot "test-prgs\GarmonInstallTest_fenix6pro_43KB.prg"
}
if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = Join-Path $projectRoot "logs\usb-sideload"
}

function New-LogSession {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $session = Join-Path $LogDir "session-$stamp"
    New-Item -ItemType Directory -Force -Path $session | Out-Null
    return $session
}

function Write-Log {
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
    $path = Join-Path $script:SessionDir $Name
    $Value | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
}

function Get-GarminPnpSnapshot {
    $items = @()
    try {
        $items = Get-PnpDevice -PresentOnly |
            Where-Object {
                $_.FriendlyName -match "Garmin|fenix|MTP|Portable|WPD" -or
                $_.InstanceId -match "VID_091E|GARMIN"
            } |
            Select-Object Status, Class, FriendlyName, InstanceId
    } catch {
        $items = Get-CimInstance Win32_PnPEntity |
            Where-Object {
                $_.Name -match "Garmin|fenix|MTP|Portable|WPD" -or
                $_.PNPDeviceID -match "VID_091E|GARMIN"
            } |
            Select-Object @{Name="Status";Expression={$_.Status}}, @{Name="Class";Expression={$_.PNPClass}}, @{Name="FriendlyName";Expression={$_.Name}}, @{Name="InstanceId";Expression={$_.PNPDeviceID}}
    }
    return @($items)
}

function Get-VolumesSnapshot {
    try {
        return @(Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, HealthStatus, SizeRemaining, Size)
    } catch {
        return @(@{ error = $_.Exception.Message })
    }
}

function Find-ChildItemByName {
    param(
        [object]$Folder,
        [string]$Name
    )
    foreach ($item in $Folder.Items()) {
        if ($item.Name -ieq $Name) {
            return $item
        }
    }
    return $null
}

function Get-MtpAppsContext {
    $shell = New-Object -ComObject Shell.Application
    $computer = $shell.Namespace(17)
    foreach ($device in $computer.Items()) {
        if ($device.Name -match $DevicePattern) {
            $deviceFolder = $device.GetFolder
            $primary = Find-ChildItemByName $deviceFolder "Primary"
            if ($null -eq $primary) {
                throw "Found '$($device.Name)', but could not find Primary storage."
            }
            $primaryFolder = $primary.GetFolder
            $garmin = Find-ChildItemByName $primaryFolder "GARMIN"
            if ($null -eq $garmin) {
                throw "Found '$($device.Name)\Primary', but could not find GARMIN."
            }
            $garminFolder = $garmin.GetFolder
            $apps = Find-ChildItemByName $garminFolder "Apps"
            if ($null -eq $apps) {
                throw "Found '$($device.Name)\Primary\GARMIN', but could not find Apps."
            }
            return [pscustomobject]@{
                Device = $device
                DeviceName = $device.Name
                Primary = $primary
                Garmin = $garmin
                Apps = $apps
                AppsFolder = $apps.GetFolder
            }
        }
    }
    throw "No MTP device matched pattern '$DevicePattern'."
}

function Get-ShellFolderListing {
    param([object]$Folder)
    $rows = @()
    foreach ($item in $Folder.Items()) {
        $rows += [pscustomobject]@{
            Name = $item.Name
            IsFolder = [bool]$item.IsFolder
            Path = $item.Path
            Type = $item.Type
        }
    }
    return $rows
}

function Test-MtpNameMatch {
    param(
        [string]$ObservedName,
        [string]$ExpectedLeaf
    )
    $expectedStem = [System.IO.Path]::GetFileNameWithoutExtension($ExpectedLeaf)
    return $ObservedName -ieq $ExpectedLeaf -or $ObservedName -ieq $expectedStem
}

function Wait-ForMtpItem {
    param(
        [object]$Folder,
        [string]$Name,
        [int]$Timeout
    )
    $deadline = (Get-Date).AddSeconds($Timeout)
    while ((Get-Date) -lt $deadline) {
        foreach ($item in $Folder.Items()) {
            if (Test-MtpNameMatch $item.Name $Name) {
                return $true
            }
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Wait-GarminPresence {
    param(
        [bool]$Present,
        [int]$Timeout
    )
    $deadline = (Get-Date).AddSeconds($Timeout)
    while ((Get-Date) -lt $deadline) {
        $found = @(Get-GarminPnpSnapshot | Where-Object { $_.FriendlyName -match "fenix|Garmin" -or $_.InstanceId -match "VID_091E" }).Count -gt 0
        if ($found -eq $Present) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

$script:SessionDir = New-LogSession
$script:TextLog = Join-Path $script:SessionDir "record.txt"

Write-Log "Garmin USB/MTP sideload recording session started."
Write-Log "Session directory: $script:SessionDir"
Write-Log "PRG: $Prg"
Save-Json "pnp-before.json" (Get-GarminPnpSnapshot)
Save-Json "volumes-before.json" (Get-VolumesSnapshot)

$context = Get-MtpAppsContext
Write-Log "MTP device found: $($context.DeviceName)"
Save-Json "apps-before.json" (Get-ShellFolderListing $context.AppsFolder)

if ($Copy) {
    if (-not (Test-Path -LiteralPath $Prg)) {
        throw "PRG does not exist: $Prg"
    }

    $targetName = Split-Path -Path $Prg -Leaf
    foreach ($item in $context.AppsFolder.Items()) {
        if (Test-MtpNameMatch $item.Name $targetName) {
            throw "Refusing to overwrite existing watch item in GARMIN\Apps: $targetName"
        }
    }

    Write-Log "Copying PRG into GARMIN\Apps: $targetName"
    # Shell CopyHere is the stable Windows automation surface for MTP devices.
    # 4 hides progress, 16 answers yes-to-all if the shell asks metadata questions, 1024 suppresses error UI.
    $copyOptions = 4 + 16 + 1024
    $context.AppsFolder.CopyHere($Prg, $copyOptions)
    if (-not (Wait-ForMtpItem $context.AppsFolder $targetName $TimeoutSeconds)) {
        throw "Timed out waiting for copied PRG to appear in GARMIN\Apps: $targetName"
    }
    Write-Log "Copy appears in GARMIN\Apps: $targetName"
} else {
    Write-Log "Dry run only. Add -Copy to copy the PRG into GARMIN\Apps."
}

Save-Json "apps-after-copy.json" (Get-ShellFolderListing $context.AppsFolder)
Save-Json "pnp-after-copy.json" (Get-GarminPnpSnapshot)
Save-Json "volumes-after-copy.json" (Get-VolumesSnapshot)

if ($WaitForDisconnect) {
    Write-Log "Waiting for Garmin USB device to disappear. Unplug the watch now."
    if (Wait-GarminPresence -Present:$false -Timeout $TimeoutSeconds) {
        Write-Log "Garmin USB device disappeared."
    } else {
        Write-Log "Timed out waiting for Garmin USB device to disappear."
    }
    Save-Json "pnp-after-disconnect.json" (Get-GarminPnpSnapshot)
}

if ($WaitForReconnect) {
    Write-Log "Waiting for Garmin USB device to reappear. Reconnect the watch when indexing/loading finishes."
    if (Wait-GarminPresence -Present:$true -Timeout $TimeoutSeconds) {
        Write-Log "Garmin USB device reappeared."
    } else {
        Write-Log "Timed out waiting for Garmin USB device to reappear."
    }
    Save-Json "pnp-after-reconnect.json" (Get-GarminPnpSnapshot)
    try {
        $context = Get-MtpAppsContext
        Save-Json "apps-after-reconnect.json" (Get-ShellFolderListing $context.AppsFolder)
    } catch {
        Write-Log "Could not refresh MTP Apps folder after reconnect: $($_.Exception.Message)"
    }
}

Write-Log "Recording session complete."
