param(
    [string]$Prg = "",
    [string]$DevicePattern = "fenix|Garmin",
    [string]$OutDir = "",
    [int]$TimeoutSeconds = 240
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($Prg)) {
    $Prg = Join-Path $projectRoot "test-prgs\GarmonInstallTest_fenix6pro_43KB.prg"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\usb-index-experiments"
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

$collectScript = Join-Path $scriptRoot "Collect-GarminAppsSnapshotMtp.ps1"
$installScript = Join-Path $scriptRoot "Install-GarminPrgMtp.ps1"
$compareScript = Join-Path $scriptRoot "Compare-GarminAppsSnapshots.py"
foreach ($path in @($collectScript, $installScript, $compareScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}
if (-not (Test-Path -LiteralPath $Prg)) {
    throw "PRG does not exist: $Prg"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$session = Join-Path $OutDir ("experiment-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$before = Join-Path $session "before"
$after = Join-Path $session "after"
$installLogs = Join-Path $session "install"
New-Item -ItemType Directory -Force -Path $session | Out-Null

$targetFile = [System.IO.Path]::GetFileNameWithoutExtension($Prg)
$targetName = ""
$targetUuid = ""
$prgParent = Split-Path -Parent $Prg
if ($prgParent) {
    $candidateMetadata = Join-Path (Split-Path -Parent $prgParent) "metadata.json"
    if (Test-Path -LiteralPath $candidateMetadata) {
        try {
            $metadata = Get-Content -LiteralPath $candidateMetadata -Raw | ConvertFrom-Json
            if ($metadata.app_name) {
                $targetName = [string]$metadata.app_name
            }
            if ($metadata.app_id) {
                $targetUuid = [string]$metadata.app_id
            }
        } catch {
            Write-Host "Could not read generated probe metadata: $($_.Exception.Message)"
        }
    }
}
$python = Find-Python

Write-Host "USB index experiment session: $session"
Write-Host "Target PRG: $Prg"
Write-Host ""
Write-Host "Step 1/4: collecting BEFORE snapshot."
& powershell -NoProfile -ExecutionPolicy Bypass -File $collectScript -DevicePattern $DevicePattern -SnapshotDir $before -Label "before" -TimeoutSeconds $TimeoutSeconds
if ($LASTEXITCODE -ne 0) {
    throw "Before snapshot failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Step 2/4: copying PRG. When prompted, unplug the watch and wait for its loading/indexing screen to finish, then reconnect it."
& powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -Prg $Prg -DevicePattern $DevicePattern -LogDir $installLogs -Copy -WaitForDisconnect -WaitForReconnect -TimeoutSeconds $TimeoutSeconds
if ($LASTEXITCODE -ne 0) {
    throw "USB install/copy step failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Step 3/4: collecting AFTER snapshot."
& powershell -NoProfile -ExecutionPolicy Bypass -File $collectScript -DevicePattern $DevicePattern -SnapshotDir $after -Label "after" -TimeoutSeconds $TimeoutSeconds
if ($LASTEXITCODE -ne 0) {
    throw "After snapshot failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Step 4/4: comparing snapshots."
$diffJson = Join-Path $session "snapshot-diff.json"
$diffText = Join-Path $session "snapshot-diff.txt"
$compareArgs = @(
    $compareScript,
    $before,
    $after,
    "--target-filename",
    $targetFile,
    "--json",
    $diffJson,
    "--text",
    $diffText
)
if (-not [string]::IsNullOrWhiteSpace($targetName)) {
    $compareArgs += @("--target-name", $targetName)
}
if (-not [string]::IsNullOrWhiteSpace($targetUuid)) {
    $compareArgs += @("--target-uuid", $targetUuid)
}
& $python @compareArgs
if ($LASTEXITCODE -ne 0) {
    throw "Snapshot comparison failed with exit code $LASTEXITCODE."
}

Write-Host "Experiment complete: $session"
