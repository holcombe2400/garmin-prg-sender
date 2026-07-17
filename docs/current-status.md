# Current Status

## Done

- Created the project outside the VPet workspace at:
  `C:\Users\holco\OneDrive\Documents\Garmin PRG Bluetooth Sender`
- Saved a narrow Gadgetbridge Garmin source snapshot under `reference/`.
- Documented the Gadgetbridge PRG upload sequence in `docs/protocol-notes.md`.
- Implemented:
  - PRG validation using Gadgetbridge's `D0 00 D0` magic rule.
  - Garmin CRC and GFDI packet framing.
  - Garmin COBS encode/decode variant.
  - `CREATE_FILE`, `UPLOAD_REQUEST`, `FILE_TRANSFER_DATA`, and `SYNC_COMPLETE` packet builders.
  - Upload response parsers for create, upload, and data-chunk statuses.
  - v2 ML GFDI BLE transport and v1 fallback transport using `bleak`.
  - CLI dry run, richer BLE scan, safe GATT probe, GFDI registration probe, direct WinRT diagnostic, live-GATT wait loop, Windows service-cache option, and live upload entry points.
  - Throttled upload progress output through `--progress-step` instead of one line per chunk.
  - Upload resume/retry support for watch-supplied offsets and recoverable transfer statuses.
  - Optional compact JSONL packet logging via `--packet-log`.
  - Packet-log summaries via `--summarize-log`.
  - Packet-log summary reader tolerates UTF-8 BOM output from PowerShell-created logs.
  - Safer resume CRC fallback when a watch supplies a non-zero offset with a zero CRC seed.
  - Create-file response validation to reject unexpected file type/subtype.
  - V1 write-fragment sizing now follows Gadgetbridge's conservative `maxWriteSize - 1` behavior.
  - V2 GFDI registration failures now surface as explicit errors instead of vague timeouts.
  - Gadgetbridge-style `SYNC_READY` before upload.
  - Final `SYNC_COMPLETE` acknowledgement wait plus a post-sync connected delay so the watch has time to commit/register the PRG.
  - Optional first-connect setup completion events (`PAIR_COMPLETE`, `SYNC_COMPLETE`, `SETUP_WIZARD_COMPLETE`) for watches still stuck in setup mode.
  - Garmin protobuf request/response support for `InstalledAppsService.GetInstalledAppsRequest(ALL)`.
  - Post-upload installed-apps verification that checks for the known-good Garmon app by UUID/name.
  - Standalone installed-apps query command for the post-restart check.
  - One-command PowerShell helper at `scripts/try-watch-upload.ps1` for the next desk attempt.
  - Tkinter GUI at `send_prg_gui.py` with a double-click launcher `Launch Garmin Sender GUI.bat`.
- Created a local `.venv` and installed `bleak`.

## Verified

```powershell
.\.venv\Scripts\python -B -m unittest discover -s tests
```

Result: 7 tests passed.

Latest result after adding protobuf installed-app verification: 29 tests passed.

```powershell
.\.venv\Scripts\python -B .\send_prg.py --file "C:\Users\holco\OneDrive\Documents\Vpet Garmin Fenix 6\bin\VPetV1_fenix6pro.prg" --dry-run
```

Result: PRG validated and upload packets built. The 2,759,548 byte PRG would be sent in 7,624 chunks at Gadgetbridge's default 375 byte GFDI packet size.

```powershell
.\.venv\Scripts\python -B .\send_prg.py --scan
```

Result: command ran, but no BLE devices were found from this shell.

```powershell
.\.venv\Scripts\python -B .\send_prg.py --scan --scan-seconds 12
```

Result: command ran, but no BLE advertisers were found. Windows Bluetooth Support Service was checked and is running.

```powershell
.\.venv\Scripts\python -B .\send_prg.py --winrt-diagnostic --address "F0:99:19:75:41:3E" --connect-timeout 45 --debug
```

Result: Windows returned the paired `fenix 6 Pro` at `F0:99:19:75:41:3E`, address type `public`, paired `True`, with cached Garmin GFDI services including `6a4e2800-667b-11e3-949a-0800200c9a66` and `6a4e8022-667b-11e3-949a-0800200c9a66`. The live GATT session timed out and uncached live services returned `unreachable`.

```powershell
.\.venv\Scripts\python -B .\send_prg.py --list-windows-ble --name fenix --connect-timeout 5 --debug
```

Result: Windows cached device list found `fenix 6 Pro`, extracted address `F0:99:19:75:41:3E`, `device_paired=yes`, status `disconnected`, address type `public`.

## Not Yet Verified

- Fresh watch pairing that can open a live GATT session.
- Safe `--probe` / `--probe-gfdi` against the watch once Windows can open live GATT.
- Actual PRG upload/install on the Garmin watch.
- Whether the Fenix firmware will register this uploaded PRG as an installed Connect IQ app. Gadgetbridge provides the upload/sync packet path, but its Garmin PRG parsing is still marked TODO and its app-management controls are explicitly experimental.
- Optional Gadgetbridge MLR reliable transport. Gadgetbridge keeps this behind a preference, and this sender currently requests normal non-MLR v2 GFDI.

## Next Hands-On Sequence

When the watch and PC are together again:

```powershell
.\.venv\Scripts\python -B .\send_prg.py --wait-live --address "F0:99:19:75:41:3E" --connect-timeout 20 --wait-seconds 300
.\.venv\Scripts\python -B .\send_prg.py --probe-gfdi --address "F0:99:19:75:41:3E" --winrt-services cached --connect-timeout 75 --debug
.\.venv\Scripts\python -B .\send_prg.py --file "C:\Users\holco\OneDrive\Documents\Vpet Garmin Fenix 6\apps\dpower\bin\DPowerLCD_fenix6pro.prg" --address "F0:99:19:75:41:3E" --winrt-services cached --connect-timeout 75 --timeout 30 --sync-timeout 20 --post-sync-delay 8 --debug
```

Or run the scripted version from the sender project folder. It sends the smaller DPower PRG first, writes a compact packet log under `logs\`, and prints a summary if a log exists:

```powershell
.\scripts\try-watch-upload.ps1
```

Or use the GUI:

```text
Launch Garmin Sender GUI.bat
```

Manual packet-log summary command:

```powershell
.\.venv\Scripts\python -B .\send_prg.py --summarize-log .\logs\manual-upload.jsonl
```

If `--wait-live` keeps reporting `live_gatt=unreachable`, remove `fenix 6 Pro` from Windows Bluetooth settings, put the watch back in `Pair Phone`, pair it again, and rerun `--wait-live`.

If a live send reports `Transfer succeeded but app is not registered`, restart the watch and run:

```powershell
.\.runtime\Scripts\python.exe -B .\send_prg.py --query-installed-apps --address "F0:99:19:75:41:3E" --winrt-services cached --connect-timeout 75 --timeout 30 --show-installed-apps
```

If Garmon is still absent after restart, treat this GFDI PRG upload path as a byte-transfer path, not a usable Connect IQ sideload installer on this watch firmware. The next reverse-engineering target is Garmin's Connect IQ app-management/download flow, not ANT or another raw file-transfer radio path.
