# Garmin PRG Bluetooth Sender

Standalone work area for reverse-engineering Gadgetbridge's Garmin PRG upload path and building a simple Bluetooth sender for Connect IQ `.prg` files.

The implementation in this folder is intentionally separate from the VPet Garmin app workspace.

## Current Shape

- `reference/` contains a narrow snapshot of upstream Gadgetbridge Garmin source files used as protocol evidence.
- `src/garmin_prg_sender/` contains a clean Python implementation of the packet builders, COBS framing, upload state machine, and BLE transports.
- `send_prg.py` is the command-line entry point.

## Setup

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
```

## Dry Run

This validates a PRG and builds the same first packets the live sender will use, without touching Bluetooth:

```powershell
python .\send_prg.py --file "C:\path\to\app.prg" --dry-run
```

## Live Send

Pair the watch with Windows first, then use either the BLE address or part of the watch name:

```powershell
.\.venv\Scripts\python .\send_prg.py --scan
.\.venv\Scripts\python .\send_prg.py --list-windows-ble --name fenix
.\.venv\Scripts\python .\send_prg.py --winrt-diagnostic --address "PASTE_WATCH_ADDRESS_HERE"
.\.venv\Scripts\python .\send_prg.py --wait-live --address "PASTE_WATCH_ADDRESS_HERE"
.\.venv\Scripts\python .\send_prg.py --probe --address "PASTE_WATCH_ADDRESS_HERE"
.\.venv\Scripts\python .\send_prg.py --probe-gfdi --address "PASTE_WATCH_ADDRESS_HERE"
.\.venv\Scripts\python .\send_prg.py --file "C:\path\to\app.prg" --name "fenix" --progress-step 5 --sync-timeout 20 --post-sync-delay 8
```

## BLE Stage, Then Garmin Connect Phone Sync

The practical no-cable path is now:

1. Stage the PRG to the watch over Bluetooth from this sender.
2. Re-enable the paired phone's Bluetooth so Garmin Connect can reconnect in the background.
3. Let Garmin Connect trigger the Connect IQ registration/install pass. Opening Garmin Connect or forcing sync is a useful fallback, but it was not required in the clean proof run.

This was proven when `BLE Probe 002604`, uploaded earlier over BLE, installed after the watch was reconnected to Garmin Connect on iPhone. The BLE packet log showed the PRG bytes were fully acknowledged by the watch; the later phone sync supplied the missing registration step.

CLI:

```powershell
.\.runtime\Scripts\python.exe -B .\send_prg.py --stage-for-garmin-connect --file "C:\path\to\app.prg" --address "F0:99:19:75:41:3E" --winrt-services uncached --connect-timeout 75 --timeout 30 --sync-timeout 20 --progress-step 5 --upload-retries 5 --debug
```

GUI:

```text
Use Send PRG to Watch, then re-enable phone Bluetooth so Garmin Connect can reconnect.
```

The staged mode treats full PRG byte acknowledgement as success and intentionally skips immediate installed-app verification. It writes a packet log plus a `.next-steps.txt` beside the log. Use `Check Install` after the phone sync if you want BLE registry confirmation from the sender.

Verified proof on 2026-07-18:

```text
PhoneSync Probe 003151
PRG bytes staged over BLE: 90140/90140
Garmin Connect phone sync registered the app
Installed-app verification: PhoneSync Probe 003151 is registered

PhoneSync Probe 004824
PRG bytes staged over BLE: 90140/90140
Post-upload trigger: none
Re-enabling iPhone Bluetooth registered the app without opening Garmin Connect
Installed-app verification: PhoneSync Probe 004824 is registered
```

For clean repeatable proof, generate a fresh tiny app, stage it, then look for that exact app name after phone Bluetooth reconnects:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-PhoneSyncStageExperiment.ps1 -Address "F0:99:19:75:41:3E" -WinrtServices uncached -PostUploadTrigger none
```

The script writes a timestamped folder under `logs\phone-sync-stage-experiments` with the generated app metadata, packet log, packet summary, and `NEXT-STEPS.txt`. To run the installed-app check after phone Bluetooth reconnects, add `-WaitForPhoneSync`.

The staging step still needs the target watch reachable from Windows Bluetooth with live GATT available. The Garmin Connect phone pairing is the second step, used after staging to trigger Connect IQ registration. If the watch keeps reconnecting to an iPhone first, temporarily disable iPhone Bluetooth from Settings, stage from Windows, then turn iPhone Bluetooth back on. Forgetting the fenix on the iPhone is a fallback, not required in the successful proof.

## GUI

For a click-based interface, double-click:

```text
Garmin PRG Sender Simple.exe
```

The batch launcher does the same thing and is useful as a fallback:

```text
Launch Garmin Sender GUI.bat
```

The GUI is intentionally simple now:

1. Choose a `.prg`.
2. Turn phone Bluetooth off so Windows can keep the watch BLE connection.
3. Click `Connect / Check Watch`.
4. Click `Send PRG to Watch` and wait for the load bar to reach 100%.
5. Turn phone Bluetooth back on. Garmin Connect should reconnect in the background and finish the Connect IQ install.

Use `Show Details` only when you want the command log. `Check Install` queries the watch's installed-app registry after the phone sync has had time to run. `stage-for-phone-sync-latest.jsonl` is replaced on each new send so the details log and summary reflect the latest run.

On Windows, if the paired watch shows the right cached Garmin services but live GATT is unreachable, start `--wait-live`, then put the watch back into pairing mode. Once `--wait-live` reports reachable services, use `--probe-gfdi`; if that succeeds, send the PRG. `--winrt-services cached` can be added to `--probe`, `--probe-gfdi`, or live send commands when Windows already has the Garmin service list cached.

There is also a one-command helper for the next desk attempt. It lists the cached Fenix, waits for live Garmin GATT, probes GFDI, then sends the smaller DPower PRG first:

```powershell
.\scripts\try-watch-upload.ps1
```

That helper writes a compact packet log under `logs\` during the send step and prints a summary when a log exists. For manual runs, add `--packet-log logs\manual-upload.jsonl` to capture GFDI transmit/receive metadata, then summarize it with:

```powershell
.\.venv\Scripts\python -B .\send_prg.py --summarize-log .\logs\manual-upload.jsonl
```

The first implementation supports Gadgetbridge's normal v2 ML GFDI transport and the older v1 COBS transport. Gadgetbridge's optional reliable MLR mode is documented in `reference/MlrCommunicator.java` but not enabled by default in this sender yet.

For direct Fenix 6 Pro install attempts, the sender sends Gadgetbridge's `SYNC_READY` event before upload, waits for the final `SYNC_COMPLETE` acknowledgement, and can query installed apps afterward. Direct BLE upload alone still does not immediately register the PRG on the tested firmware; use `--stage-for-garmin-connect` when the intended finish step is a Garmin Connect phone sync.

After upload, the sender now queries Garmin's installed-apps protobuf service and checks for the known-good Garmon app (`d036558e-537b-4aa3-aac9-c23c7ba27344`, `Garmon`). The GUI/details log will report one of:

```text
Transfer succeeded and app is registered
Transfer succeeded but app is not registered
Unable to query installed apps
```

To query again after restarting the watch, run:

```powershell
.\.runtime\Scripts\python.exe -B .\send_prg.py --query-installed-apps --address "F0:99:19:75:41:3E" --winrt-services cached --connect-timeout 75 --timeout 30 --show-installed-apps
```

## USB Registry Check

When the watch is connected by data cable, this command copies and decodes `GARMIN\Apps\OUT`, the on-watch Connect IQ registry/index file:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Check-GarminAppsRegistryMtp.ps1 -DevicePattern "fenix|Garmin" -FileName "GarmonInstallTest_fenix6pro_43KB" -FileOnly
```

Verified result on the fenix 6 Pro after USB indexing:

```text
Transfer succeeded and app is registered in USB/MTP registry
  073  Garmon  file=GarmonInstallTest_fenix6pro_43KB  size_or_id=43148  type=1  uuid=d036558e537b4aa3aac9c23c7ba27344
```

Negative control against `TinyTransferTest_64bytes` correctly reports:

```text
Transfer succeeded but app is not registered in USB/MTP registry
```

## USB Soft Install

This is not cable-free, but it is the first repeatable non-physical-unplug registration trigger found. It stages a PRG over MTP, restarts the Windows Garmin WPD/MTP device with `pnputil /restart-device`, then verifies the app through the BLE installed-apps service:

```powershell
.\.runtime\Scripts\python.exe -B .\send_prg.py --usb-soft-install --file ".\test-prgs\GarmonInstallTest_fenix6pro_43KB.prg" --address "F0:99:19:75:41:3E" --usb-timeout 180 --usb-mtp-return-timeout 45 --debug
```

Observed proof case:

```text
SoftDisc Probe 011629 is registered
```

Important caveat: after the WPD restart, Windows may leave the watch in `Garmin USB GPS` mode (`PID_0003`) instead of normal MTP (`PID_4CDA`). A follow-up `pnputil /restart-device` against the `Garmin USB GPS` device returned `Access is denied`, so physically unplug/replug the watch to restore normal MTP access.

The standard Windows Portable Devices commands were also tested directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-WpdDeviceCommand.ps1 -Command ListRootObjects -DevicePattern "fenix|Garmin"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-WpdDeviceCommand.ps1 -Command ResetDevice -DevicePattern "fenix|Garmin" -Access ReadWrite
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-WpdDeviceCommand.ps1 -Command StorageEject -DevicePattern "fenix|Garmin" -ObjectId "s20001" -Access ReadWrite
```

On this fenix 6 Pro, root storage enumerated as `s20001`, but both WPD `ResetDevice` and `StorageEject` returned `E_NOTIMPL` from the Garmin WPD driver. The working soft trigger remains the lower-level PnP restart path, not a normal WPD command.

There is also an experimental Windows Configuration Manager eject path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminSoftDisconnectIndexExperiment.ps1 -TryPnpEject -BleAddress "F0:99:19:75:41:3E"
```

This calls `CM_Request_Device_EjectW` for the Garmin WPD device. It succeeded (`Veto=Ok`) and MTP disappeared, but the watch screen did not change and BLE verification timed out while the watch was in the ejected USB state. Treat this as a Windows-side WPD eject, not a proven watch-side indexing trigger.

There is also a targeted USB hub port-cycle path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminSoftDisconnectIndexExperiment.ps1 -TryUsbHubPortCycle -BleAddress "F0:99:19:75:41:3E"
```

This uses the fenix PnP properties to find the parent USB hub and 1-based port, then sends `IOCTL_USB_HUB_CYCLE_PORT`. It must run from an Administrator PowerShell. The UAC-elevated proof run succeeded at the USB layer:

```text
USB hub port-cycle Succeeded=True StatusReturned=0
Kernel-PnP 1010: USB\VID_091E&PID_4CDA\0000c5dc0f5a surprise removed as missing on the bus
```

But the fresh probe app still did not register:

```text
Registry: before=129 after=129
Target: SoftDisc Probe 123650 before_matches=0 after_matches=0
```

So a Windows hub-port reset is not the same trigger as physically unplugging the cable on this watch. The remaining "fake USB unplug" option is likely an external USB switch/relay that physically drops the cable or VBUS state, not another WPD/MTP command.

## USB Snapshot And Index Diff

For the next install experiment, use the snapshot/diff tools to capture exactly what changes when the watch indexes a PRG after USB disconnect.

Collect a read-only snapshot of the current `GARMIN\Apps` tree:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Collect-GarminAppsSnapshotMtp.ps1 -DevicePattern "fenix|Garmin" -Label current
```

Run a guided USB index experiment. This collects `before`, copies the PRG, waits for you to unplug/replug the watch, collects `after`, then writes `snapshot-diff.txt/json`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminUsbIndexExperiment.ps1 -Prg ".\test-prgs\GarmonInstallTest_fenix6pro_43KB.prg" -DevicePattern "fenix|Garmin"
```

For the cleanest index-registration proof, generate a brand-new tiny Connect IQ probe app with a unique name and UUID, then run the same USB index experiment:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-FreshCiqProbeUsbExperiment.ps1 -DevicePattern "fenix|Garmin"
```

The fresh probe flow lets the diff identify the exact new `GARMIN\Apps\OUT` registry row by generated app name, UUID, and PRG filename, instead of relying on a previously installed app.

## Physical Unplug Trigger Capture

To better understand the physical unplug trigger, use the two-phase capture. The before phase generates a fresh probe, records USB/PnP/WPD state and Windows event-log context, stages the PRG over MTP, and writes next-step instructions:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminPhysicalUnplugTriggerCapture.ps1 -Phase Before
```

Then physically unplug the watch, note whether/when the loading/indexing screen appears, wait for it to finish, reconnect the watch, and run the after phase using the experiment folder printed in `NEXT-STEPS.txt`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminPhysicalUnplugTriggerCapture.ps1 -Phase After -ExperimentDir ".\logs\physical-unplug-trigger-captures\physical-unplug-YYYYMMDD-HHMMSS"
```

The capture writes PnP state, WPD root storage state, `GARMIN\Apps` snapshots, `OUT` registry diffs, System USB/PnP event-log rows, and `setupapi.dev.log` excerpts. This helps separate the watch-side firmware indexing event from Windows-only WPD/MTP disappearance.

## Fresh Probe BLE Trigger Experiment

To test the no-cable path with the same clean-proof approach, unplug the watch from USB, make sure it is in normal watch mode, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-FreshCiqProbeBleExperiment.ps1 -Address "F0:99:19:75:41:3E" -StopOnRegistered
```

This builds a new tiny CIQ probe for each BLE trigger, uploads it over GFDI, and verifies the generated app UUID/name through Garmin's installed-apps protobuf service. Each trigger gets a separate output log and packet log under `logs\fresh-ble-experiments`.

The newest session-transition trigger is `device-disconnect`. It uploads the PRG, sends normal `SYNC_COMPLETE`, then sends Garmin's known `DEVICE_DISCONNECT` system event and verifies after reconnect. That is the closest BLE-side test to the USB/PnP result where ending the device session made the watch register the staged app:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-FreshCiqProbeBleExperiment.ps1 -Address "F0:99:19:75:41:3E" -Triggers device-disconnect -StopOnRegistered
```

## Garmin Express IQ Store Experiment

To capture an official IQ Store install through Garmin Express, connect the watch by USB and collect the before state:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminExpressIqExperiment.ps1 -Phase Before -DevicePattern "fenix|Garmin"
```

Then use Garmin Express to install one free IQ Store app that is not already on the watch. After Garmin Express finishes syncing, unplug the watch, wait until its loading/indexing screen is done, reconnect it, and run the after phase using the experiment folder printed by the before phase:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminExpressIqExperiment.ps1 -Phase After -ExperimentDir ".\logs\garmin-express-iq-experiments\express-iq-YYYYMMDD-HHMMSS"
```

This writes a watch diff (`watch-snapshot-diff.txt/json`) and a lightweight Garmin PC-folder diff (`pc-diff.txt/json`) so we can see both the on-watch registry changes and any Garmin Express download/cache artifacts.

Compare two existing snapshots manually:

```powershell
.\.runtime\Scripts\python.exe -B .\scripts\Compare-GarminAppsSnapshots.py ".\logs\usb-index-experiments\experiment-YYYYMMDD-HHMMSS\before" ".\logs\usb-index-experiments\experiment-YYYYMMDD-HHMMSS\after" --target-filename "GarmonInstallTest_fenix6pro_43KB" --text ".\logs\usb-index-experiments\experiment-YYYYMMDD-HHMMSS\snapshot-diff.txt" --json ".\logs\usb-index-experiments\experiment-YYYYMMDD-HHMMSS\snapshot-diff.json"
```

Current baseline collected on 2026-07-16 at 23:50:

```text
logs\usb-snapshots\current-20260716-235019
```

It matched the prior USB Probe capture: 120 registry records, no registry changes, and Garmon still registered.

## Track 2: BLE CIQ App-Management Discovery

The no-cable path now has a safe protobuf listener for Garmin's private `Smart` services:

```powershell
.\.runtime\Scripts\python.exe -B .\send_prg.py --protobuf-listen --address "F0:99:19:75:41:3E" --winrt-services cached --connect-timeout 75 --timeout 5 --listen-seconds 120 --listen-phone-events --listen-http-unknown --packet-log logs\track2-protobuf-listen.jsonl --packet-log-bytes 512 --debug
```

It decodes watch-originated protobuf services, including private Connect IQ fields when they appear. The first live fenix 6 Pro capture only showed `LIVE_TRACK_SERVICE`, notification subscription, configuration, and device information. See `docs/track2-ble-ciq-app-management.md` for the current evidence and next experiments.

For a packaged remote-install hunt session, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminRemoteInstallHunt.ps1 -Address "F0:99:19:75:41:3E" -ListenSeconds 300 -WinRtServices uncached
```

If the baseline run only shows LiveTrack/notification traffic, try one more phone-like run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-GarminRemoteInstallHunt.ps1 -Address "F0:99:19:75:41:3E" -ListenSeconds 300 -WinRtServices uncached -SetupEvents
```

While it is connected, use the watch to provoke sync or Connect IQ/phone-data actions. The script writes a timestamped folder under `logs\remote-install-hunts` containing:

```text
protobuf-listen-transcript.txt
protobuf-packets.jsonl
packet-summary.txt
interesting-lines.txt
NEXT-STEPS.txt
```

Useful hits are `CONNECT_IQ_HTTP_SERVICE` URLs, `DATA_TRANSFER_SERVICE` download requests, `GENERIC_ITEM_TRANSFER_SERVICE`, or unknown Smart fields that appear only around app-management actions. If these never appear from watch-side actions, the official Bluetooth install is probably initiated by Garmin Connect Mobile rather than by the watch.

Important caveat: Gadgetbridge's Garmin PRG path is still experimental evidence, not a complete documented sideload installer. Its PRG parser is still marked TODO in the local source snapshot, and Garmin app-management actions are gated behind an experimental setting.

## Git Workflow

This is the active source repo for the Garmin PRG Bluetooth/USB sender. Work here, not in OneDrive.

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pip install pytest
.\scripts\test.ps1 -Python .\.venv\Scripts\python.exe
```

Build/test outputs, logs, virtual environments, test PRGs, and packaged `.exe` files are ignored. Publish known-good executables through GitHub Releases.
