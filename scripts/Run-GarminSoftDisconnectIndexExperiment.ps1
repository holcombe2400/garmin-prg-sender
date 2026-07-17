param(
    [string]$Prg = "",
    [string]$DevicePattern = "fenix|Garmin",
    [string]$OutDir = "",
    [string]$BleAddress = "",
    [string]$Python = "",
    [int]$TimeoutSeconds = 180,
    [int]$MtpReturnTimeoutSeconds = 45,
    [switch]$TryShellEject,
    [switch]$TryWpdReset,
    [switch]$TryPnpEject,
    [switch]$TryPnpDisableEnable,
    [switch]$TryPnpRemoveSubtree,
    [switch]$TryUsbHubPortCycle,
    [switch]$TryPnpRestart,
    [switch]$NoStage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot "logs\soft-disconnect-index-experiments"
}

$collectScript = Join-Path $scriptRoot "Collect-GarminAppsSnapshotMtp.ps1"
$installScript = Join-Path $scriptRoot "Install-GarminPrgMtp.ps1"
$compareScript = Join-Path $scriptRoot "Compare-GarminAppsSnapshots.py"
$probeScript = Join-Path $scriptRoot "New-CiqInstallProbe.ps1"
$wpdCommandScript = Join-Path $scriptRoot "Invoke-WpdDeviceCommand.ps1"
foreach ($path in @($collectScript, $installScript, $compareScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

function Find-Python {
    if (-not [string]::IsNullOrWhiteSpace($Python)) {
        return $Python
    }
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

function Save-Json {
    param(
        [string]$Name,
        [object]$Value
    )
    $Value | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $script:Session $Name) -Encoding UTF8
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

function Get-MtpDeviceItem {
    $shell = New-Object -ComObject Shell.Application
    $computer = $shell.Namespace(17)
    foreach ($device in $computer.Items()) {
        if ($device.Name -match $DevicePattern) {
            return $device
        }
    }
    throw "No MTP device matched pattern '$DevicePattern'."
}

function Get-ShellVerbRows {
    param([object]$Device)
    $rows = @()
    foreach ($verb in $Device.Verbs()) {
        $rows += [pscustomobject]@{
            object = "device"
            name = $Device.Name
            verb = $verb.Name
        }
    }
    foreach ($item in $Device.GetFolder.Items()) {
        foreach ($verb in $item.Verbs()) {
            $rows += [pscustomobject]@{
                object = "device-child"
                name = $item.Name
                verb = $verb.Name
            }
        }
    }
    return @($rows)
}

function Invoke-ShellEjectIfPresent {
    param([object]$Device)
    $verbs = @($Device.Verbs())
    foreach ($verb in $verbs) {
        $clean = ([string]$verb.Name) -replace "&", ""
        if ($clean -match "^(Eject|Disconnect|Remove)$") {
            Write-TextLog "Invoking shell verb '$($verb.Name)' on '$($Device.Name)'."
            $verb.DoIt()
            return $true
        }
    }
    Write-TextLog "No shell Eject/Disconnect/Remove verb was present on '$($Device.Name)'."
    return $false
}

function Get-GarminPnpDevices {
    try {
        return @(Get-PnpDevice -PresentOnly |
            Where-Object {
                $_.FriendlyName -match "Garmin|fenix|MTP|Portable|WPD" -or
                $_.InstanceId -match "VID_091E|GARMIN"
            } |
            Select-Object Status, Class, FriendlyName, InstanceId)
    } catch {
        return @([pscustomobject]@{ error = $_.Exception.Message })
    }
}

function Get-GarminInstanceId {
    $devices = @(Get-GarminPnpDevices | Where-Object {
        $_.PSObject.Properties["InstanceId"] -and
        ([string]$_.InstanceId) -match "VID_091E" -and
        ([string]$_.FriendlyName) -match "fenix|Garmin"
    })
    if ($devices.Count -lt 1) {
        return $null
    }
    $preferred = @($devices | Where-Object {
        ([string]$_.InstanceId) -match "PID_4CDA" -and
        ([string]$_.Status) -eq "OK"
    } | Select-Object -First 1)
    if ($preferred.Count -gt 0) {
        return [string]$preferred[0].InstanceId
    }

    $mtp = @($devices | Where-Object {
        ([string]$_.InstanceId) -match "PID_4CDA"
    } | Select-Object -First 1)
    if ($mtp.Count -gt 0) {
        return [string]$mtp[0].InstanceId
    }

    return [string]$devices[0].InstanceId
}

function Invoke-PnpRestart {
    $instanceId = Get-GarminInstanceId
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        Write-TextLog "No Garmin VID_091E PnP instance id found; cannot restart."
        return $false
    }
    Write-TextLog "Restarting Garmin PnP device: $instanceId"
    $output = & pnputil /restart-device $instanceId 2>&1
    $output | Set-Content -Path (Join-Path $script:Session "pnputil-restart-output.txt") -Encoding UTF8
    Write-TextLog "pnputil /restart-device finished with exit code $LASTEXITCODE."
    $text = ($output | Out-String)
    return (($LASTEXITCODE -eq 0) -and ($text -notmatch "Failed to restart device"))
}

function Invoke-PnpDisableEnable {
    $instanceId = Get-GarminInstanceId
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        Write-TextLog "No Garmin VID_091E PnP instance id found; cannot disable/enable."
        return $false
    }

    Write-TextLog "Disabling Garmin PnP device: $instanceId"
    $disableOutput = & pnputil /disable-device $instanceId 2>&1
    $disableExit = $LASTEXITCODE
    $disableOutput | Set-Content -Path (Join-Path $script:Session "pnputil-disable-output.txt") -Encoding UTF8
    foreach ($line in @($disableOutput | Select-Object -Last 12)) {
        Write-TextLog "[pnputil-disable] $line"
    }
    Write-TextLog "pnputil /disable-device finished with exit code $disableExit."
    $disableText = ($disableOutput | Out-String)
    $disableSucceeded = (($disableExit -eq 0) -and ($disableText -notmatch "Failed to disable device"))
    if (-not $disableSucceeded) {
        return $false
    }

    Start-Sleep -Seconds 5
    Write-TextLog "Enabling Garmin PnP device: $instanceId"
    $enableOutput = & pnputil /enable-device $instanceId 2>&1
    $enableExit = $LASTEXITCODE
    $enableOutput | Set-Content -Path (Join-Path $script:Session "pnputil-enable-output.txt") -Encoding UTF8
    foreach ($line in @($enableOutput | Select-Object -Last 12)) {
        Write-TextLog "[pnputil-enable] $line"
    }
    Write-TextLog "pnputil /enable-device finished with exit code $enableExit."
    $enableText = ($enableOutput | Out-String)
    return (($enableExit -eq 0) -and ($enableText -notmatch "Failed to enable device"))
}

function Invoke-PnpRemoveSubtree {
    $instanceId = Get-GarminInstanceId
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        Write-TextLog "No Garmin VID_091E PnP instance id found; cannot remove subtree."
        return $false
    }

    Write-TextLog "Removing Garmin PnP device subtree: $instanceId"
    $removeOutput = & pnputil /remove-device $instanceId /subtree 2>&1
    $removeExit = $LASTEXITCODE
    $removeOutput | Set-Content -Path (Join-Path $script:Session "pnputil-remove-subtree-output.txt") -Encoding UTF8
    foreach ($line in @($removeOutput | Select-Object -Last 12)) {
        Write-TextLog "[pnputil-remove-subtree] $line"
    }
    Write-TextLog "pnputil /remove-device /subtree finished with exit code $removeExit."
    $removeText = ($removeOutput | Out-String)

    Start-Sleep -Seconds 5
    Write-TextLog "Scanning for hardware changes after remove-subtree."
    $scanOutput = & pnputil /scan-devices 2>&1
    $scanExit = $LASTEXITCODE
    $scanOutput | Set-Content -Path (Join-Path $script:Session "pnputil-scan-devices-output.txt") -Encoding UTF8
    foreach ($line in @($scanOutput | Select-Object -Last 12)) {
        Write-TextLog "[pnputil-scan-devices] $line"
    }
    Write-TextLog "pnputil /scan-devices finished with exit code $scanExit."
    return (($removeExit -eq 0) -and ($removeText -notmatch "Failed to remove device"))
}

function Convert-UsbHubInstanceIdToInterfacePath {
    param([string]$InstanceId)
    $devicePath = ([string]$InstanceId).ToLowerInvariant() -replace "\\", "#"
    return "\\?\$devicePath#{f18a0e88-c30c-11d0-8815-00a0c906bed8}"
}

function Get-PnpPropertyData {
    param(
        [string]$InstanceId,
        [string]$KeyName
    )
    try {
        $property = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop
        return $property.Data
    } catch {
        Write-TextLog "Could not read PnP property $KeyName from $InstanceId`: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-UsbHubPortCycle {
    $instanceId = Get-GarminInstanceId
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        Write-TextLog "No Garmin VID_091E PnP instance id found; cannot USB hub port-cycle."
        return $false
    }

    $parentHub = [string](Get-PnpPropertyData -InstanceId $instanceId -KeyName "DEVPKEY_Device_Parent")
    $portNumber = Get-PnpPropertyData -InstanceId $instanceId -KeyName "DEVPKEY_Device_Address"
    $locationInfo = [string](Get-PnpPropertyData -InstanceId $instanceId -KeyName "DEVPKEY_Device_LocationInfo")
    $locationPaths = @(Get-PnpPropertyData -InstanceId $instanceId -KeyName "DEVPKEY_Device_LocationPaths")
    if (($null -eq $portNumber) -and ($locationInfo -match "Port_#0*([0-9]+)")) {
        $portNumber = [int]$Matches[1]
    }
    if ([string]::IsNullOrWhiteSpace($parentHub) -or ($null -eq $portNumber)) {
        Write-TextLog "Missing parent hub or port number for $instanceId; cannot USB hub port-cycle."
        return $false
    }

    $portNumber = [uint32]$portNumber
    $hubPath = Convert-UsbHubInstanceIdToInterfacePath $parentHub
    $target = [pscustomobject]@{
        instance_id = $instanceId
        parent_hub = $parentHub
        hub_interface_path = $hubPath
        port_number = $portNumber
        location_info = $locationInfo
        location_paths = $locationPaths
    }
    Save-Json "usb-hub-port-cycle-target.json" $target

    $source = @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace GarminPrgSender.UsbHub {
    public sealed class CyclePortResult {
        public string HubPath { get; set; }
        public uint PortNumber { get; set; }
        public bool Succeeded { get; set; }
        public int Win32Error { get; set; }
        public string ErrorMessage { get; set; }
        public uint StatusReturned { get; set; }
        public int BytesReturned { get; set; }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct UsbCyclePortParams {
        public uint ConnectionIndex;
        public uint StatusReturned;
    }

    public static class HubPortCycler {
        private const uint GENERIC_READ = 0x80000000;
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private const uint IOCTL_USB_HUB_CYCLE_PORT = 0x00220444;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(
            SafeFileHandle device,
            uint ioControlCode,
            ref UsbCyclePortParams inBuffer,
            int inBufferSize,
            ref UsbCyclePortParams outBuffer,
            int outBufferSize,
            out int bytesReturned,
            IntPtr overlapped);

        public static CyclePortResult Cycle(string hubPath, uint portNumber) {
            var result = new CyclePortResult {
                HubPath = hubPath,
                PortNumber = portNumber
            };

            using (var handle = CreateFileW(
                hubPath,
                GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                IntPtr.Zero,
                OPEN_EXISTING,
                0,
                IntPtr.Zero)) {
                if (handle.IsInvalid) {
                    result.Win32Error = Marshal.GetLastWin32Error();
                    result.ErrorMessage = new Win32Exception(result.Win32Error).Message;
                    return result;
                }

                var input = new UsbCyclePortParams { ConnectionIndex = portNumber, StatusReturned = 0 };
                var output = input;
                int bytesReturned;
                int size = Marshal.SizeOf(typeof(UsbCyclePortParams));
                result.Succeeded = DeviceIoControl(
                    handle,
                    IOCTL_USB_HUB_CYCLE_PORT,
                    ref input,
                    size,
                    ref output,
                    size,
                    out bytesReturned,
                    IntPtr.Zero);
                result.BytesReturned = bytesReturned;
                result.StatusReturned = output.StatusReturned;
                if (!result.Succeeded) {
                    result.Win32Error = Marshal.GetLastWin32Error();
                    result.ErrorMessage = new Win32Exception(result.Win32Error).Message;
                }
                return result;
            }
        }
    }
}
"@

    if (-not ("GarminPrgSender.UsbHub.HubPortCycler" -as [type])) {
        Add-Type -Language CSharp -TypeDefinition $source
    }

    Write-TextLog "Cycling USB hub port $portNumber for Garmin device: $instanceId"
    Write-TextLog "Parent hub: $parentHub"
    $result = [GarminPrgSender.UsbHub.HubPortCycler]::Cycle($hubPath, $portNumber)
    Save-Json "usb-hub-port-cycle-result.json" $result
    Write-TextLog "USB hub port-cycle Succeeded=$($result.Succeeded) Win32Error=$($result.Win32Error) Error='$($result.ErrorMessage)' StatusReturned=$($result.StatusReturned) BytesReturned=$($result.BytesReturned)"
    return [bool]$result.Succeeded
}

function Invoke-PnpEject {
    $instanceId = Get-GarminInstanceId
    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        Write-TextLog "No Garmin VID_091E PnP instance id found; cannot request eject."
        return $false
    }

    $source = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace GarminPrgSender.CfgMgr {
    public enum PnpVetoType : uint {
        Ok = 0,
        TypeUnknown = 1,
        LegacyDevice = 2,
        PendingClose = 3,
        WindowsApp = 4,
        WindowsService = 5,
        OutstandingOpen = 6,
        Device = 7,
        Driver = 8,
        IllegalDeviceRequest = 9,
        InsufficientPower = 10,
        NonDisableable = 11,
        LegacyDriver = 12,
        InsufficientRights = 13
    }

    public sealed class EjectResult {
        public string InstanceId { get; set; }
        public uint LocateConfigRet { get; set; }
        public uint EjectConfigRet { get; set; }
        public PnpVetoType VetoType { get; set; }
        public string VetoName { get; set; }
        public bool Succeeded { get { return LocateConfigRet == 0 && EjectConfigRet == 0 && VetoType == PnpVetoType.Ok; } }
        public string LocateConfigRetHex { get { return "0x" + LocateConfigRet.ToString("X8"); } }
        public string EjectConfigRetHex { get { return "0x" + EjectConfigRet.ToString("X8"); } }
    }

    public static class DeviceEject {
        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
        private static extern uint CM_Locate_DevNodeW(out uint pdnDevInst, string pDeviceID, uint ulFlags);

        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
        private static extern uint CM_Request_Device_EjectW(uint dnDevInst, out PnpVetoType pVetoType, StringBuilder pszVetoName, uint ulNameLength, uint ulFlags);

        public static EjectResult Request(string instanceId) {
            uint devInst;
            uint locate = CM_Locate_DevNodeW(out devInst, instanceId, 0);
            PnpVetoType veto = PnpVetoType.Ok;
            string vetoName = "";
            uint eject = 0xFFFFFFFF;
            if (locate == 0) {
                var buffer = new StringBuilder(1024);
                eject = CM_Request_Device_EjectW(devInst, out veto, buffer, (uint)buffer.Capacity, 0);
                vetoName = buffer.ToString();
            }
            return new EjectResult {
                InstanceId = instanceId,
                LocateConfigRet = locate,
                EjectConfigRet = eject,
                VetoType = veto,
                VetoName = vetoName
            };
        }
    }
}
"@

    if (-not ("GarminPrgSender.CfgMgr.DeviceEject" -as [type])) {
        Add-Type -Language CSharp -TypeDefinition $source
    }

    Write-TextLog "Requesting PnP eject for Garmin device: $instanceId"
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $result = [GarminPrgSender.CfgMgr.DeviceEject]::Request($instanceId)
    $result | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $script:Session "cm-request-device-eject-result.json") -Encoding UTF8
    Write-TextLog "CM_Locate_DevNode=$($result.LocateConfigRetHex) CM_Request_Device_Eject=$($result.EjectConfigRetHex) Veto=$($result.VetoType) VetoName='$($result.VetoName)' Succeeded=$($result.Succeeded)"
    return [bool]$result.Succeeded
}

function Invoke-WpdReset {
    if (-not (Test-Path -LiteralPath $wpdCommandScript)) {
        throw "WPD command helper not found: $wpdCommandScript"
    }
    Write-TextLog "Sending WPD COMMON_RESET_DEVICE to Garmin device."
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $wpdCommandScript -Command ResetDevice -DevicePattern $DevicePattern -Access ReadOnly 2>&1
    $exitCode = $LASTEXITCODE
    $output | Set-Content -Path (Join-Path $script:Session "wpd-reset-output.txt") -Encoding UTF8
    foreach ($line in @($output | Select-Object -Last 12)) {
        Write-TextLog "[wpd-reset] $line"
    }
    Write-TextLog "WPD ResetDevice helper finished with exit code $exitCode."
    return ($exitCode -eq 0)
}

function Wait-MtpVisible {
    param(
        [bool]$Visible,
        [int]$Timeout
    )
    $deadline = (Get-Date).AddSeconds($Timeout)
    while ((Get-Date) -lt $deadline) {
        $found = $false
        try {
            [void](Get-MtpDeviceItem)
            $found = $true
        } catch {
            $found = $false
        }
        if ($found -eq $Visible) {
            return $true
        }
        Start-Sleep -Seconds 1
    }
    return $false
}

function New-ProbeIfNeeded {
    if (-not [string]::IsNullOrWhiteSpace($Prg)) {
        return $Prg
    }
    if ($NoStage) {
        return ""
    }
    if (-not (Test-Path -LiteralPath $probeScript)) {
        throw "No PRG was supplied and probe generator was not found: $probeScript"
    }
    $probeRoot = Join-Path $script:Session "generated-probe"
    $probeOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $probeScript -OutputRoot $probeRoot -NamePrefix "SoftDisc Probe" 2>&1
    Write-ChildOutput "generate-probe" $probeOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Probe generator failed with exit code $LASTEXITCODE."
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
        [string]$Name,
        [object]$Target
    )
    $python = Find-Python
    $diffJson = Join-Path $script:Session "$Name.json"
    $diffText = Join-Path $script:Session "$Name.txt"
    $compareArgs = @(
        $compareScript,
        $Before,
        $After,
        "--json",
        $diffJson,
        "--text",
        $diffText
    )
    if ($Target.filename) {
        $compareArgs += @("--target-filename", $Target.filename)
    }
    if ($Target.name) {
        $compareArgs += @("--target-name", $Target.name)
    }
    if ($Target.uuid) {
        $compareArgs += @("--target-uuid", $Target.uuid)
    }
    $compareOutput = & $python @compareArgs 2>&1
    Write-ChildOutput "compare-$Name" $compareOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Snapshot comparison '$Name' failed with exit code $LASTEXITCODE."
    }
}

function Invoke-BleInstalledAppsVerification {
    param([object]$Target)
    if ([string]::IsNullOrWhiteSpace($BleAddress)) {
        Write-TextLog "No BLE address supplied; skipping BLE installed-app verification."
        return $null
    }
    $sendPrg = Join-Path $projectRoot "send_prg.py"
    if (-not (Test-Path -LiteralPath $sendPrg)) {
        Write-TextLog "send_prg.py not found; skipping BLE installed-app verification."
        return $null
    }
    $python = Find-Python
    $packetLog = Join-Path $script:Session "ble-installed-apps.jsonl"
    $args = @(
        "-B",
        $sendPrg,
        "--query-installed-apps",
        "--address",
        $BleAddress,
        "--winrt-services",
        "cached",
        "--connect-timeout",
        "75",
        "--timeout",
        "15",
        "--packet-log",
        $packetLog,
        "--packet-log-bytes",
        "256"
    )
    $verifyId = ""
    if ($Target.PSObject.Properties["uuid_dashed"] -and $Target.uuid_dashed) {
        $verifyId = [string]$Target.uuid_dashed
    } elseif ($Target.uuid) {
        $verifyId = [string]$Target.uuid
    }
    if ($verifyId) {
        $args += @("--verify-app-id", $verifyId)
    }
    if ($Target.name) {
        $args += @("--verify-app-name", [string]$Target.name)
    }
    Write-TextLog "Running BLE installed-app verification against $BleAddress."
    $bleOutput = & $python @args 2>&1
    Write-ChildOutput "ble-installed-apps" $bleOutput
    $registered = @($bleOutput | Where-Object { [string]$_ -match " is registered$" }).Count -gt 0
    $result = [pscustomobject]@{
        address = $BleAddress
        exit_code = $LASTEXITCODE
        registered = $registered
        packet_log = $packetLog
        target_name = $Target.name
        target_uuid = $verifyId
    }
    Save-Json "ble-installed-apps-result.json" $result
    if ($registered) {
        Write-TextLog "BLE verification result: target is registered."
    } else {
        Write-TextLog "BLE verification result: target was not confirmed registered."
    }
    return $registered
}

function Run-Snapshot {
    param([string]$Name)
    $path = Join-Path $script:Session $Name
    $snapshotOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $collectScript -DevicePattern $DevicePattern -SnapshotDir $path -Label $Name -TimeoutSeconds $TimeoutSeconds 2>&1
    Write-ChildOutput "snapshot-$Name" $snapshotOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Snapshot '$Name' failed with exit code $LASTEXITCODE."
    }
    return ,$path
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:Session = Join-Path $OutDir ("soft-disconnect-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $script:Session | Out-Null
$script:TextLog = Join-Path $script:Session "record.txt"

Write-TextLog "Soft USB disconnect/index experiment started."
Write-TextLog "Session: $script:Session"
Write-TextLog "TryShellEject=$TryShellEject TryWpdReset=$TryWpdReset TryPnpEject=$TryPnpEject TryPnpDisableEnable=$TryPnpDisableEnable TryPnpRemoveSubtree=$TryPnpRemoveSubtree TryUsbHubPortCycle=$TryUsbHubPortCycle TryPnpRestart=$TryPnpRestart NoStage=$NoStage BleAddress=$BleAddress"

$device = Get-MtpDeviceItem
Write-TextLog "MTP device found: $($device.Name)"
Save-Json "shell-verbs.json" (Get-ShellVerbRows $device)
Save-Json "pnp-before.json" (Get-GarminPnpDevices)

$targetPrg = New-ProbeIfNeeded
$target = Get-TargetMetadata $targetPrg
Save-Json "target.json" $target

$before = Run-Snapshot "before"

if (-not $NoStage) {
    if (-not (Test-Path -LiteralPath $targetPrg)) {
        throw "Target PRG does not exist: $targetPrg"
    }
    Write-TextLog "Staging PRG over MTP: $targetPrg"
    $installLogs = Join-Path $script:Session "stage-copy"
    $stageOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript -Prg $targetPrg -DevicePattern $DevicePattern -LogDir $installLogs -Copy -TimeoutSeconds $TimeoutSeconds 2>&1
    Write-ChildOutput "stage-copy" $stageOutput
    if ($LASTEXITCODE -ne 0) {
        throw "MTP staging failed with exit code $LASTEXITCODE."
    }
} else {
    Write-TextLog "NoStage set; skipping PRG copy."
}

$staged = Run-Snapshot "after-stage-before-soft-disconnect"
Compare-Snapshots $before $staged "before-to-after-stage-diff" $target

$triggered = $false
if ($TryShellEject) {
    $device = Get-MtpDeviceItem
    $triggered = (Invoke-ShellEjectIfPresent $device) -or $triggered
    if ($triggered) {
        [void](Wait-MtpVisible -Visible:$false -Timeout 30)
        [void](Wait-MtpVisible -Visible:$true -Timeout $TimeoutSeconds)
    }
}

if ($TryWpdReset) {
    $triggered = (Invoke-WpdReset) -or $triggered
    [void](Wait-MtpVisible -Visible:$false -Timeout 15)
    [void](Wait-MtpVisible -Visible:$true -Timeout $TimeoutSeconds)
}

if ($TryPnpEject) {
    $device = $null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $triggered = (Invoke-PnpEject) -or $triggered
    [void](Wait-MtpVisible -Visible:$false -Timeout 15)
    [void](Wait-MtpVisible -Visible:$true -Timeout $TimeoutSeconds)
}

if ($TryPnpDisableEnable) {
    $device = $null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $triggered = (Invoke-PnpDisableEnable) -or $triggered
    [void](Wait-MtpVisible -Visible:$false -Timeout 30)
    [void](Wait-MtpVisible -Visible:$true -Timeout $TimeoutSeconds)
}

if ($TryPnpRemoveSubtree) {
    $device = $null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $triggered = (Invoke-PnpRemoveSubtree) -or $triggered
    [void](Wait-MtpVisible -Visible:$false -Timeout 30)
    [void](Wait-MtpVisible -Visible:$true -Timeout $TimeoutSeconds)
}

if ($TryUsbHubPortCycle) {
    $device = $null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $triggered = (Invoke-UsbHubPortCycle) -or $triggered
    [void](Wait-MtpVisible -Visible:$false -Timeout 30)
    [void](Wait-MtpVisible -Visible:$true -Timeout $TimeoutSeconds)
}

if ($TryPnpRestart) {
    $triggered = (Invoke-PnpRestart) -or $triggered
    [void](Wait-MtpVisible -Visible:$false -Timeout 15)
    [void](Wait-MtpVisible -Visible:$true -Timeout $TimeoutSeconds)
}

if (-not $triggered) {
    Write-TextLog "No soft-disconnect trigger was invoked. Collecting final snapshot for baseline."
} else {
    Write-TextLog "Waiting 20 seconds after soft-disconnect trigger before final snapshot."
    Start-Sleep -Seconds 20
}

Save-Json "pnp-after-trigger.json" (Get-GarminPnpDevices)

$mtpVisible = Wait-MtpVisible -Visible:$true -Timeout $MtpReturnTimeoutSeconds
if ($mtpVisible) {
    Write-TextLog "MTP returned; collecting final MTP snapshot."
    $after = Run-Snapshot "after-soft-disconnect"
    Compare-Snapshots $before $after "before-to-after-soft-disconnect-diff" $target
} else {
    Write-TextLog "MTP did not return within $MtpReturnTimeoutSeconds seconds; skipping final MTP snapshot."
    [void](Invoke-BleInstalledAppsVerification $target)
}

Write-TextLog "Experiment complete."
Write-TextLog "Session: $script:Session"
