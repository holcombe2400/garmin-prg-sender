param(
    [ValidateSet("List", "ListRootObjects", "ResetDevice", "StorageEject")]
    [string]$Command = "List",
    [string]$DevicePattern = "fenix|Garmin",
    [string]$ObjectId = "",
    [ValidateSet("ReadOnly", "ReadWrite")]
    [string]$Access = "ReadOnly"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace GarminPrgSender.Wpd {
    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY {
        public Guid fmtid;
        public uint pid;

        public PROPERTYKEY(Guid fmtid, uint pid) {
            this.fmtid = fmtid;
            this.pid = pid;
        }

        public override string ToString() {
            return fmtid.ToString("B") + " " + pid.ToString();
        }
    }

    [ComImport, Guid("0af10cec-2ecd-4b92-9581-34f6ae0637f3")]
    public class PortableDeviceManagerClass {}

    [ComImport, Guid("728a21c5-3d9e-48d7-9810-864848f0f404")]
    public class PortableDeviceClass {}

    [ComImport, Guid("0c15d503-d017-47ce-9016-7b3f978721cc")]
    public class PortableDeviceValuesClass {}

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("a1567595-4c2f-4574-a6fa-ecef917b9a40")]
    public interface IPortableDeviceManager {
        [PreserveSig] int GetDevices(IntPtr pPnPDeviceIDs, ref uint pcPnPDeviceIDs);
        [PreserveSig] int RefreshDeviceList();
        [PreserveSig] int GetDeviceFriendlyName([MarshalAs(UnmanagedType.LPWStr)] string pszPnPDeviceID, IntPtr pDeviceFriendlyName, ref uint pcchDeviceFriendlyName);
        [PreserveSig] int GetDeviceDescription([MarshalAs(UnmanagedType.LPWStr)] string pszPnPDeviceID, IntPtr pDeviceDescription, ref uint pcchDeviceDescription);
        [PreserveSig] int GetDeviceManufacturer([MarshalAs(UnmanagedType.LPWStr)] string pszPnPDeviceID, IntPtr pDeviceManufacturer, ref uint pcchDeviceManufacturer);
        [PreserveSig] int GetDeviceProperty([MarshalAs(UnmanagedType.LPWStr)] string pszPnPDeviceID, [MarshalAs(UnmanagedType.LPWStr)] string pszDevicePropertyName, IntPtr pData, ref uint pcbData, ref uint pdwType);
        [PreserveSig] int GetPrivateDevices(IntPtr pPnPDeviceIDs, ref uint pcPnPDeviceIDs);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("625e2df8-6392-4cf0-9ad1-3cfa5f17775c")]
    public interface IPortableDevice {
        [PreserveSig] int Open([MarshalAs(UnmanagedType.LPWStr)] string pszPnPDeviceID, IPortableDeviceValues pClientInfo);
        [PreserveSig] int SendCommand(uint dwFlags, IPortableDeviceValues pParameters, out IPortableDeviceValues ppResults);
        [PreserveSig] int Content(out IPortableDeviceContent ppContent);
        [PreserveSig] int Capabilities(out IntPtr ppCapabilities);
        [PreserveSig] int Cancel();
        [PreserveSig] int Close();
        [PreserveSig] int Advise(uint dwFlags, IntPtr pCallback, IPortableDeviceValues pParameters, out IntPtr ppszCookie);
        [PreserveSig] int Unadvise([MarshalAs(UnmanagedType.LPWStr)] string pszCookie);
        [PreserveSig] int GetPnPDeviceID(out IntPtr ppszPnPDeviceID);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("6a96ed84-7c73-4480-9938-bf5af477d426")]
    public interface IPortableDeviceContent {
        [PreserveSig] int EnumObjects(uint dwFlags, [MarshalAs(UnmanagedType.LPWStr)] string pszParentObjectID, IPortableDeviceValues pFilter, out IEnumPortableDeviceObjectIDs ppEnum);
        [PreserveSig] int Properties(out IntPtr ppProperties);
        [PreserveSig] int Transfer(out IntPtr ppResources);
        [PreserveSig] int CreateObjectWithPropertiesOnly(IPortableDeviceValues pValues, out IntPtr ppszObjectID);
        [PreserveSig] int CreateObjectWithPropertiesAndData(IPortableDeviceValues pValues, out IntPtr ppData, out uint pdwOptimalWriteBufferSize, out IntPtr ppszCookie);
        [PreserveSig] int Delete(uint dwOptions, IntPtr pObjectIDs, out IntPtr ppResults);
        [PreserveSig] int GetObjectIDsFromPersistentUniqueIDs(IntPtr pPersistentUniqueIDs, out IntPtr ppObjectIDs);
        [PreserveSig] int Cancel();
        [PreserveSig] int Move(IntPtr pObjectIDs, [MarshalAs(UnmanagedType.LPWStr)] string pszDestinationFolderObjectID, out IntPtr ppResults);
        [PreserveSig] int Copy(IntPtr pObjectIDs, [MarshalAs(UnmanagedType.LPWStr)] string pszDestinationFolderObjectID, out IntPtr ppResults);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("10ece955-cf41-4728-bfa0-41eedf1bbf19")]
    public interface IEnumPortableDeviceObjectIDs {
        [PreserveSig] int Next(uint cObjects, IntPtr pObjIDs, ref uint pcFetched);
        [PreserveSig] int Skip(uint cObjects);
        [PreserveSig] int Reset();
        [PreserveSig] int Clone(out IEnumPortableDeviceObjectIDs ppEnum);
        [PreserveSig] int Cancel();
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("6848f6f2-3155-4f86-b6f5-263eeeab3143")]
    public interface IPortableDeviceValues {
        [PreserveSig] int GetCount(out uint pcelt);
        [PreserveSig] int GetAt(uint index, out PROPERTYKEY pKey, IntPtr pValue);
        [PreserveSig] int SetValue(ref PROPERTYKEY key, IntPtr pValue);
        [PreserveSig] int GetValue(ref PROPERTYKEY key, IntPtr pValue);
        [PreserveSig] int SetStringValue(ref PROPERTYKEY key, [MarshalAs(UnmanagedType.LPWStr)] string Value);
        [PreserveSig] int GetStringValue(ref PROPERTYKEY key, out IntPtr pValue);
        [PreserveSig] int SetUnsignedIntegerValue(ref PROPERTYKEY key, uint Value);
        [PreserveSig] int GetUnsignedIntegerValue(ref PROPERTYKEY key, out uint Value);
        [PreserveSig] int SetSignedIntegerValue(ref PROPERTYKEY key, int Value);
        [PreserveSig] int GetSignedIntegerValue(ref PROPERTYKEY key, out int Value);
        [PreserveSig] int SetUnsignedLargeIntegerValue(ref PROPERTYKEY key, ulong Value);
        [PreserveSig] int GetUnsignedLargeIntegerValue(ref PROPERTYKEY key, out ulong Value);
        [PreserveSig] int SetSignedLargeIntegerValue(ref PROPERTYKEY key, long Value);
        [PreserveSig] int GetSignedLargeIntegerValue(ref PROPERTYKEY key, out long Value);
        [PreserveSig] int SetFloatValue(ref PROPERTYKEY key, float Value);
        [PreserveSig] int GetFloatValue(ref PROPERTYKEY key, out float Value);
        [PreserveSig] int SetErrorValue(ref PROPERTYKEY key, int Value);
        [PreserveSig] int GetErrorValue(ref PROPERTYKEY key, out int Value);
        [PreserveSig] int SetKeyValue(ref PROPERTYKEY key, ref PROPERTYKEY Value);
        [PreserveSig] int GetKeyValue(ref PROPERTYKEY key, out PROPERTYKEY Value);
        [PreserveSig] int SetBoolValue(ref PROPERTYKEY key, [MarshalAs(UnmanagedType.Bool)] bool Value);
        [PreserveSig] int GetBoolValue(ref PROPERTYKEY key, [MarshalAs(UnmanagedType.Bool)] out bool Value);
        [PreserveSig] int SetIUnknownValue(ref PROPERTYKEY key, [MarshalAs(UnmanagedType.IUnknown)] object pValue);
        [PreserveSig] int GetIUnknownValue(ref PROPERTYKEY key, out IntPtr ppValue);
        [PreserveSig] int SetGuidValue(ref PROPERTYKEY key, ref Guid Value);
        [PreserveSig] int GetGuidValue(ref PROPERTYKEY key, out Guid Value);
        [PreserveSig] int SetBufferValue(ref PROPERTYKEY key, IntPtr pValue, uint cbValue);
        [PreserveSig] int GetBufferValue(ref PROPERTYKEY key, out IntPtr ppValue, out uint pcbValue);
        [PreserveSig] int SetIPortableDeviceValuesValue(ref PROPERTYKEY key, IPortableDeviceValues pValue);
        [PreserveSig] int GetIPortableDeviceValuesValue(ref PROPERTYKEY key, out IPortableDeviceValues ppValue);
        [PreserveSig] int SetIPortableDevicePropVariantCollectionValue(ref PROPERTYKEY key, IntPtr pValue);
        [PreserveSig] int GetIPortableDevicePropVariantCollectionValue(ref PROPERTYKEY key, out IntPtr ppValue);
        [PreserveSig] int SetIPortableDeviceKeyCollectionValue(ref PROPERTYKEY key, IntPtr pValue);
        [PreserveSig] int GetIPortableDeviceKeyCollectionValue(ref PROPERTYKEY key, out IntPtr ppValue);
        [PreserveSig] int SetIPortableDeviceValuesCollectionValue(ref PROPERTYKEY key, IntPtr pValue);
        [PreserveSig] int GetIPortableDeviceValuesCollectionValue(ref PROPERTYKEY key, out IntPtr ppValue);
        [PreserveSig] int RemoveValue(ref PROPERTYKEY key);
        [PreserveSig] int CopyValuesFromPropertyStore(IntPtr pStore);
        [PreserveSig] int CopyValuesToPropertyStore(IntPtr pStore);
        [PreserveSig] int Clear();
    }

    public sealed class DeviceInfo {
        public string PnpDeviceId { get; set; }
        public string FriendlyName { get; set; }
        public string Manufacturer { get; set; }
        public string Description { get; set; }
    }

    public sealed class CommandResult {
        public string PnpDeviceId { get; set; }
        public string Command { get; set; }
        public string ObjectId { get; set; }
        public int SendCommandHResult { get; set; }
        public bool HasDriverHResult { get; set; }
        public int DriverHResult { get; set; }
        public string SendCommandHResultHex { get { return "0x" + unchecked((uint)SendCommandHResult).ToString("X8"); } }
        public string DriverHResultHex { get { return "0x" + unchecked((uint)DriverHResult).ToString("X8"); } }
        public bool Succeeded { get { return SendCommandHResult >= 0 && (!HasDriverHResult || DriverHResult >= 0); } }
    }

    public static class WpdCommand {
        private static PROPERTYKEY WPD_CLIENT_NAME = new PROPERTYKEY(new Guid("204d9f0c-2292-4080-9f42-40664e70f859"), 2);
        private static PROPERTYKEY WPD_CLIENT_MAJOR_VERSION = new PROPERTYKEY(new Guid("204d9f0c-2292-4080-9f42-40664e70f859"), 3);
        private static PROPERTYKEY WPD_CLIENT_MINOR_VERSION = new PROPERTYKEY(new Guid("204d9f0c-2292-4080-9f42-40664e70f859"), 4);
        private static PROPERTYKEY WPD_CLIENT_REVISION = new PROPERTYKEY(new Guid("204d9f0c-2292-4080-9f42-40664e70f859"), 5);
        private static PROPERTYKEY WPD_CLIENT_SECURITY_QUALITY_OF_SERVICE = new PROPERTYKEY(new Guid("204d9f0c-2292-4080-9f42-40664e70f859"), 8);
        private static PROPERTYKEY WPD_CLIENT_DESIRED_ACCESS = new PROPERTYKEY(new Guid("204d9f0c-2292-4080-9f42-40664e70f859"), 9);
        private static PROPERTYKEY WPD_PROPERTY_COMMON_COMMAND_CATEGORY = new PROPERTYKEY(new Guid("f0422a9c-5dc8-4440-b5bd-5df28835658a"), 1001);
        private static PROPERTYKEY WPD_PROPERTY_COMMON_COMMAND_ID = new PROPERTYKEY(new Guid("f0422a9c-5dc8-4440-b5bd-5df28835658a"), 1002);
        private static PROPERTYKEY WPD_PROPERTY_COMMON_HRESULT = new PROPERTYKEY(new Guid("f0422a9c-5dc8-4440-b5bd-5df28835658a"), 1003);
        private static PROPERTYKEY WPD_COMMAND_COMMON_RESET_DEVICE = new PROPERTYKEY(new Guid("f0422a9c-5dc8-4440-b5bd-5df28835658a"), 2);
        private static PROPERTYKEY WPD_COMMAND_STORAGE_EJECT = new PROPERTYKEY(new Guid("d8f907a6-34cc-45fa-97fb-d007fa47ec94"), 4);
        private static PROPERTYKEY WPD_PROPERTY_STORAGE_OBJECT_ID = new PROPERTYKEY(new Guid("d8f907a6-34cc-45fa-97fb-d007fa47ec94"), 1001);
        private const uint GENERIC_READ = 0x80000000;
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint SECURITY_IMPERSONATION = 0x00020000;

        public static DeviceInfo[] ListDevices() {
            var manager = (IPortableDeviceManager)new PortableDeviceManagerClass();
            Check(manager.RefreshDeviceList(), "RefreshDeviceList");
            uint count = 0;
            int hr = manager.GetDevices(IntPtr.Zero, ref count);
            if (hr < 0) {
                Marshal.ThrowExceptionForHR(hr);
            }
            if (count == 0) {
                return new DeviceInfo[0];
            }

            IntPtr ids = Marshal.AllocCoTaskMem(IntPtr.Size * (int)count);
            try {
                for (int i = 0; i < count; i++) {
                    Marshal.WriteIntPtr(ids, i * IntPtr.Size, IntPtr.Zero);
                }
                hr = manager.GetDevices(ids, ref count);
                Check(hr, "GetDevices");
                var rows = new List<DeviceInfo>();
                for (int i = 0; i < count; i++) {
                    IntPtr idPtr = Marshal.ReadIntPtr(ids, i * IntPtr.Size);
                    if (idPtr == IntPtr.Zero) {
                        continue;
                    }
                    string id = Marshal.PtrToStringUni(idPtr);
                    Marshal.FreeCoTaskMem(idPtr);
                    Marshal.WriteIntPtr(ids, i * IntPtr.Size, IntPtr.Zero);
                    rows.Add(new DeviceInfo {
                        PnpDeviceId = id,
                        FriendlyName = ReadDeviceString(manager, id, "friendly"),
                        Manufacturer = ReadDeviceString(manager, id, "manufacturer"),
                        Description = ReadDeviceString(manager, id, "description")
                    });
                }
                return rows.ToArray();
            } finally {
                for (int i = 0; i < count; i++) {
                    IntPtr idPtr = Marshal.ReadIntPtr(ids, i * IntPtr.Size);
                    if (idPtr != IntPtr.Zero) {
                        Marshal.FreeCoTaskMem(idPtr);
                    }
                }
                Marshal.FreeCoTaskMem(ids);
                Marshal.ReleaseComObject(manager);
            }
        }

        public static CommandResult ResetDevice(string pnpDeviceId, bool readWrite) {
            return SendCommonCommand(pnpDeviceId, "ResetDevice", WPD_COMMAND_COMMON_RESET_DEVICE, readWrite, "");
        }

        public static string[] ListRootObjectIds(string pnpDeviceId, bool readWrite) {
            var device = (IPortableDevice)new PortableDeviceClass();
            IPortableDeviceValues clientInfo = CreateValues();
            IPortableDeviceContent content = null;
            IEnumPortableDeviceObjectIDs objectIds = null;
            try {
                SetClientInfo(clientInfo, readWrite);
                Check(device.Open(pnpDeviceId, clientInfo), "Open");
                Check(device.Content(out content), "Content");
                Check(content.EnumObjects(0, "DEVICE", null, out objectIds), "EnumObjects(DEVICE)");
                var rows = new List<string>();
                while (true) {
                    uint fetched = 0;
                    IntPtr buffer = Marshal.AllocCoTaskMem(IntPtr.Size);
                    try {
                        Marshal.WriteIntPtr(buffer, IntPtr.Zero);
                        int hr = objectIds.Next(1, buffer, ref fetched);
                        if (hr < 0) {
                            Marshal.ThrowExceptionForHR(hr);
                        }
                        if (fetched == 0) {
                            break;
                        }
                        IntPtr objectIdPtr = Marshal.ReadIntPtr(buffer);
                        if (objectIdPtr != IntPtr.Zero) {
                            rows.Add(Marshal.PtrToStringUni(objectIdPtr));
                            Marshal.FreeCoTaskMem(objectIdPtr);
                            Marshal.WriteIntPtr(buffer, IntPtr.Zero);
                        }
                    } finally {
                        IntPtr objectIdPtr = Marshal.ReadIntPtr(buffer);
                        if (objectIdPtr != IntPtr.Zero) {
                            Marshal.FreeCoTaskMem(objectIdPtr);
                        }
                        Marshal.FreeCoTaskMem(buffer);
                    }
                }
                return rows.ToArray();
            } finally {
                ReleaseIfCom(objectIds);
                ReleaseIfCom(content);
                try {
                    device.Close();
                } catch {
                }
                ReleaseIfCom(clientInfo);
                ReleaseIfCom(device);
            }
        }

        public static CommandResult StorageEject(string pnpDeviceId, string objectId, bool readWrite) {
            if (String.IsNullOrWhiteSpace(objectId)) {
                throw new ArgumentException("StorageEject requires an object id.", "objectId");
            }
            return SendCommonCommand(pnpDeviceId, "StorageEject", WPD_COMMAND_STORAGE_EJECT, readWrite, objectId);
        }

        private static CommandResult SendCommonCommand(string pnpDeviceId, string commandName, PROPERTYKEY command, bool readWrite, string objectId) {
            var device = (IPortableDevice)new PortableDeviceClass();
            IPortableDeviceValues clientInfo = CreateValues();
            IPortableDeviceValues parameters = CreateValues();
            IPortableDeviceValues results = null;
            try {
                SetClientInfo(clientInfo, readWrite);
                Check(device.Open(pnpDeviceId, clientInfo), "Open");
                Guid category = command.fmtid;
                Check(parameters.SetGuidValue(ref WPD_PROPERTY_COMMON_COMMAND_CATEGORY, ref category), "SetGuidValue(command category)");
                Check(parameters.SetUnsignedIntegerValue(ref WPD_PROPERTY_COMMON_COMMAND_ID, command.pid), "SetUnsignedIntegerValue(command id)");
                if (!String.IsNullOrWhiteSpace(objectId)) {
                    Check(parameters.SetStringValue(ref WPD_PROPERTY_STORAGE_OBJECT_ID, objectId), "SetStringValue(storage object id)");
                }

                int sendHr = device.SendCommand(0, parameters, out results);
                int driverHr = 0;
                bool hasDriverHr = false;
                if (results != null) {
                    int getHr = results.GetErrorValue(ref WPD_PROPERTY_COMMON_HRESULT, out driverHr);
                    hasDriverHr = getHr >= 0;
                }
                return new CommandResult {
                    PnpDeviceId = pnpDeviceId,
                    Command = commandName,
                    ObjectId = objectId,
                    SendCommandHResult = sendHr,
                    HasDriverHResult = hasDriverHr,
                    DriverHResult = driverHr
                };
            } finally {
                try {
                    device.Close();
                } catch {
                }
                ReleaseIfCom(results);
                ReleaseIfCom(parameters);
                ReleaseIfCom(clientInfo);
                ReleaseIfCom(device);
            }
        }

        private static IPortableDeviceValues CreateValues() {
            return (IPortableDeviceValues)new PortableDeviceValuesClass();
        }

        private static void SetClientInfo(IPortableDeviceValues values, bool readWrite) {
            Check(values.SetStringValue(ref WPD_CLIENT_NAME, "Garmin PRG Sender WPD Trigger"), "SetStringValue(client name)");
            Check(values.SetUnsignedIntegerValue(ref WPD_CLIENT_MAJOR_VERSION, 1), "SetUnsignedIntegerValue(client major)");
            Check(values.SetUnsignedIntegerValue(ref WPD_CLIENT_MINOR_VERSION, 0), "SetUnsignedIntegerValue(client minor)");
            Check(values.SetUnsignedIntegerValue(ref WPD_CLIENT_REVISION, 0), "SetUnsignedIntegerValue(client revision)");
            Check(values.SetUnsignedIntegerValue(ref WPD_CLIENT_SECURITY_QUALITY_OF_SERVICE, SECURITY_IMPERSONATION), "SetUnsignedIntegerValue(client SQOS)");
            uint desiredAccess = readWrite ? (GENERIC_READ | GENERIC_WRITE) : GENERIC_READ;
            Check(values.SetUnsignedIntegerValue(ref WPD_CLIENT_DESIRED_ACCESS, desiredAccess), "SetUnsignedIntegerValue(client access)");
        }

        private static string ReadDeviceString(IPortableDeviceManager manager, string id, string field) {
            uint chars = 0;
            int hr;
            if (field == "manufacturer") {
                hr = manager.GetDeviceManufacturer(id, IntPtr.Zero, ref chars);
            } else if (field == "description") {
                hr = manager.GetDeviceDescription(id, IntPtr.Zero, ref chars);
            } else {
                hr = manager.GetDeviceFriendlyName(id, IntPtr.Zero, ref chars);
            }
            if (chars == 0) {
                return "";
            }
            IntPtr buffer = Marshal.AllocHGlobal((int)chars * 2);
            try {
                if (field == "manufacturer") {
                    hr = manager.GetDeviceManufacturer(id, buffer, ref chars);
                } else if (field == "description") {
                    hr = manager.GetDeviceDescription(id, buffer, ref chars);
                } else {
                    hr = manager.GetDeviceFriendlyName(id, buffer, ref chars);
                }
                if (hr < 0) {
                    return "";
                }
                return Marshal.PtrToStringUni(buffer) ?? "";
            } finally {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private static void Check(int hr, string operation) {
            if (hr < 0) {
                throw new InvalidOperationException(operation + " failed: " + ToHex(hr), Marshal.GetExceptionForHR(hr));
            }
        }

        private static string ToHex(int hr) {
            return "0x" + unchecked((uint)hr).ToString("X8");
        }

        private static void ReleaseIfCom(object value) {
            if (value != null && Marshal.IsComObject(value)) {
                Marshal.ReleaseComObject(value);
            }
        }
    }
}
"@

if (-not ("GarminPrgSender.Wpd.WpdCommand" -as [type])) {
    Add-Type -Language CSharp -TypeDefinition $source
}

$devices = @([GarminPrgSender.Wpd.WpdCommand]::ListDevices())
if ($Command -eq "List") {
    $devices | ForEach-Object {
        [pscustomobject]@{
            FriendlyName = $_.FriendlyName
            Manufacturer = $_.Manufacturer
            Description = $_.Description
            PnpDeviceId = $_.PnpDeviceId
        }
    }
    return
}

$matching = @($devices | Where-Object {
    $_.FriendlyName -match $DevicePattern -or
    $_.Description -match $DevicePattern -or
    $_.Manufacturer -match $DevicePattern -or
    $_.PnpDeviceId -match $DevicePattern
})
if ($matching.Count -lt 1) {
    throw "No WPD device matched pattern '$DevicePattern'."
}
if ($matching.Count -gt 1) {
    Write-Warning "Multiple WPD devices matched '$DevicePattern'; using first match '$($matching[0].FriendlyName)'."
}

$readWrite = $Access -eq "ReadWrite"
if ($Command -eq "ListRootObjects") {
    $objectIds = @([GarminPrgSender.Wpd.WpdCommand]::ListRootObjectIds($matching[0].PnpDeviceId, $readWrite))
    foreach ($id in $objectIds) {
        [pscustomobject]@{
            FriendlyName = $matching[0].FriendlyName
            PnpDeviceId = $matching[0].PnpDeviceId
            Access = $Access
            ObjectId = $id
        }
    }
    return
}

$results = @()
if ($Command -eq "ResetDevice") {
    $results += [GarminPrgSender.Wpd.WpdCommand]::ResetDevice($matching[0].PnpDeviceId, $readWrite)
} elseif ($Command -eq "StorageEject") {
    $objectIds = @()
    if (-not [string]::IsNullOrWhiteSpace($ObjectId)) {
        $objectIds += $ObjectId
    } else {
        $objectIds = @([GarminPrgSender.Wpd.WpdCommand]::ListRootObjectIds($matching[0].PnpDeviceId, $readWrite))
    }
    if ($objectIds.Count -lt 1) {
        throw "No root WPD object ids were available for StorageEject."
    }
    foreach ($id in $objectIds) {
        $results += [GarminPrgSender.Wpd.WpdCommand]::StorageEject($matching[0].PnpDeviceId, $id, $readWrite)
        if ($results[-1].Succeeded) {
            break
        }
    }
}

$anySucceeded = $false
foreach ($result in $results) {
    $row = [pscustomObject]@{
        Command = $result.Command
        FriendlyName = $matching[0].FriendlyName
        PnpDeviceId = $result.PnpDeviceId
        Access = $Access
        ObjectId = $result.ObjectId
        SendCommandHResult = $result.SendCommandHResultHex
        HasDriverHResult = $result.HasDriverHResult
        DriverHResult = $result.DriverHResultHex
        Succeeded = $result.Succeeded
    }
    $row
    $anySucceeded = $anySucceeded -or $result.Succeeded
}
if (-not $anySucceeded) {
    exit 1
}
