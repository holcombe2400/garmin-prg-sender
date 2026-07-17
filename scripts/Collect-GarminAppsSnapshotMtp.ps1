param(
    [string]$DevicePattern = "fenix|Garmin",
    [string]$OutDir = "",
    [string]$SnapshotDir = "",
    [string]$Label = "",
    [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\usb-snapshots"
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
            $garmin = Find-ChildItemByName $primary.GetFolder "GARMIN"
            if ($null -eq $garmin) {
                throw "Found '$($device.Name)\Primary', but could not find GARMIN."
            }
            $apps = Find-ChildItemByName $garmin.GetFolder "Apps"
            if ($null -eq $apps) {
                throw "Found '$($device.Name)\Primary\GARMIN', but could not find Apps."
            }
            return [pscustomobject]@{
                DeviceName = $device.Name
                AppsFolder = $apps.GetFolder
            }
        }
    }
    throw "No MTP device matched pattern '$DevicePattern'."
}

function Wait-MtpAppsContext {
    param([int]$Timeout)
    $deadline = (Get-Date).AddSeconds($Timeout)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            return Get-MtpAppsContext
        } catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Seconds 2
        }
    }
    if ($lastError) {
        throw "Timed out waiting for GARMIN\Apps over MTP. Last error: $lastError"
    }
    throw "Timed out waiting for GARMIN\Apps over MTP."
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

function Copy-MtpFileToFolder {
    param(
        [object]$Item,
        [string]$Destination
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $shell = New-Object -ComObject Shell.Application
    $destFolder = $shell.Namespace((Resolve-Path $Destination).Path)
    if ($null -eq $destFolder) {
        throw "Could not open destination folder: $Destination"
    }
    $copyOptions = 4 + 16 + 1024
    Write-Host "Copying $($Item.Name)"
    $destFolder.CopyHere($Item, $copyOptions)
}

function Copy-MtpFolderRecursive {
    param(
        [object]$Folder,
        [string]$Destination
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ShellFolderListing $Folder | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $Destination "listing.json") -Encoding UTF8
    foreach ($child in $Folder.Items()) {
        if ($child.IsFolder) {
            Copy-MtpFolderRecursive $child.GetFolder (Join-Path $Destination $child.Name)
        } else {
            Copy-MtpFileToFolder $child $Destination
        }
    }
}

function Wait-ForCopyQuiescence {
    param([string]$Path, [int]$Timeout)
    $deadline = (Get-Date).AddSeconds($Timeout)
    $lastCount = -1
    $lastBytes = -1
    $stableRounds = 0
    while ((Get-Date) -lt $deadline) {
        $files = @(Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue)
        $count = $files.Count
        $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $bytes) {
            $bytes = 0
        }
        if ($count -eq $lastCount -and $bytes -eq $lastBytes) {
            $stableRounds++
            if ($stableRounds -ge 3) {
                return
            }
        } else {
            $stableRounds = 0
            $lastCount = $count
            $lastBytes = $bytes
        }
        Start-Sleep -Seconds 1
    }
}

function Find-Python {
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
    return $null
}

if ([string]::IsNullOrWhiteSpace($SnapshotDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $cleanLabel = if ([string]::IsNullOrWhiteSpace($Label)) { "snapshot" } else { $Label -replace "[^A-Za-z0-9._-]", "-" }
    $SnapshotDir = Join-Path $OutDir ("$cleanLabel-$stamp")
}

New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null
$context = Wait-MtpAppsContext $TimeoutSeconds
Write-Host "MTP device found: $($context.DeviceName)"

$meta = [pscustomobject]@{
    DeviceName = $context.DeviceName
    CapturedAt = (Get-Date).ToString("O")
    DevicePattern = $DevicePattern
}
$meta | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $SnapshotDir "snapshot-meta.json") -Encoding UTF8
Get-ShellFolderListing $context.AppsFolder | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $SnapshotDir "apps-listing.json") -Encoding UTF8

foreach ($item in $context.AppsFolder.Items()) {
    if ($item.IsFolder) {
        Copy-MtpFolderRecursive $item.GetFolder (Join-Path $SnapshotDir $item.Name)
    } else {
        Copy-MtpFileToFolder $item (Join-Path $SnapshotDir "ROOT_FILES")
    }
}

Wait-ForCopyQuiescence $SnapshotDir $TimeoutSeconds

$outBin = Join-Path $SnapshotDir "ROOT_FILES\OUT.BIN"
$parser = Join-Path $scriptRoot "Parse-GarminAppsOut.py"
$python = Find-Python
if ((Test-Path -LiteralPath $outBin) -and (Test-Path -LiteralPath $parser) -and ($null -ne $python)) {
    Write-Host "Parsing GARMIN\Apps\OUT registry"
    & $python $parser $outBin --json (Join-Path $SnapshotDir "out-apps.json") --text (Join-Path $SnapshotDir "out-apps.txt")
}

Write-Host "Snapshot folder: $SnapshotDir"
