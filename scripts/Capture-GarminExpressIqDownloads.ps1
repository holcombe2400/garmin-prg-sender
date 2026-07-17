param(
    [string]$WatchRoot = "C:\ProgramData\Garmin\CoreService\Devices",
    [string]$OutDir = "",
    [int]$TimeoutSeconds = 300,
    [int]$PollMilliseconds = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\garmin-express-iq-download-captures"
}

function Copy-FileShared {
    param(
        [string]$Source,
        [string]$Destination
    )
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $sourceStream = [System.IO.File]::Open($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
    try {
        $destStream = [System.IO.File]::Create($Destination)
        try {
            $sourceStream.CopyTo($destStream)
        } finally {
            $destStream.Dispose()
        }
    } finally {
        $sourceStream.Dispose()
    }
}

function Get-Sha256 {
    param([string]$Path)
    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    } catch {
        return $null
    }
}

$session = Join-Path $OutDir ("capture-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$filesDir = Join-Path $session "files"
New-Item -ItemType Directory -Force -Path $filesDir | Out-Null

Write-Host "Garmin Express IQ download capture: $session"
Write-Host "Watching: $WatchRoot\*\Sync\Download\IQWatchApps"
Write-Host "Timeout: $TimeoutSeconds seconds"
Write-Host "Start the Garmin Express IQ app install now."

$seen = @{}
$captures = @()
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    $downloadDirs = @(Get-ChildItem -LiteralPath $WatchRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "Sync\Download\IQWatchApps" } |
        Where-Object { Test-Path -LiteralPath $_ })

    foreach ($dir in $downloadDirs) {
        $files = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            $key = "$($file.FullName)|$($file.Length)|$($file.LastWriteTimeUtc.Ticks)"
            if ($seen.ContainsKey($key)) {
                continue
            }
            $seen[$key] = $true

            $safeLeaf = $file.Name -replace "[^A-Za-z0-9._-]", "_"
            $dest = Join-Path $filesDir ("{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), $safeLeaf)
            try {
                Copy-FileShared $file.FullName $dest
                $destItem = Get-Item -LiteralPath $dest
                $record = [pscustomobject]@{
                    captured_at = (Get-Date).ToString("O")
                    source = $file.FullName
                    source_length = $file.Length
                    source_last_write_utc = $file.LastWriteTimeUtc.ToString("O")
                    captured_path = $dest
                    captured_length = $destItem.Length
                    sha256 = Get-Sha256 $dest
                }
                $captures += $record
                $captures | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $session "captures.json") -Encoding UTF8
                Write-Host "Captured $($file.FullName) -> $dest ($($destItem.Length) bytes)"
            } catch {
                Write-Host "Could not capture $($file.FullName): $($_.Exception.Message)"
            }
        }
    }
    Start-Sleep -Milliseconds $PollMilliseconds
}

if ($captures.Count -eq 0) {
    Write-Host "No IQWatchApps temp files were captured."
} else {
    Write-Host "Captured $($captures.Count) file snapshot(s)."
}
Write-Host "Capture folder: $session"
