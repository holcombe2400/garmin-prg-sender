param(
    [string]$DevicePattern = "fenix|Garmin",
    [string]$OutDir = "",
    [string]$AppId = "d036558e-537b-4aa3-aac9-c23c7ba27344",
    [string]$AppName = "Garmon",
    [string]$FileName = "GarmonInstallTest_fenix6pro_43KB",
    [switch]$FileOnly,
    [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\usb-registry"
}
if ($FileOnly) {
    $AppId = ""
    $AppName = ""
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

function Copy-MtpChildFile {
    param(
        [object]$AppsFolder,
        [string]$FileName,
        [string]$Destination
    )
    $item = Find-ChildItemByName $AppsFolder $FileName
    if ($null -eq $item) {
        throw "No GARMIN\Apps\$FileName file found."
    }
    if ($item.IsFolder) {
        throw "GARMIN\Apps\$FileName is a folder, not a file."
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $shell = New-Object -ComObject Shell.Application
    $destFolder = $shell.Namespace((Resolve-Path $Destination).Path)
    if ($null -eq $destFolder) {
        throw "Could not open destination folder: $Destination"
    }

    $copyOptions = 4 + 16 + 1024
    $destFolder.CopyHere($item, $copyOptions)
}

function Wait-ForFile {
    param(
        [string]$Path,
        [int]$Timeout
    )
    $deadline = (Get-Date).AddSeconds($Timeout)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).Length -gt 0)) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
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
    throw "Python was not found. Expected .runtime, .venv, or python on PATH."
}

function Normalize-AppId {
    param([string]$Value)
    return ($Value -replace "-", "").ToLowerInvariant()
}

function Get-OptionalProperty {
    param(
        [object]$Object,
        [string]$Name
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$session = Join-Path $OutDir ("registry-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$rootFiles = Join-Path $session "ROOT_FILES"
New-Item -ItemType Directory -Force -Path $rootFiles | Out-Null

$context = Wait-MtpAppsContext $TimeoutSeconds
Write-Host "MTP device found: $($context.DeviceName)"
Copy-MtpChildFile $context.AppsFolder "OUT" $rootFiles

$outBin = Join-Path $rootFiles "OUT.BIN"
if (-not (Wait-ForFile $outBin $TimeoutSeconds)) {
    throw "Timed out waiting for copied GARMIN\Apps\OUT file."
}

$parser = Join-Path $scriptRoot "Parse-GarminAppsOut.py"
if (-not (Test-Path -LiteralPath $parser)) {
    throw "Parser not found: $parser"
}

$outJson = Join-Path $session "out-apps.json"
$outText = Join-Path $session "out-apps.txt"
$python = Find-Python
& $python $parser $outBin --json $outJson --text $outText
if ($LASTEXITCODE -ne 0) {
    throw "OUT parser failed with exit code $LASTEXITCODE."
}

$summary = Get-Content -LiteralPath $outJson -Raw | ConvertFrom-Json
$targetId = if ([string]::IsNullOrWhiteSpace($AppId)) { "" } else { Normalize-AppId $AppId }
$targetName = if ([string]::IsNullOrWhiteSpace($AppName)) { "" } else { $AppName.ToLowerInvariant() }
$targetFile = if ([string]::IsNullOrWhiteSpace($FileName)) { "" } else { $FileName.ToLowerInvariant() }

$matches = @()
foreach ($record in $summary.records) {
    $uuidValue = Get-OptionalProperty $record "uuid_hex"
    $nameValue = Get-OptionalProperty $record "name"
    $fileValue = Get-OptionalProperty $record "filename"
    $recordId = if ($null -ne $uuidValue) { [string]$uuidValue } else { "" }
    $recordName = if ($null -ne $nameValue) { ([string]$nameValue).ToLowerInvariant() } else { "" }
    $recordFile = if ($null -ne $fileValue) { ([string]$fileValue).ToLowerInvariant() } else { "" }
    $matched = $false
    if ($targetId -and $recordId.ToLowerInvariant() -eq $targetId) {
        $matched = $true
    }
    if ($targetName -and $recordName -eq $targetName) {
        $matched = $true
    }
    if ($targetFile -and $recordFile -eq $targetFile) {
        $matched = $true
    }
    if ($matched) {
        $matches += $record
    }
}

Write-Host "Registry capture: $session"
Write-Host "Records decoded: $($summary.record_count)"

if ($matches.Count -gt 0) {
    Write-Host "Transfer succeeded and app is registered in USB/MTP registry"
    foreach ($match in $matches) {
        $matchIndex = Get-OptionalProperty $match "index"
        $matchName = Get-OptionalProperty $match "name"
        $matchFile = Get-OptionalProperty $match "filename"
        $matchSize = Get-OptionalProperty $match "size_or_id"
        $matchType = Get-OptionalProperty $match "entry_type"
        $matchUuid = Get-OptionalProperty $match "uuid_hex"
        Write-Host ("  {0:000}  {1}  file={2}  size_or_id={3}  type={4}  uuid={5}" -f
            [int]$matchIndex,
            [string]$matchName,
            [string]$matchFile,
            [string]$matchSize,
            [string]$matchType,
            [string]$matchUuid)
    }
    exit 0
}

Write-Host "Transfer succeeded but app is not registered in USB/MTP registry"
Write-Host "Decoded app rows are in: $outText"
exit 3
