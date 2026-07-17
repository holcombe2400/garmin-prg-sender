# Gadgetbridge Garmin PRG Upload Notes

Source reference: Gadgetbridge `master` on Codeberg, saved under `reference/`.

## PRG Recognition

`GarminPrgFile.java` accepts a PRG when the first three bytes are:

```text
D0 00 D0
```

It also applies a defensive 10 MB maximum expected size.

## File Type

`FileType.java` defines Connect IQ PRG uploads as:

```text
data type = 255
subtype   = 17
```

## GFDI Packet Envelope

All file-transfer commands are little-endian GFDI packets:

```text
u16 length_including_crc
u16 message_id
... payload ...
u16 garmin_crc_over_all_previous_bytes
```

Message IDs used for upload:

```text
5000 RESPONSE
5003 UPLOAD_REQUEST
5004 FILE_TRANSFER_DATA
5005 CREATE_FILE
5030 SYSTEM_EVENT
```

## Upload Sequence

1. Send `CREATE_FILE` with file size and file type `255/17`.
2. Wait for `RESPONSE` to `CREATE_FILE`.
3. Extract `fileIndex`; proceed only when status is `ACK` and create status is `OK`.
4. Send `UPLOAD_REQUEST` with the returned `fileIndex`, total size, offset `0`, CRC seed `0`.
5. Wait for `RESPONSE` to `UPLOAD_REQUEST`; proceed only when upload status is `OK` and offset is `0`.
6. Send `FILE_TRANSFER_DATA` chunks. Gadgetbridge default max GFDI packet size is `375`, so data payload is `375 - 13 = 362` bytes.
7. Each chunk includes a running Garmin CRC over all uploaded file bytes so far.
8. Wait for `RESPONSE` to each chunk and verify the returned offset.
9. After the final chunk acknowledgement, send `SYSTEM_EVENT` value `SYNC_COMPLETE`, with byte value `0`.
10. Keep the connection alive long enough for the watch to acknowledge/process `SYNC_COMPLETE`; Gadgetbridge remains connected as a background device service instead of disconnecting immediately after the event.

## Fenix 6 Pro-Relevant Gadgetbridge Notes

The local Windows cache for the target watch found `fenix 6 Pro` at `F0:99:19:75:41:3E`, with Garmin ML/v2 service `6A4E2800-667B-11E3-949A-0800200C9A66`. Gadgetbridge tries the v2 ML transport first and falls back to the older GFDI characteristics only if v2 initialization is not available.

During normal Garmin initialization, Gadgetbridge requests a high MTU, registers the GFDI service, asks for supported file types/settings, and sends `SYSTEM_EVENT SYNC_READY`. During a first-pair setup path, Gadgetbridge also sends `PAIR_COMPLETE`, `SYNC_COMPLETE`, and `SETUP_WIZARD_COMPLETE`.

For Connect IQ `.prg` install, Gadgetbridge does not use `SetFileFlagsMessage`; it uploads raw PRG bytes as file type `255/17` and relies on the final `SYNC_COMPLETE` event to make the watch commit/register the received file. That makes the final system-event acknowledgement and a short post-sync connected delay important for this standalone sender.

Important caveat: the Gadgetbridge Garmin app-management path is not mature proof that arbitrary PRGs can be copied into the watch apps folder. In the local source snapshot, `GarminPrgFile.java` only checks the `D0 00 D0` magic and then says `TODO parse bytes`, while `GarminSupport.java` guards app start/delete behind `garmin_experimental_app_management`. Treat Gadgetbridge as upload-protocol evidence, not a finished Garmin Connect IQ sideload installer.

## External Reverse-Engineering Leads

- Hacker News discussion, July 23 2020: `https://news.ycombinator.com/item?id=23926574`
  - One reverse-engineering effort for Vivofit 3 is at `https://github.com/mjsir911/GarminBLE`; its stated end goal was setting the time, not Connect IQ app sideloading.
  - A Gadgetbridge Garmin WIP fork was mentioned for Vivomove HR.
  - Another commenter reported older Fenix protocol work, but also noted that later protocol generations became encrypted/complicated and were "not an easy task."
  - Practical takeaway: public Garmin BLE reverse engineering exists, but it is fragmented by model/protocol generation and does not prove that PRG app registration is simply a file-copy step.

## USB Sideload Baseline

Garmin's Connect IQ SDK documents the normal developer sideload flow as:

1. Build a device-specific executable with "Build for Device".
2. Plug the Garmin device into the computer.
3. Copy the generated `.prg` file to the device's `GARMIN/APPS` directory.
4. Disconnect/eject the watch so firmware can scan/index the app.

The `.debug.xml` files are for development/debugging and are not part of the normal USB sideload. The `*-settings.json` files describe configurable app settings for tooling; they are not what makes the app install. Runtime settings, data, and logs are app-owned files under Garmin's Connect IQ app storage areas after the app is known to firmware.

This means USB sideload is fundamentally a filesystem install: the watch sees a complete PRG at the expected path, then its firmware indexes it. The Bluetooth sender is trying to trigger the equivalent outcome through Garmin file-transfer messages, but we do not yet know whether a PRG uploaded as file type `255/17` lands in the same internal location/indexing path as `GARMIN/APPS`.

## BLE Framing

GFDI packets are COBS encoded with Garmin's leading and trailing zero byte variant.

### v2 ML GFDI

Gadgetbridge tries v2 first:

```text
service  6A4E2800-667B-11E3-949A-0800200C9A66
receive  6A4E2810..2814-667B-11E3-949A-0800200C9A66
send     receive + 0x10
```

Startup:

1. Enable notifications on the receive characteristic.
2. Send close-all handle management packet.
3. On close-all response, register service `GFDI` code `1`.
4. Use returned handle as a one-byte prefix on every outgoing COBS fragment.

### v1 GFDI Fallback

Gadgetbridge falls back to:

```text
service  6A4E2401-667B-11E3-949A-0800200C9A66
send     6A4E4C80-667B-11E3-949A-0800200C9A66
receive  6A4ECD28-667B-11E3-949A-0800200C9A66
```

Older v0 UUIDs are also in `CommunicatorV1.java`.
