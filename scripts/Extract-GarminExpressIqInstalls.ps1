param(
    [string]$LogDir = "",
    [string]$OutDir = "",
    [string]$IqAppInfoPath = "",
    [switch]$IncludeSensitiveUrls
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = Join-Path $env:ProgramData "Garmin\Logs\Express"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\garmin-express-iq-install-summaries"
}

function Redact-Url {
    param([string]$Url)
    if ($IncludeSensitiveUrls) {
        return $Url
    }
    return ($Url -replace "([?&](customerId|unitId)=)[^&]+", '${1}<redacted>')
}

function Get-QueryValue {
    param(
        [string]$Url,
        [string]$Name
    )
    $match = [regex]::Match($Url, "(?:[?&])$([regex]::Escape($Name))=([^&]+)")
    if ($match.Success) {
        return [System.Uri]::UnescapeDataString($match.Groups[1].Value)
    }
    return $null
}

function Get-IqAppInfoByAppId {
    param([string]$Path)
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $map
    }
    [xml]$xml = Get-Content -LiteralPath $Path -Raw
    $nodes = $xml.GetElementsByTagName("IqAppInfo.StoreAppInfo")
    foreach ($node in $nodes) {
        $appId = [string]$node.AppId
        if ([string]::IsNullOrWhiteSpace($appId)) {
            continue
        }
        $map[$appId.ToLowerInvariant()] = [pscustomobject]@{
            app_id = $appId
            file_name = [string]$node.FileName
            file_size = if ([string]::IsNullOrWhiteSpace([string]$node.FileSize)) { $null } else { [int64]$node.FileSize }
            name = [string]$node.Name
            version = if ([string]::IsNullOrWhiteSpace([string]$node.Version)) { $null } else { [int64]$node.Version }
        }
    }
    return $map
}

function Add-EventIfComplete {
    param(
        [System.Collections.ArrayList]$Events,
        [hashtable]$Current
    )
    if ($null -eq $Current -or -not $Current.ContainsKey("name")) {
        return
    }
    [void]$Events.Add([pscustomobject]$Current.Clone())
}

if (-not (Test-Path -LiteralPath $LogDir)) {
    throw "Garmin Express log folder not found: $LogDir"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$expressLog = Join-Path $LogDir "Express.log"
if (-not (Test-Path -LiteralPath $expressLog)) {
    throw "Express.log not found: $expressLog"
}

$events = [System.Collections.ArrayList]::new()
$current = $null
$installPattern = "^(?<time>\d{4}-\d{2}-\d{2} [0-9:.]+)\s+\|.*Installing Store IQ item (?<name>.+?)\s*$"
$downloadPattern = "^(?<time>\d{4}-\d{2}-\d{2} [0-9:.]+)\s+\|.*Downloading file from (?<url>https?://\S+) to (?<temp>.+?)\s*$"
$transferPattern = "^(?<time>\d{4}-\d{2}-\d{2} [0-9:.]+)\s+\|.*File to transfer (?<temp>.+?) -> (?<dest>.+?) \(dataType (?<type>[^)]+)\)\s*$"

foreach ($line in Get-Content -LiteralPath $expressLog) {
    $match = [regex]::Match($line, $installPattern)
    if ($match.Success) {
        Add-EventIfComplete $events $current
        $current = @{
            install_time = $match.Groups["time"].Value
            name = $match.Groups["name"].Value.Trim()
            source_log = $expressLog
        }
        continue
    }

    if ($null -eq $current) {
        continue
    }

    $match = [regex]::Match($line, $downloadPattern)
    if ($match.Success) {
        $url = $match.Groups["url"].Value
        $current["download_time"] = $match.Groups["time"].Value
        $current["download_url"] = Redact-Url $url
        $current["download_url_sensitive_present"] = -not $IncludeSensitiveUrls
        $current["temp_path"] = $match.Groups["temp"].Value.Trim()
        $urlMatch = [regex]::Match($url, "/apps/(?<app>[0-9a-fA-F-]{36})/versions/(?<version>[0-9a-fA-F-]{36})/binaries/(?<binary>[^?&/]+)")
        if ($urlMatch.Success) {
            $current["app_id"] = $urlMatch.Groups["app"].Value.ToLowerInvariant()
            $current["version_id"] = $urlMatch.Groups["version"].Value.ToLowerInvariant()
            $current["binary_target"] = $urlMatch.Groups["binary"].Value
        }
        $current["current_firmware"] = Get-QueryValue $url "currentFirmware"
        continue
    }

    $match = [regex]::Match($line, $transferPattern)
    if ($match.Success) {
        $current["transfer_time"] = $match.Groups["time"].Value
        $current["transfer_temp_path"] = $match.Groups["temp"].Value.Trim()
        $current["watch_destination"] = $match.Groups["dest"].Value.Trim()
        $current["data_type"] = $match.Groups["type"].Value.Trim()
        $destMatch = [regex]::Match($current["watch_destination"], "([A-Za-z0-9_ -]+)\.PRG$")
        if ($destMatch.Success) {
            $current["watch_prg_stem"] = $destMatch.Groups[1].Value
        }
        continue
    }
}
Add-EventIfComplete $events $current

if ([string]::IsNullOrWhiteSpace($IqAppInfoPath)) {
    $appIds = @($events | ForEach-Object { $_.app_id } | Where-Object { $_ } | Select-Object -Unique)
    $connectIqRoot = Join-Path $env:ProgramData "Garmin\CoreService\ConnectIq"
    if (Test-Path -LiteralPath $connectIqRoot) {
        foreach ($candidate in Get-ChildItem -LiteralPath $connectIqRoot -Recurse -Filter "IQAppInfo.xml" -File -ErrorAction SilentlyContinue) {
            $text = Get-Content -LiteralPath $candidate.FullName -Raw
            foreach ($appId in $appIds) {
                if ($text -match [regex]::Escape($appId)) {
                    $IqAppInfoPath = $candidate.FullName
                    break
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($IqAppInfoPath)) {
                break
            }
        }
    }
}

$iqMap = Get-IqAppInfoByAppId $IqAppInfoPath
$enriched = @()
foreach ($event in $events) {
    $copy = [ordered]@{}
    foreach ($property in $event.PSObject.Properties) {
        $copy[$property.Name] = $property.Value
    }
    $appId = if ($copy.Contains("app_id")) { [string]$copy["app_id"] } else { "" }
    if ($appId -and $iqMap.ContainsKey($appId.ToLowerInvariant())) {
        $copy["iq_app_info"] = $iqMap[$appId.ToLowerInvariant()]
    }
    $enriched += [pscustomobject]$copy
}

$session = Join-Path $OutDir ("express-iq-installs-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $session | Out-Null
$jsonPath = Join-Path $session "installs.json"
$textPath = Join-Path $session "installs.txt"

$summary = [pscustomobject]@{
    generated_at = (Get-Date).ToString("O")
    log_dir = $LogDir
    iq_app_info_path = $IqAppInfoPath
    count = $enriched.Count
    installs = $enriched
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

$lines = @()
$lines += "Garmin Express IQ installs"
$lines += "Log dir: $LogDir"
if ($IqAppInfoPath) {
    $lines += "IQAppInfo: $IqAppInfoPath"
}
$lines += "Count: $($enriched.Count)"
$lines += ""
foreach ($event in $enriched) {
    $lines += "$($event.install_time)  $($event.name)"
    if ($event.PSObject.Properties["app_id"]) {
        $lines += "  app_id=$($event.app_id)"
    }
    if ($event.PSObject.Properties["version_id"]) {
        $lines += "  version_id=$($event.version_id)"
    }
    if ($event.PSObject.Properties["binary_target"]) {
        $lines += "  binary_target=$($event.binary_target) firmware=$($event.current_firmware)"
    }
    if ($event.PSObject.Properties["temp_path"]) {
        $lines += "  temp=$($event.temp_path)"
    }
    if ($event.PSObject.Properties["watch_destination"]) {
        $lines += "  destination=$($event.watch_destination) data_type=$($event.data_type)"
    }
    if ($event.PSObject.Properties["iq_app_info"]) {
        $info = $event.iq_app_info
        $lines += "  iq_app_info name=$($info.name) file=$($info.file_name) size=$($info.file_size) version=$($info.version)"
    }
    if ($event.PSObject.Properties["download_url"]) {
        $lines += "  url=$($event.download_url)"
    }
    $lines += ""
}
$lines -join "`n" | Set-Content -Path $textPath -Encoding UTF8

Write-Host (Get-Content -LiteralPath $textPath -Raw)
Write-Host "Summary folder: $session"
