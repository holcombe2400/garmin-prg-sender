param(
    [string]$OutputRoot = "",
    [string]$NamePrefix = "CIQ Probe",
    [string]$Device = "fenix6pro",
    [string]$DeveloperKey = "",
    [string]$MonkeyC = "",
    [string]$JavaBin = "",
    [switch]$NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $projectRoot "logs\install-probes"
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)

function Find-MonkeyC {
    if (-not [string]::IsNullOrWhiteSpace($MonkeyC)) {
        return $MonkeyC
    }
    $sdkRoot = Join-Path $env:APPDATA "Garmin\ConnectIQ\Sdks"
    if (Test-Path -LiteralPath $sdkRoot) {
        $candidate = Get-ChildItem -LiteralPath $sdkRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "bin\monkeyc.bat" } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($candidate) {
            return $candidate
        }
    }
    return "monkeyc.bat"
}

function Find-DeveloperKey {
    if (-not [string]::IsNullOrWhiteSpace($DeveloperKey)) {
        return $DeveloperKey
    }
    $candidates = @(
        (Join-Path $projectRoot "developer_key.der"),
        (Join-Path $projectRoot "keys\developer_key.der"),
        "C:\Users\holco\Documents\Codex\2026-07-14\lo\work\ciq_usb_probe\developer_key.der"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw "Developer key not found. Provide -DeveloperKey."
}

function Find-JavaBin {
    if (-not [string]::IsNullOrWhiteSpace($JavaBin)) {
        return $JavaBin
    }
    $candidates = @(
        "C:\Users\holco\Documents\Codex\2026-07-08\can\tools\java\jdk-17.0.19+10-jre\bin",
        (Join-Path $projectRoot "tools\java\bin")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "java.exe")) {
            return $candidate
        }
    }
    return ""
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Value
    )
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $utf8)
}

function Escape-MonkeyString {
    param([string]$Value)
    return ($Value -replace "\\", "\\") -replace '"', '\"'
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$guid = [Guid]::NewGuid()
$appId = $guid.ToString("N").ToUpperInvariant()
$suffix = Get-Date -Format "HHmmss"
$appName = "$NamePrefix $suffix"
$fileBase = "CiqProbe_$stamp"
$projectDir = Join-Path $OutputRoot $fileBase
$sourceDir = Join-Path $projectDir "source"
$stringsDir = Join-Path $projectDir "resources\strings"
$drawablesDir = Join-Path $projectDir "resources\drawables"
$binDir = Join-Path $projectDir "bin"
New-Item -ItemType Directory -Force -Path $sourceDir, $stringsDir, $drawablesDir, $binDir | Out-Null

$manifest = @"
<iq:manifest xmlns:iq="http://www.garmin.com/xml/connectiq" version="1">
    <iq:application entry="InstallProbeApp" id="$appId" launcherIcon="@Drawables.LauncherIcon" minSdkVersion="3.1.0" name="@Strings.AppName" type="watch-app">
        <iq:products>
            <iq:product id="fenix6"/>
            <iq:product id="fenix6pro"/>
            <iq:product id="fenix6s"/>
            <iq:product id="fenix6spro"/>
            <iq:product id="fenix6xpro"/>
        </iq:products>
        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>
    </iq:application>
</iq:manifest>
"@
Write-Utf8NoBom (Join-Path $projectDir "manifest.xml") $manifest
Write-Utf8NoBom (Join-Path $projectDir "monkey.jungle") "project.manifest = manifest.xml`r`n"

$strings = @"
<strings xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">
    <string id="AppName">$appName</string>
</strings>
"@
Write-Utf8NoBom (Join-Path $stringsDir "strings.xml") $strings

$drawables = @"
<drawables xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">
    <bitmap id="LauncherIcon" filename="launcher_icon.png" />
</drawables>
"@
Write-Utf8NoBom (Join-Path $drawablesDir "drawables.xml") $drawables

$iconBase64 = "iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAESSURBVFhH7Y5BDsMgDATz/+/lQa1yQHLG2NgQKFW70lwWY89xHMdrc1SxG6rYDVXshirCZMK/CVTRZCTcFUAVJsx5nmEY7nZQRRUZHs8gwxsGqrjB8GAPDG92CfLIEwwLzpQrBCRVcZNbJXiFDiFBLpxBWnClXMGRVMXegp+QKxiSOUHOZ+G+v2AW7lsmyDlrljOSpqAMP/cezcxeVCTvCz4pWJEbF+Q7ycxPEWwdzcz+rqB1mDPWXCEkeNGSnIEh96WCqyUdubbgbEkZOriCUpJLn6Qh5wvOlgzIxQVLeKQHhjdTggUZHswgwxsGqjBheNyD4W4HVTTxUpOR4a4AqgiTCf8mUMUQgzI1VLEbqtiKN1zYIdGxrNjKAAAAAElFTkSuQmCC"
[System.IO.File]::WriteAllBytes((Join-Path $drawablesDir "launcher_icon.png"), [Convert]::FromBase64String($iconBase64))

$escapedName = Escape-MonkeyString $appName
$idShort = $appId.Substring(0, 8)
$source = @"
import Toybox.Application;
import Toybox.Graphics;
import Toybox.WatchUi;

class InstallProbeApp extends Application.AppBase {
    public function initialize() {
        AppBase.initialize();
    }

    public function getInitialView() {
        return [new InstallProbeView()];
    }
}

class InstallProbeView extends WatchUi.View {
    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (h / 2) - 20, Graphics.FONT_SMALL, "$escapedName", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, (h / 2) + 6, Graphics.FONT_XTINY, "$idShort", Graphics.TEXT_JUSTIFY_CENTER);
    }
}
"@
Write-Utf8NoBom (Join-Path $sourceDir "InstallProbeApp.mc") $source

$prgPath = Join-Path $binDir "$fileBase`_$Device.prg"
$metadataPath = Join-Path $projectDir "metadata.json"
$metadata = [ordered]@{
    created_at = (Get-Date).ToString("O")
    app_name = $appName
    app_id = $appId
    app_id_dashed = $guid.ToString()
    file_base = "$fileBase`_$Device"
    project_dir = $projectDir
    prg_path = $prgPath
    device = $Device
    built = $false
}

if (-not $NoBuild) {
    $monkeycPath = Find-MonkeyC
    $developerKeyPath = Find-DeveloperKey
    $javaPath = Find-JavaBin
    if (-not [string]::IsNullOrWhiteSpace($javaPath)) {
        $env:PATH = "$javaPath;$env:PATH"
    }
    Push-Location $projectDir
    try {
        & $monkeycPath -f monkey.jungle -d $Device -o $prgPath -y $developerKeyPath -w
    } finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $prgPath)) {
        throw "Build did not create PRG: $prgPath"
    }
    $metadata["built"] = $true
    $metadata["prg_size"] = (Get-Item -LiteralPath $prgPath).Length
    $metadata["monkeyc"] = $monkeycPath
    $metadata["developer_key"] = $developerKeyPath
}

$metadata | ConvertTo-Json -Depth 8 | Set-Content -Path $metadataPath -Encoding UTF8
Write-Host "Install probe project: $projectDir"
Write-Host "App name: $appName"
Write-Host "App id: $appId"
Write-Host "File base: $fileBase`_$Device"
if ($metadata["built"]) {
    Write-Host "PRG: $prgPath"
    Write-Host "PRG size: $($metadata["prg_size"])"
}
Write-Host "Metadata: $metadataPath"
