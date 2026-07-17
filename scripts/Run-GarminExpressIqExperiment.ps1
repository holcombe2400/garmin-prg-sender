param(
    [ValidateSet("Before", "After", "Compare")]
    [string]$Phase = "Before",
    [string]$ExperimentDir = "",
    [string]$DevicePattern = "fenix|Garmin",
    [string]$OutDir = "",
    [int]$TimeoutSeconds = 120,
    [int]$MaxHashMegabytes = 25,
    [string]$TargetFilename = "",
    [string]$TargetName = "",
    [string]$TargetUuid = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\garmin-express-iq-experiments"
}

$collectScript = Join-Path $scriptRoot "Collect-GarminAppsSnapshotMtp.ps1"
$compareScript = Join-Path $scriptRoot "Compare-GarminAppsSnapshots.py"
foreach ($path in @($collectScript, $compareScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
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
    throw "Python was not found. Expected .runtime, .venv, or python on PATH."
}

function Find-LatestExperiment {
    if (-not (Test-Path -LiteralPath $OutDir)) {
        throw "No Garmin Express IQ experiment folder exists yet: $OutDir"
    }
    $latest = Get-ChildItem -LiteralPath $OutDir -Directory -Filter "express-iq-*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $latest) {
        throw "No Garmin Express IQ experiment sessions found in $OutDir"
    }
    return $latest.FullName
}

function Get-GarminPcRoots {
    $roots = @()
    $candidates = @(
        @{ Label = "programdata-garmin"; Path = Join-Path $env:ProgramData "Garmin" },
        @{ Label = "localappdata-garmin"; Path = Join-Path $env:LOCALAPPDATA "Garmin" },
        @{ Label = "appdata-garmin"; Path = Join-Path $env:APPDATA "Garmin" }
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate.Path) {
            $roots += [pscustomobject]$candidate
        }
    }
    return $roots
}

function Get-Sha256IfSmall {
    param(
        [string]$Path,
        [long]$Length,
        [long]$MaxBytes
    )
    if ($Length -gt $MaxBytes) {
        return $null
    }
    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    } catch {
        return $null
    }
}

function Collect-PcManifest {
    param([string]$Path)
    $maxBytes = [long]$MaxHashMegabytes * 1024L * 1024L
    $records = @()
    foreach ($root in Get-GarminPcRoots) {
        $rootPath = [string]$root.Path
        $rootLabel = [string]$root.Label
        Write-Host "Indexing PC Garmin folder: $rootPath"
        $files = Get-ChildItem -LiteralPath $rootPath -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($rootPath.Length).TrimStart("\", "/")
            $records += [pscustomobject]@{
                key = "$rootLabel/$($relative -replace '\\', '/')"
                root = $rootLabel
                root_path = $rootPath
                relative_path = $relative
                full_path = $file.FullName
                length = $file.Length
                last_write_utc = $file.LastWriteTimeUtc.ToString("O")
                sha256 = Get-Sha256IfSmall $file.FullName $file.Length $maxBytes
            }
        }
    }
    $manifest = [pscustomobject]@{
        captured_at = (Get-Date).ToString("O")
        max_hash_megabytes = $MaxHashMegabytes
        roots = @(Get-GarminPcRoots)
        file_count = $records.Count
        files = $records
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding UTF8
    Write-Host "PC manifest: $Path ($($records.Count) files)"
}

function Load-PcManifestMap {
    param([string]$Path)
    $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $map = @{}
    foreach ($file in $manifest.files) {
        $map[[string]$file.key] = $file
    }
    return $map
}

function Test-PcRecordChanged {
    param($Before, $After)
    if ([int64]$Before.length -ne [int64]$After.length) {
        return $true
    }
    $beforeHash = [string]$Before.sha256
    $afterHash = [string]$After.sha256
    if ($beforeHash -or $afterHash) {
        return $beforeHash -ne $afterHash
    }
    return ([string]$Before.last_write_utc) -ne ([string]$After.last_write_utc)
}

function Compare-PcManifests {
    param(
        [string]$BeforePath,
        [string]$AfterPath,
        [string]$JsonPath,
        [string]$TextPath
    )
    $before = Load-PcManifestMap $BeforePath
    $after = Load-PcManifestMap $AfterPath
    $beforeKeys = @($before.Keys)
    $afterKeys = @($after.Keys)
    $beforeSet = @{}
    foreach ($key in $beforeKeys) { $beforeSet[$key] = $true }
    $afterSet = @{}
    foreach ($key in $afterKeys) { $afterSet[$key] = $true }

    $added = @()
    foreach ($key in $afterKeys) {
        if (-not $beforeSet.ContainsKey($key)) { $added += $after[$key] }
    }
    $removed = @()
    foreach ($key in $beforeKeys) {
        if (-not $afterSet.ContainsKey($key)) { $removed += $before[$key] }
    }
    $changed = @()
    foreach ($key in $beforeKeys) {
        if ($afterSet.ContainsKey($key) -and (Test-PcRecordChanged $before[$key] $after[$key])) {
            $changed += [pscustomobject]@{
                key = $key
                before = $before[$key]
                after = $after[$key]
            }
        }
    }

    $diff = [pscustomobject]@{
        before = $BeforePath
        after = $AfterPath
        added_count = $added.Count
        removed_count = $removed.Count
        changed_count = $changed.Count
        added = $added
        removed = $removed
        changed = $changed
    }
    $diff | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonPath -Encoding UTF8

    $lines = @()
    $lines += "Before: $BeforePath"
    $lines += "After:  $AfterPath"
    $lines += ""
    $lines += "PC Garmin folders:"
    $lines += "  added=$($added.Count) removed=$($removed.Count) changed=$($changed.Count)"
    foreach ($label in @("added", "removed")) {
        $items = @(if ($label -eq "added") { $added } else { $removed })
        if ($items.Count -gt 0) {
            $lines += "  ${label}:"
            foreach ($item in @($items | Sort-Object key | Select-Object -First 80)) {
                $hashText = [string]$item.sha256
                $hashPrefix = if ($hashText.Length -gt 0) { $hashText.Substring(0, [Math]::Min(16, $hashText.Length)) } else { "" }
                $lines += "    $($item.key) size=$($item.length) sha256=$hashPrefix"
            }
            if ($items.Count -gt 80) {
                $lines += "    ... $($items.Count - 80) more"
            }
        }
    }
    if ($changed.Count -gt 0) {
        $lines += "  changed:"
        foreach ($item in @($changed | Sort-Object key | Select-Object -First 80)) {
            $lines += "    $($item.key) size=$($item.before.length)->$($item.after.length)"
        }
        if ($changed.Count -gt 80) {
            $lines += "    ... $($changed.Count - 80) more"
        }
    }
    $lines -join "`n" | Set-Content -Path $TextPath -Encoding UTF8
    Write-Host (Get-Content -LiteralPath $TextPath -Raw)
}

function Run-WatchCompare {
    param([string]$Session)
    $before = Join-Path $Session "watch-before"
    $after = Join-Path $Session "watch-after"
    if (-not (Test-Path -LiteralPath $before)) {
        throw "Missing before watch snapshot: $before"
    }
    if (-not (Test-Path -LiteralPath $after)) {
        throw "Missing after watch snapshot: $after"
    }
    $python = Find-Python
    $diffJson = Join-Path $Session "watch-snapshot-diff.json"
    $diffText = Join-Path $Session "watch-snapshot-diff.txt"
    $args = @(
        $compareScript,
        $before,
        $after,
        "--json",
        $diffJson,
        "--text",
        $diffText
    )
    if (-not [string]::IsNullOrWhiteSpace($TargetFilename)) {
        $args += @("--target-filename", $TargetFilename)
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetName)) {
        $args += @("--target-name", $TargetName)
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetUuid)) {
        $args += @("--target-uuid", $TargetUuid)
    }
    & $python @args
    if ($LASTEXITCODE -ne 0) {
        throw "Watch snapshot comparison failed with exit code $LASTEXITCODE."
    }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ($Phase -eq "Before") {
    if ([string]::IsNullOrWhiteSpace($ExperimentDir)) {
        $ExperimentDir = Join-Path $OutDir ("express-iq-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    }
    New-Item -ItemType Directory -Force -Path $ExperimentDir | Out-Null
    $meta = [pscustomobject]@{
        created_at = (Get-Date).ToString("O")
        device_pattern = $DevicePattern
        phase = "Before"
        instructions = "Install one not-yet-installed IQ Store app in Garmin Express, sync it, unplug the watch, wait for indexing/loading to finish, reconnect, then run this script with -Phase After -ExperimentDir."
    }
    $meta | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $ExperimentDir "experiment-meta.json") -Encoding UTF8

    Write-Host "Garmin Express IQ experiment: $ExperimentDir"
    Collect-PcManifest (Join-Path $ExperimentDir "pc-before.json")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $collectScript -DevicePattern $DevicePattern -SnapshotDir (Join-Path $ExperimentDir "watch-before") -Label "watch-before" -TimeoutSeconds $TimeoutSeconds
    if ($LASTEXITCODE -ne 0) {
        throw "Before watch snapshot failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Before snapshot complete."
    Write-Host "Next: use Garmin Express to install one free IQ Store app that is not already on the watch."
    Write-Host "After Express finishes syncing, unplug the watch, wait for its loading/indexing screen, reconnect it, then run:"
    Write-Host "powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Phase After -ExperimentDir `"$ExperimentDir`""
    return
}

if ([string]::IsNullOrWhiteSpace($ExperimentDir)) {
    $ExperimentDir = Find-LatestExperiment
}
if (-not (Test-Path -LiteralPath $ExperimentDir)) {
    throw "Experiment directory does not exist: $ExperimentDir"
}

if ($Phase -eq "After") {
    Write-Host "Garmin Express IQ experiment: $ExperimentDir"
    Collect-PcManifest (Join-Path $ExperimentDir "pc-after.json")
    & powershell -NoProfile -ExecutionPolicy Bypass -File $collectScript -DevicePattern $DevicePattern -SnapshotDir (Join-Path $ExperimentDir "watch-after") -Label "watch-after" -TimeoutSeconds $TimeoutSeconds
    if ($LASTEXITCODE -ne 0) {
        throw "After watch snapshot failed with exit code $LASTEXITCODE."
    }
}

$pcBefore = Join-Path $ExperimentDir "pc-before.json"
$pcAfter = Join-Path $ExperimentDir "pc-after.json"
if ((Test-Path -LiteralPath $pcBefore) -and (Test-Path -LiteralPath $pcAfter)) {
    Compare-PcManifests $pcBefore $pcAfter (Join-Path $ExperimentDir "pc-diff.json") (Join-Path $ExperimentDir "pc-diff.txt")
}
Run-WatchCompare $ExperimentDir

Write-Host "Experiment complete: $ExperimentDir"
