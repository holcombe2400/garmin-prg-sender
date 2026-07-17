# Watch-To-Watch PRG Sender Feasibility

## Goal

Build a Connect IQ app that runs on the sender watch, stages a `.prg` to another Garmin watch over BLE/GFDI, then lets the recipient's Garmin Connect phone sync complete Connect IQ registration.

This would mimic the proven Windows flow:

1. Stage PRG bytes to the recipient watch over Garmin GFDI BLE.
2. Recipient turns phone Bluetooth/Garmin Connect back on.
3. Garmin Connect completes app registration.

## Current Feasibility Call

This is worth testing, but it should be treated as a narrow proof ladder, not a guaranteed full VPet sender yet.

The most realistic first target is a tiny embedded probe PRG, not VPet V2.

Reasons:

- fēnix 6 Pro supports `Toybox.BluetoothLowEnergy` for watch apps.
- The CIQ BLE API can scan, pair, register GATT profiles, access services/characteristics, write values, and receive notifications.
- The Garmin GFDI service/characteristics are visible on the receiving fenix 6 Pro:
  - service `6a4e2800-667b-11e3-949a-0800200c9a66`
  - receive notify characteristics `6a4e2810` through `6a4e2814`
  - send write characteristics `6a4e2820` through `6a4e2824`
- But CIQ characteristic writes are limited to 20 bytes, so every GFDI/COBS frame must be fragmented into 20-byte writes.
- A CIQ app cannot read arbitrary files from `GARMIN\Apps`, so it cannot copy an already installed app's PRG from the sender watch.
- `Application.Storage` values are limited to 32 KB each and object-store space varies by device, so it is not a good place for multi-megabyte PRGs.
- fēnix 6 Pro watch apps have a 1,310,720 byte memory limit. Current VPet V2 PRGs are about 2,969,276 bytes, before adding sender code or encoding overhead.

## Payload Reality

Measured local PRG sizes:

```text
VPetRunField_fenix6pro.prg       98,828 bytes
VPetFace_fenix6pro.prg          103,676 bytes
DPowerLCD_fenix6pro.prg         528,204 bytes
VPetV2_fenix6pro.prg          2,969,276 bytes
```

Small apps or a tiny proof PRG may be possible to embed as chunked resources/source data. VPet V2 is probably too large for a fēnix 6 Pro sender app unless it is radically split, compressed, or fetched through a phone/cloud path.

## Implementation Ladder

### Gate 1: BLE/GFDI Connector Probe

Build a CIQ watch app named something like `Watch GFDI Probe`.

It should:

- request `BluetoothLowEnergy` permission
- scan for nearby BLE devices
- show RSSI/name/address-ish identifiers
- register the Garmin v2 GFDI profile
- pair/connect to a selected recipient watch
- locate service `6a4e2800-667b-11e3-949a-0800200c9a66`
- enable notifications on `6a4e2810`
- write the v2 management `CLOSE_ALL` request to `6a4e2820`
- wait for the management response
- write `REGISTER_ML` for GFDI service `1`
- display whether a GFDI handle was assigned

Success means:

```text
Target watch found
GFDI service found
Notifications enabled
GFDI handle assigned
```

If this gate fails, full watch-to-watch sending is blocked at the Connect IQ BLE/security layer.

### Gate 2: GFDI System Event Probe

After GFDI registration works, port only the small protocol pieces needed to send:

- COBS encode/decode
- Garmin CRC
- GFDI frame wrapper
- `SYNC_READY`
- `SYNC_COMPLETE`
- `SUPPORTED_FILE_TYPES_REQUEST`

Success means the sender watch receives normal GFDI ACK/status frames from the recipient watch.

### Gate 3: Tiny PRG Stage

Embed a very small known-good PRG in the sender app, probably the existing ~90 KB fresh probe app or a smaller generated CIQ proof app.

Port:

- `CREATE_FILE`
- `UPLOAD_REQUEST`
- `FILE_TRANSFER_DATA`
- running CRC
- retry on `RESEND`
- progress display
- final `SYNC_COMPLETE`

Success means:

```text
Uploaded 100%
Recipient phone Bluetooth/Garmin Connect reconnects
Recipient watch shows Connect IQ installed message
```

### Gate 4: Payload Packaging

Only after Gate 3 works, decide how to package real apps:

- Small apps: chunked string/JSON resources may be acceptable.
- Medium apps: possible but slow and memory-sensitive.
- VPet V2-sized apps: likely not practical on fēnix 6 Pro as a self-contained watch sender.

For VPet V2, better product options are:

- make a smaller "shareable demo" PRG under ~100 KB
- split the VPet family into smaller installable apps
- use the watch app as a picker/remote and have a phone/PC/cloud sender provide the actual PRG bytes
- investigate Garmin Connect's official app-management/download flow rather than raw embedded PRG transfer

## Expected User Flow If It Works

Sender watch:

1. Open `Watch PRG Sender`.
2. Choose payload.
3. Scan/select recipient watch.
4. Send.

Recipient:

1. Temporarily stop phone from holding BLE, if needed.
2. Allow/enter pairing mode if the target watch asks.
3. Wait for sender upload to finish.
4. Turn phone Bluetooth back on.
5. Garmin Connect registers the staged app.

## Main Unknowns

- Whether a Connect IQ app can pair/connect to another Garmin watch's private GFDI service in practice.
- Whether the target watch exposes the same GFDI characteristics to a CIQ-originated central connection.
- Whether Garmin firmware rejects the sender because it is another Garmin watch rather than a phone/PC BLE stack.
- Whether 20-byte write throughput is tolerable for anything larger than a tiny app.
- Whether a payload large enough to be useful can be embedded without exceeding compile-time/runtime memory limits.

## Next Recommended Step

Build Gate 1 only.

Do not port the PRG uploader yet. First prove that the sender watch can connect to a recipient watch and get a GFDI handle. That is the smallest experiment that can kill or unlock the whole idea.
