param(
    [string]$DevicePattern = "fenix|Garmin",
    [string]$OutDir = "",
    [string]$NamePrefix = "CIQ Probe",
    [string]$Device = "fenix6pro",
    [int]$TimeoutSeconds = 240,
    [switch]$GenerateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\fresh-probe-experiments"
}

$probeRoot = Join-Path $OutDir "probes"
$experimentRoot = Join-Path $OutDir "experiments"
$generator = Join-Path $scriptRoot "New-CiqInstallProbe.ps1"
$experiment = Join-Path $scriptRoot "Run-GarminUsbIndexExperiment.ps1"

foreach ($path in @($generator, $experiment)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $probeRoot, $experimentRoot | Out-Null

Write-Host "Generating fresh CIQ install probe..."
$beforeProbeDirs = @{}
foreach ($dir in Get-ChildItem -LiteralPath $probeRoot -Directory) {
    $beforeProbeDirs[$dir.FullName] = $true
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $generator -OutputRoot $probeRoot -NamePrefix $NamePrefix -Device $Device
if ($LASTEXITCODE -ne 0) {
    throw "Probe generation failed with exit code $LASTEXITCODE."
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
    throw "Could not find generated probe directory under $probeRoot."
}
$metadataPath = Join-Path $probeDir.FullName "metadata.json"
if (-not (Test-Path -LiteralPath $metadataPath)) {
    throw "Could not find generated probe metadata under $probeRoot."
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$prg = [string]$metadata.prg_path
if (-not (Test-Path -LiteralPath $prg)) {
    throw "Generated PRG was not found: $prg"
}

Write-Host "Fresh probe ready:"
Write-Host "  App name: $($metadata.app_name)"
Write-Host "  App id:   $($metadata.app_id)"
Write-Host "  PRG:      $prg"

if ($GenerateOnly) {
    return
}

Write-Host ""
Write-Host "Starting guided USB index experiment."
& powershell -NoProfile -ExecutionPolicy Bypass -File $experiment -Prg $prg -DevicePattern $DevicePattern -OutDir $experimentRoot -TimeoutSeconds $TimeoutSeconds
if ($LASTEXITCODE -ne 0) {
    throw "USB index experiment failed with exit code $LASTEXITCODE."
}
