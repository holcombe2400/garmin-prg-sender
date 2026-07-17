# Track 2: BLE Connect IQ App-Management Path

## Current conclusion

The proven USB/MTP path installs a PRG because the watch indexes `GARMIN\Apps` after USB disconnect. The BLE GFDI PRG upload path transfers bytes, but the fenix 6 Pro does not advertise PRG `255/17` as a supported GFDI file type and does not immediately register the app afterward.

The important update is that Garmin Connect Mobile can complete the missing registration pass later. `BLE Probe 002604` was uploaded over BLE, did not immediately appear as installed, then installed after the watch was paired/reconnected to Garmin Connect on iPhone. That makes the practical no-cable workflow:

1. Stage PRG bytes over BLE from this sender.
2. Have the user pair/open Garmin Connect on their phone and sync the watch.
3. Let Garmin Connect trigger Connect IQ registration.

Track 2 is therefore still about Garmin's private Connect IQ app-management/download flow, but the immediate product path is now "BLE stage plus Garmin Connect phone sync" rather than "BLE-only self-registration."

## USB registry artifact

The proven cable path produces a PC-readable registry artifact at `GARMIN\Apps\OUT` after the watch disconnects and indexes. `scripts\Parse-GarminAppsOut.py` decodes it as a protobuf-style wrapper containing repeated installed-app records:

- field `1`: 16-byte store/app UUID
- field `2`: app type (`1` watch app, `4` data field, `7` audio provider, etc.)
- field `3`: display name
- field `4`: disabled-ish flag observed in installed-apps protobuf too
- field `5`: native/activity id when present
- field `6`: PRG filename stem
- field `7`: PRG size for sideloaded apps, id/version-like value for some store/system entries
- field `8`: `4294967295` on some sideloaded PRGs
- field `9`: favorite/pinned-ish flag observed in installed-apps protobuf too

Latest fenix 6 Pro USB registry check confirmed:

```text
073  Garmon     GarmonInstallTest_fenix6pro_43KB  size_or_id=43148  type=1  uuid=d036558e537b4aa3aac9c23c7ba27344
074  USB Probe  UsbProbe_fenix6pro                size_or_id=96668  type=1  uuid=b16b00b5f6a64e5aa029d8d8f2b7c401
```

This makes the BLE failure mode more specific: BLE raw upload is not causing the watch to add this installed-app record. The missing no-cable step is therefore an app-management/index transaction, not merely moving bytes into a PRG-shaped file.

The project now includes `Collect-GarminAppsSnapshotMtp.ps1`, `Compare-GarminAppsSnapshots.py`, and `Run-GarminUsbIndexExperiment.ps1` so each future cable install can produce a before/after file diff plus decoded `OUT` registry diff. That is the evidence source for deciding which USB-created artifacts, if any, are feasible to reproduce through Garmin's BLE protobuf services.

## Gadgetbridge evidence

The current Gadgetbridge Garmin source does not expose a complete CIQ PRG installer over BLE.

- `GarminFitFileInstallHandler` validates FIT files and supports course/workout-style installs.
- Gadgetbridge's GFDI `FileType` enum does not define PRG `255/17`.
- `gdi_smart_proto.proto` documents private Garmin `Smart` field numbers, including:
  - `2` `CONNECT_IQ_HTTP_SERVICE`
  - `3` `CONNECT_IQ_INSTALLED_APPS_SERVICE`
  - `4` `CONNECT_IQ_APP_SETTINGS_SERVICE`
  - `31` `GENERIC_ITEM_TRANSFER_SERVICE`
- Gadgetbridge implements the public HTTP proxy/data-transfer parts:
  - field `2` HTTP raw requests from watch to phone
  - field `7` data transfer chunks when the watch pulls response bodies from the phone
- Gadgetbridge does not define a public install-app protobuf command we can copy.

## New tool added

The sender now has a safe protobuf listener:

```powershell
.\.runtime\Scripts\python.exe -B .\send_prg.py --protobuf-listen --address "F0:99:19:75:41:3E" --winrt-services cached --connect-timeout 75 --timeout 5 --listen-seconds 120 --listen-phone-events --listen-http-unknown --packet-log logs\track2-protobuf-listen.jsonl --packet-log-bytes 512 --debug
```

What it does:

- connects to Garmin GFDI over BLE
- sends optional safe phone-presence events (`HOST_DID_ENTER_FOREGROUND`, `SYNC_READY`)
- ACKs watch-originated GFDI/protobuf requests
- decodes Garmin `Smart` protobuf field numbers
- redacts token-like HTTP headers/query values in summaries
- optionally replies to HTTP `RawRequest` messages with harmless `UNKNOWN_STATUS`

## First live capture

With the fenix 6 Pro at `F0:99:19:75:41:3E`, a 30-second listener run produced:

- `DEVICE_INFORMATION`
- repeated `NOTIFICATION_SUBSCRIPTION`
- one `CONFIGURATION`
- repeated `PROTOBUF_REQUEST` messages on `Smart` field `21` (`LIVE_TRACK_SERVICE`)

It did not produce:

- field `2` `CONNECT_IQ_HTTP_SERVICE`
- field `3` `CONNECT_IQ_INSTALLED_APPS_SERVICE`, except when we explicitly query it
- field `4` `CONNECT_IQ_APP_SETTINGS_SERVICE`
- field `31` `GENERIC_ITEM_TRANSFER_SERVICE`

So the watch does not automatically start a Connect IQ install/download flow just because a phone-like BLE peer connects.

## CIQ provocation capture

A later 180-second capture while prompting phone-presence events and interacting with the watch produced the same pattern:

- `5000` response/ACK packets: 151
- `5024` `DEVICE_INFORMATION`: 1
- `5030` `SYSTEM_EVENT`: 2 transmitted
- `5036` `NOTIFICATION_SUBSCRIPTION`: 138
- `5043` `PROTOBUF_REQUEST`: 9
- `5050` `CONFIGURATION`: 1

All 9 protobuf requests decoded as `Smart` field `21` (`LIVE_TRACK_SERVICE`). No `CONNECT_IQ_HTTP_SERVICE`, `CONNECT_IQ_APP_SETTINGS_SERVICE`, `CONNECT_IQ_INSTALLED_APPS_SERVICE`, or `GENERIC_ITEM_TRANSFER_SERVICE` fields appeared in this capture.

Capture log:

```text
C:\Users\holco\Documents\Codex\2026-07-14\lo\work\track2-ciq-provocation.jsonl
```

## Fresh BLE trigger experiment

On 2026-07-17, fresh tiny CIQ probes were generated per BLE trigger so registration could be checked by a unique UUID/name instead of an already-installed app.

Preflight over BLE:

- `SUPPORTED_FILE_TYPES_REQUEST` succeeded.
- The watch advertised 14 file types.
- PRG `255/17` was not advertised.

Observed upload behavior:

- Baseline `SYNC_COMPLETE`: PRG bytes fully ACKed, installed-apps query succeeded, probe was not registered.
- `NEW_DOWNLOAD_AVAILABLE` then `SYNC_COMPLETE`: PRG bytes fully ACKed, installed-apps query succeeded, probe was not registered.
- `SYNCHRONIZATION 5037` type `0`, `1`, and `2`, with 4-byte and 8-byte install bitmasks: watch returned `UNSUPPORTED`.
- `SET_FILE_FLAG ARCHIVE` using the created file index: watch returned `FlagsStatus.ERROR`.
- `SET_FILE_FLAG ARCHIVE` using the returned file number: watch applied the archive flag, then `SYNC_COMPLETE` and installed-apps query succeeded, but the probe was not registered.

Representative successful-but-not-registered logs:

```text
logs\fresh-ble-experiments\ble-experiment-20260717-002350
logs\fresh-ble-experiments\ble-experiment-20260717-002526
logs\fresh-ble-experiments\ble-experiment-20260717-003306
```

The cleanest negative case is `archive-created-file-number`:

```text
Upload completed; PRG bytes acknowledged (file_index=65520, file_number=65519).
Post-upload trigger: SET_FILE_FLAG ARCHIVE sent file_number=65519 response_file_identifier=65518 flags=0x10.
Installed apps query succeeded: 122 apps, available_space=10698299, available_slots=17
Transfer succeeded but app is not registered
```

Initial conclusion from this ladder: the missing immediate no-cable mechanism is not a simple GFDI system event, synchronization bitmask, or file archive flag after raw PRG upload. Later evidence refined this: Garmin Connect Mobile can notice or process a BLE-staged PRG and complete registration during phone sync.

## Garmin Connect Mobile completed a BLE-staged install

After the BLE ladder, Bluetooth pairing to the iPhone/Garmin Connect app was restored. The watch displayed:

```text
Garmin Connect IQ
BLE Probe 002604 has been installed to your device.
```

That probe maps to:

```text
logs\fresh-ble-experiments\ble-experiment-20260717-002526\probes\CiqProbe_20260717-002604
App name: BLE Probe 002604
UUID: cea3459e-81a9-411b-961c-4b9b67e19649
PRG size: 90108
Packet log: logs\fresh-ble-experiments\ble-experiment-20260717-002526\runs\sync-install-type0-CiqProbe_20260717-002604_fenix6pro-packets.jsonl
```

Packet summary:

```text
Data packets sent: 249
Data statuses received: 249
Last acknowledged offset: 90108
Last status: UNSUPPORTED
Last error: UNSUPPORTED
```

Interpretation:

- The PRG bytes were fully staged over BLE.
- The final `UNSUPPORTED` came from the experimental post-upload trigger, not the byte transfer.
- Immediate installed-app verification was absent or negative during the BLE experiment.
- Garmin Connect Mobile later triggered the registration/install notice.

The sender now has `--stage-for-garmin-connect` and the GUI has `Stage for Phone Sync` for this workflow. This mode logs the packet exchange, writes a next-steps text file, and treats full byte acknowledgement as staged success instead of requiring immediate installed-app registration.

## Confirmed phone-sync registration proof

On 2026-07-18, the complete workflow succeeded with a fresh probe:

```text
App name: PhoneSync Probe 003151
App UUID generated by probe: b15ac123-e183-4fac-a4a8-a485f16a113b
PRG size: 90140 bytes
Packet log: logs\phone-sync-stage-experiments\phone-sync-stage-20260718-003150\run\CiqProbe_20260718-003151_fenix6pro-stage-packets.jsonl
```

BLE staging result:

```text
Uploaded 90140/90140 bytes (100%)
Upload completed; PRG bytes acknowledged (file_index=65520, file_number=65519).
PRG staged for Garmin Connect phone sync
```

The experimental `SYNCHRONIZATION type 0 INSTALL` trigger still returned `UNSUPPORTED`, so the trigger is not confirmed as the install mechanism. The important fact is that the watch acknowledged every PRG byte over BLE.

After Garmin Connect Mobile was reconnected and synced, BLE installed-app verification reported:

```text
Installed apps query succeeded: 119 apps, available_slots=20
PhoneSync Probe 003151  WATCH_APP  23c15ab1-83e1-ac4f-a4a8-a485f16a113b  file=G7HE3426  size=90140  version=0
PhoneSync Probe 003151 is registered
```

This confirms the practical no-cable-recipient workflow:

1. Temporarily prevent the phone from holding the watch BLE connection.
2. Stage the PRG from Windows over Garmin GFDI BLE.
3. Re-enable phone Bluetooth so Garmin Connect Mobile can reconnect.
4. Garmin Connect Mobile completes Connect IQ registration. Opening Garmin Connect or forcing sync is useful as a fallback, but the clean no-trigger proof did not require opening the app.

A second proof removed the experimental trigger entirely:

```text
App name: PhoneSync Probe 004824
App UUID generated by probe: 76a2d77d-c072-411c-bbf1-88661398dc6a
Post-upload trigger: none
Packet log: logs\phone-sync-stage-experiments\phone-sync-stage-20260718-004819\run\CiqProbe_20260718-004824_fenix6pro-stage-packets.jsonl
```

BLE staging result:

```text
Uploaded 90140/90140 bytes (100%)
Upload completed; PRG bytes acknowledged (file_index=65520, file_number=65519).
Post-upload trigger: none (SYNC_COMPLETE baseline)
Last error: none
Sync-complete sent: yes
```

After simply turning iPhone Bluetooth back on, without opening Garmin Connect, BLE installed-app verification reported:

```text
Installed apps query succeeded: 120 apps, available_slots=19
PhoneSync Probe 004824  WATCH_APP  76a2d77d-c072-411c-bbf1-88661398dc6a  file=G7HE4956  size=90140  version=0
PhoneSync Probe 004824 is registered
```

This proves the unsupported `SYNCHRONIZATION type 0 INSTALL` trigger is unnecessary for the tested workflow. Plain BLE PRG staging followed by phone Bluetooth/Garmin Connect reconnect is enough on this fenix 6 Pro firmware.

Practical constraints observed:

- Windows needed `--winrt-services uncached` for reliable Garmin GFDI registration.
- The watch needed available Connect IQ app slots. At `available_slots=0`, `CREATE_FILE` returned `NO_SLOTS`.
- Once old probe apps were removed, `available_slots=21` and staging succeeded.

Next repeat tests:

- Stage another fresh probe with no extra trigger and confirm the exact probe name installs after phone Bluetooth reconnect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-PhoneSyncStageExperiment.ps1 -Address "F0:99:19:75:41:3E" -WinrtServices uncached -PostUploadTrigger none
```

- Add `-WaitForPhoneSync` when you want the script to pause while the phone reconnects, then run the installed-app query for the generated UUID/name.

## Garmin Express IQ Store experiment

Garmin Express was used over USB to install the free store app `T-Rex dino game from Chrome offline mode.`. The experiment folder is:

```text
logs\garmin-express-iq-experiments\express-iq-20260717-004420
```

Watch registry result:

```text
Registry:
  before=122 after=123
  added:
    077  GarminTrexGame  file=12BE69AC  size_or_id=60933  type=1  uuid=c3f58c638e4649cd9baafb0196da0165
```

Garmin Express local metadata added the same app:

```text
AppName=GarminTrexGame
StoreId=c3f58c63-8e46-49cd-9baa-fb0196da0165
AppId=df081c36-7a2e-4e83-9fb3-a423a343e842
AppType=watch-app
Version=27
FileName=12BE69AC.PRG
```

Garmin Express log evidence showed the install transaction:

```text
Installing Store IQ item T-Rex dino game from Chrome offline mode.
Downloading file from https://services.garmin.com/appsLibraryBusinessServices_v0/rest/apps/c3f58c63-8e46-49cd-9baa-fb0196da0165/versions/71b9966b-5ac8-4f00-937e-325a14638feb/binaries/fenix6p?... to ...\Sync\Download\IQWatchApps\oqevgk5k.0hv
File to transfer ...\Sync\Download\IQWatchApps\oqevgk5k.0hv -> GARMIN/APPS/MEDIA\12BE69AC.PRG (dataType IQWatchApps)
```

The temp download was gone by the time the watch was reconnected and indexed. The permanent PC-side evidence was `IQAppInfo.xml`, `device_data_store.xml`, Garmin Express logs, and the watch `OUT` registry row. The next USB/Express experiment should either capture the temp `Sync\Download\IQWatchApps` file while Express is syncing or replay the discovered app-library download endpoint in a controlled way.

## Garmin Express staged-vs-indexed proof

A second Garmin Express install used `Classic Tetris Game`.

Garmin Express staged the app before the watch was unplugged:

```text
Installing Store IQ item Classic Tetris Game
Downloading file from https://services.garmin.com/appsLibraryBusinessServices_v0/rest/apps/e214b907-1730-42a6-ac0b-ce1fb2eb68c7/versions/4803fc9a-3534-4d55-a4cd-ebd560e92daf/binaries/fenix6p?... to ...\Sync\Download\IQWatchApps\25qi0ex1.4c3
File to transfer ...\Sync\Download\IQWatchApps\25qi0ex1.4c3 -> GARMIN/APPS/MEDIA\1B66586E.PRG (dataType IQWatchApps)
```

Before unplugging the watch, the PC-side `IQAppInfo.xml` already contained:

```text
AppId=e214b907-1730-42a6-ac0b-ce1fb2eb68c7
FileName=1B66586E
FileSize=46712
Name=Classic Tetris Game
Version=68
```

But the watch-side `GARMIN\Apps\OUT` registry had only 123 records and did not include `e214b907...` or `1B66586E`.

After physical USB unplug, waiting for the watch loading/indexing screen, and reconnecting, `OUT` had 124 records and included:

```text
079  Tetris  file=1B66586E  size_or_id=47237  type=1  uuid=e214b907173042a6ac0bce1fb2eb68c7
```

This proves the app can be staged before disconnect, but Connect IQ registration still depends on a watch-side index/registration pass that runs after USB disconnect. The missing no-cable mechanism is therefore either:

- an official BLE app-management transaction that both transfers/stages the app and requests this index operation; or
- a private event that makes the watch run the same registration pass without a physical USB disconnect.

New helper scripts:

```text
scripts\Start-GarminExpressIqDownloadCapture.ps1
scripts\Extract-GarminExpressIqInstalls.ps1
```

The capture starter uses an encoded PowerShell launch so paths with spaces do not break the watcher. The extractor creates redacted Garmin Express install summaries from `Express.log` and `IQAppInfo.xml`.

## Soft USB/WPD restart trigger result

Windows does not expose a Shell `Eject`/`Disconnect` verb for the fenix 6 Pro MTP object. The available Shell verbs are only Open, pin/shortcut, and Properties.

A no-stage PnP restart test was run against the WPD device:

```text
USB\VID_091E&PID_4CDA\0000C5DC0F5A
Device Description: fenix 6 Pro
Class Name: WPD
Driver: wpdmtp.inf
```

Without a staged app, `pnputil /restart-device` returned success and the visible app registry stayed unchanged:

```text
Registry:
  before=124 after=124
  added=0 removed=0 changed=0 unchanged=124
```

A fresh probe was then generated and staged over MTP:

```text
App name: SoftDisc Probe 011629
App id: 32a67194-7226-4515-9318-91aea274fd01
File: CiqProbe_20260717-011629_fenix6pro
Size: 90172
```

Before the soft restart, the MTP snapshot showed the PRG file was present but the `OUT` registry still had 124 records and did not include the probe. Then `pnputil /restart-device` was sent to the Garmin WPD device. Afterward, Windows no longer exposed the watch as MTP; the USB stack re-enumerated it as:

```text
USB\VID_091E&PID_0003\6&3b1c401&0&1
Device Description: Garmin USB GPS
Class Name: GARMIN Devices
Driver: grmnusb / oem56.inf
```

Because MTP did not return, final verification used the BLE installed-apps protobuf service. BLE reported:

```text
Installed apps query succeeded: 125 apps, available_space=10499957, available_slots=14
SoftDisc Probe 011629 is registered
```

This is the first positive non-physical-unplug registration trigger found. It proves that a Windows-side restart of the Garmin WPD/MTP USB device can make the watch run the Connect IQ registration/index path for a staged PRG.

Important limits:

- This is not cable-free yet; it still depends on USB/MTP staging and Windows PnP.
- It does not mimic a clean physical unplug. The watch/driver stack switched from MTP (`PID_4CDA`) to Garmin USB GPS mode (`PID_0003`), and MTP did not come back automatically.
- Attempting to restart the resulting `Garmin USB GPS` device (`USB\VID_091E&PID_0003\...`) returned `Access is denied`; normal MTP recovery still requires a physical unplug/replug.
- The result still narrows the missing BLE mechanism: successful registration appears tied to a device-mode/session transition, not to file bytes alone and not to the earlier GFDI `SYNC_COMPLETE`/archive/sync-install messages.

Follow-up BLE hypothesis: because the positive USB/PnP result looks like a session/device transition, the sender now exposes a `device-disconnect` post-upload trigger. It sends `SYNC_COMPLETE`, then Garmin's known GFDI `SYSTEM_EVENT DEVICE_DISCONNECT` (`11`), tolerating a missing ACK because a disconnect-like event may close or disturb the BLE session. This is the closest safe BLE-side equivalent to "file staged, device session ends, watch indexes" that is visible in the Gadgetbridge system-event enum.

The focused `device-disconnect` run was negative:

```text
logs\fresh-ble-experiments\ble-experiment-20260717-072334
App name: BLE DeviceDisc 072335
App id: 3E2DE413B46142A19DC0E00CBD89DBD9
PRG size: 90124
```

Packet-log summary:

```text
Rows: 568 (270 tx, 298 rx)
Parse errors: 0
Data packets sent: 249
Data statuses received: 249
Last acknowledged offset: 90124
Last status: ACK
Sync-complete sent: yes
```

Verification result:

```text
Installed apps query succeeded: 125 apps, available_space=10499957, available_slots=14
Transfer succeeded but app is not registered
```

Delayed follow-up verification using the exact probe UUID/name also returned:

```text
BLE DeviceDisc 072335 is not registered
```

So `SYSTEM_EVENT DEVICE_DISCONNECT` is not the missing BLE-only index trigger on this firmware. The positive USB/PnP registration result still points to a deeper USB storage/device-mode transition or Garmin's private Connect IQ app-management flow, not a simple GFDI system event.

## WPD reset/eject command result

Microsoft's WPD API exposes two explicit commands that looked relevant to the USB trigger:

- `WPD_COMMAND_COMMON_RESET_DEVICE`
- `WPD_COMMAND_STORAGE_EJECT`

The project now includes:

```text
scripts\Invoke-WpdDeviceCommand.ps1
```

It uses `IPortableDevice::SendCommand` directly. It can list the fenix WPD device and enumerate the root storage object:

```text
FriendlyName: fenix 6 Pro
PnpDeviceId: \\?\usb#vid_091e&pid_4cda#0000c5dc0f5a#{6ac27878-a6fa-4155-ba85-f98f491d4f33}
Root storage object id: s20001
```

A fresh probe was staged over MTP:

```text
logs\soft-disconnect-index-experiments\soft-disconnect-20260717-081633
App name: SoftDisc Probe 081635
App id: 4e89ede8-c04b-44b9-920e-07505b3c363b
File: CiqProbe_20260717-081635_fenix6pro
Size: 90172
```

Before any trigger, the staged file was present but the `OUT` registry did not change:

```text
Registry:
  before=125 after=125
  added=0 removed=0 changed=0 unchanged=125
Target:
  before_matches=0 after_matches=0
```

`WPD_COMMAND_COMMON_RESET_DEVICE` result:

```text
ReadOnly open: SendCommandHResult=0x80070005
ReadWrite open: SendCommandHResult=0x00000000 DriverHResult=0x80004001
```

`WPD_COMMAND_STORAGE_EJECT` against `s20001` result:

```text
SendCommandHResult=0x00000000 DriverHResult=0x80004001
```

`0x80004001` is `E_NOTIMPL`, so Garmin's WPD/MTP driver exposes the device and storage object but does not implement the standard WPD reset/eject commands as usable indexing triggers. This makes the earlier successful `pnputil /restart-device` result more specific: it worked below WPD, at the Windows PnP/USB device-restart level, not through ordinary WPD commands.

After the failed WPD reset/eject attempts, the watch was physically unplugged and replugged. The same staged PRG then registered through the normal USB indexing path:

```text
Registry capture: logs\usb-registry\registry-20260717-083254
Records decoded: 126
Transfer succeeded and app is registered in USB/MTP registry
  081  SoftDisc Probe 081635  file=CiqProbe_20260717-081635_fenix6pro  size_or_id=90172  type=1  uuid=4e89ede8c04b44b9920e07505b3c363b
```

This is the cleanest boundary proof so far:

- The exact same PRG file was copied to `GARMIN\Apps`.
- The WPD-visible staged state did not update `GARMIN\Apps\OUT`.
- WPD `ResetDevice` and `StorageEject` did not trigger indexing.
- Physical USB disconnect did trigger indexing and registration.

So the registration trigger is very likely below WPD/MTP command semantics: either the watch firmware reacts to a real USB cable/session loss, or Windows' lower-level PnP/USB stack causes a reset/disconnect sequence that WPD cannot request through its standard driver commands.

## Configuration Manager eject test

A cleaner lower-level Windows trigger was added to `Run-GarminSoftDisconnectIndexExperiment.ps1`:

```text
-TryPnpEject
```

This calls `CM_Request_Device_EjectW` through `cfgmgr32.dll`, below WPD and without using `pnputil /restart-device`.

Fresh probe staged:

```text
logs\soft-disconnect-index-experiments\soft-disconnect-20260717-083642
App name: SoftDisc Probe 083644
App id: 463af976-1340-4bdb-b980-d9a3e6938c98
File: CiqProbe_20260717-083644_fenix6pro
Size: 90172
```

Pre-trigger proof:

```text
Registry:
  before=126 after=126
  added=0 removed=0 changed=0 unchanged=126
Target:
  before_matches=0 after_matches=0
```

The Configuration Manager eject call succeeded:

```text
InstanceId: USB\VID_091E&PID_4CDA\0000C5DC0F5A
CM_Locate_DevNode=0x00000000
CM_Request_Device_Eject=0x00000000
Veto=Ok
Succeeded=True
```

Afterward, MTP did not return automatically. Windows showed:

```text
Unknown GARMIN Devices Garmin USB GPS USB\VID_091E&PID_0003\...
Error   WPD            fenix 6 Pro    USB\VID_091E&PID_4CDA\0000C5DC0F5A
```

BLE installed-app verification failed twice while the watch was in this ejected USB state, and non-admin `pnputil /scan-devices` returned `Access is denied`, so the registration result is not yet confirmed. The critical observation needed for this experiment is whether the watch displayed its normal loading/indexing screen immediately after `CM_Request_Device_Eject`. If yes, this may be a cleaner software-only USB disconnect trigger than `pnputil /restart-device`; if not, it may only eject Windows' WPD view without causing the watch firmware's CIQ index pass.

After a later physical unplug/replug, MTP returned normally and the same staged probe was present in `OUT`:

```text
Registry capture: logs\usb-registry\registry-20260717-085512
Records decoded: 127
Transfer succeeded and app is registered in USB/MTP registry
  082  SoftDisc Probe 083644  file=CiqProbe_20260717-083644_fenix6pro  size_or_id=90172  type=1  uuid=463af97613404bdbb980d9a3e6938c98
```

This confirms the PRG staged before `CM_Request_Device_Eject` did ultimately install. It does not yet prove that `CM_Request_Device_Eject` alone triggered indexing, because the only successful registry observation happened after a physical unplug/replug, which is already known to run the index pass. The remaining differentiator is user-visible watch behavior during the CM eject: if the watch shows the loading/indexing screen immediately after the software eject, CM eject is likely enough; if it does not, CM eject probably only removes Windows' WPD session and the physical unplug remains the actual firmware trigger.

A second observation run was started while the watch was connected and the user was asked to watch the fenix screen:

```text
logs\soft-disconnect-index-experiments\soft-disconnect-20260717-114856
App name: SoftDisc Probe 114857
App id: c290cca7-2a8d-4f67-b596-7281e30ee538
File: CiqProbe_20260717-114857_fenix6pro
Size: 90172
```

Pre-trigger proof:

```text
Registry:
  before=127 after=127
  added=0 removed=0 changed=0 unchanged=127
Target:
  before_matches=0 after_matches=0
```

The Configuration Manager eject again succeeded:

```text
CM_Locate_DevNode=0x00000000
CM_Request_Device_Eject=0x00000000
Veto=Ok
Succeeded=True
```

Post-trigger Windows state:

```text
Unknown GARMIN Devices Garmin USB GPS USB\VID_091E&PID_0003\...
Error   WPD            fenix 6 Pro    USB\VID_091E&PID_4CDA\0000C5DC0F5A
```

MTP did not return automatically and BLE installed-app verification timed out again. The remaining missing observation is whether the watch displayed the indexing/loading screen immediately after the CM eject.

User observation from this run: the watch screen did not change after `CM_Request_Device_Eject`.

Conclusion: `CM_Request_Device_Eject` is not sufficient as a Connect IQ registration trigger on this watch. It cleanly removes/ejects Windows' WPD/MTP view, but it does not make the fenix firmware enter the visible loading/indexing state that physical USB unplug causes. The useful software trigger remains the lower-level `pnputil /restart-device` path, which is rougher but did cause a registration pass in the earlier positive test. The remaining no-cable target is still Garmin's private Connect IQ app-management/download flow rather than ordinary WPD eject semantics.

## Physical unplug trigger capture

To understand the true physical unplug boundary more precisely, the project now includes:

```text
scripts\Run-GarminPhysicalUnplugTriggerCapture.ps1
```

It is a two-phase capture:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminPhysicalUnplugTriggerCapture.ps1 -Phase Before
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminPhysicalUnplugTriggerCapture.ps1 -Phase After -ExperimentDir ".\logs\physical-unplug-trigger-captures\physical-unplug-YYYYMMDD-HHMMSS"
```

The before phase generates a fresh probe, records PnP/WPD state, collects Windows USB/PnP event-log rows, takes a `GARMIN\Apps` snapshot, stages the PRG over MTP, and takes a staged snapshot. The after phase is run after the human physical unplug/replug; it captures the same state again and compares `OUT`.

This should tell us more than "the registry changed": it gives a timeline of what Windows saw around the physical unplug, while the watch-screen observation tells us when the firmware entered its index/loading path. If the event-log/device-state pattern matches the earlier successful `pnputil /restart-device` run but not CM eject, the next software target is a lower-level USB device reset/restart that reproduces that exact pattern without relying on WPD.

First capture:

```text
logs\physical-unplug-trigger-captures\physical-unplug-20260717-120908
App name: PhysicalUnplug Probe 120910
App id: 3134dc0a-8db0-4016-a380-e2c9476acd8a
File: CiqProbe_20260717-120910_fenix6pro
```

Registry result after physical unplug/replug:

```text
Registry:
  before=128 after=129
  added=1 removed=0 changed=0 unchanged=128
  added:
    084  PhysicalUnplug Probe 120910  file=CiqProbe_20260717-120910_fenix6pro  size_or_id=90172  type=1  uuid=3134dc0a8db04016a380e2c9476acd8a
```

File result:

```text
Files:
  before=52 after=52
  added=0 removed=0 changed=1 unchanged=51
  changed:
    ROOT_FILES/OUT.BIN
```

High-signal Windows operational events captured manually for the same window:

```text
Kernel-PnP 1010: USB\VID_091E&PID_4CDA\0000c5dc0f5a surprise removed as missing on the bus
Kernel-PnP 1010: USB\VID_091E&PID_0003\6&3b1c401&0&1 surprise removed as missing on the bus
WPD-MTPClassDriver 1000: MTP Driver started successfully
```

Interpretation: physical unplug is visible to Windows as true USB bus removal, not just WPD session closure. The watch's index pass updates only `OUT.BIN`; the staged PRG file count/content snapshot is otherwise unchanged. The software trigger to emulate is therefore closer to "make the Garmin USB device disappear from the USB bus in the same way physical unplug does" than "ask WPD/MTP to reset/eject." The capture script was updated to include Kernel-PnP/WPD operational logs by default in future runs.

## USB hub port-cycle result

Windows exposes a lower-level hub port-cycle request through `IOCTL_USB_HUB_CYCLE_PORT`. The soft disconnect experiment now supports:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminSoftDisconnectIndexExperiment.ps1 -TryUsbHubPortCycle -BleAddress "F0:99:19:75:41:3E"
```

The script reads the active fenix MTP device properties and targets:

```text
InstanceId: USB\VID_091E&PID_4CDA\0000C5DC0F5A
Parent hub: USB\ROOT_HUB30\5&23a70e4d&0&0
Port: 1
Location: Port_#0001.Hub_#0003
Path: PCIROOT(0)#PCI(0803)#PCI(0004)#USBROOT(0)#USB(1)
```

Non-elevated run:

```text
logs\soft-disconnect-index-experiments\soft-disconnect-20260717-123414
USB hub port-cycle Succeeded=False
Win32Error=31
Error=A device attached to the system is not functioning
Registry: before=129 after=129
Target: SoftDisc Probe 123415 before_matches=0 after_matches=0
```

UAC-elevated Administrator run:

```text
logs\soft-disconnect-index-experiments\soft-disconnect-20260717-123649
App name: SoftDisc Probe 123650
App id: 7BB8864623384CAA98C6EC412D5BE0F0
File: CiqProbe_20260717-123650_fenix6pro
USB hub port-cycle Succeeded=True
Win32Error=0
StatusReturned=0
BytesReturned=8
```

Windows events around the successful hub cycle:

```text
Kernel-PnP 1010: USB\VID_091E&PID_4CDA\0000c5dc0f5a surprise removed as missing on the bus
WPD-MTPClassDriver 1000: MTP Driver started successfully
```

Delayed exact target registry check:

```text
Records decoded: 129
Transfer succeeded but app is not registered in USB/MTP registry
```

Snapshot comparison:

```text
Files:
  before=54 after=55
  added=1 removed=0 changed=0 unchanged=54
  added:
    ROOT_FILES/CiqProbe_20260717-123650_fenix6pro.prg size=90172 sha256=f0160f6aa489fb90

Registry:
  before=129 after=129
  added=0 removed=0 changed=0 unchanged=129

Target:
  filename=CiqProbe_20260717-123650_fenix6pro name=SoftDisc Probe 123650 uuid=7BB8864623384CAA98C6EC412D5BE0F0
  before_matches=0 after_matches=0
```

Conclusion: a real Administrator hub-port cycle is enough for Windows to report the fenix MTP node as missing on the bus and to restart the MTP driver, but it is not enough to make the fenix firmware run the Connect IQ registration pass. Physical unplug remains distinct. The remaining hardware-like trigger is likely actual cable/VBUS loss through a controlled USB switch/relay, or the investigation should move back to Garmin's private Connect IQ app-management/download flow.

New helper:

```text
scripts\Run-GarminSoftDisconnectIndexExperiment.ps1
```

The helper now treats MTP disappearance as expected evidence and can fall back to BLE installed-app verification when `-BleAddress` is supplied.

Evidence folder:

```text
logs\soft-disconnect-index-experiments\soft-disconnect-20260717-011628
logs\soft-disconnect-index-experiments\soft-disconnect-20260717-011628\ble-installed-apps-result.txt
```

## Next useful experiments

Run `--protobuf-listen` while manually provoking watch-side features:

- open a Connect IQ app/widget that fetches data
- trigger a watch sync from the watch UI
- open any CIQ-related watch settings screen
- open LiveTrack/safety features only if you want more field `21` examples

Success for Track 2 means seeing one of these:

- field `2` with a Garmin Connect IQ URL
- field `7` data-transfer requests for a body that looks like an app package/manifest
- field `31` generic item transfer messages
- a new private field near `3` or `4` that appears only around app-management actions

If those fields never appear without Garmin Connect Mobile, the missing installer flow is probably initiated by the official phone app rather than by the watch. In that case the strongest next evidence would be an Android Bluetooth HCI snoop capture from Garmin Connect Mobile installing a known PRG/app.
