# Garmin Native Sender

Native CoreBluetooth sender/probe for a jailbroken iPhone 5 on iOS 10.3.4.

This is meant to test whether a native app can do better than the Bluefy/WebBLE bridge and to capture cleaner Garmin protocol traces.

## What It Does

- Scans for Garmin-like BLE advertisements, especially devices advertising `FE1F`.
- Connects to Garmin v2 GATT service `6A4E2800-667B-11E3-949A-0800200C9A66`.
- Uses the first available `2810..2814` notify / `2820..2824` write pair.
- Calls native `maximumWriteValueLengthForType:` and logs the write-without-response and write-with-response limits.
- Registers Garmin GFDI over Multi-Link, requesting reliable MLR.
- Sends a PRG from `/var/mobile/Documents/GarminNativeSender/input.prg`.
- Defaults to the current best web settings: GFDI `3072`, BLE fragment `20`, pipeline `8`, reliable MLR on.
- Records app-level packet traces to JSONL.

## Packet Capture Scope

The built-in trace is an app-level Garmin/BLE trace, not a raw RF sniffer.

It records:

- App BLE writes.
- App BLE notifications.
- Decoded GFDI packets.
- Garmin advertisement candidates.

For the deeper jailbreak packet-sniffer track, see `BTServerSnifferNotes.md`. The root snapshot shows `BTPacketLogger` and HCI logging strings, but that still needs a separate private BTServer client.

## Build On The Jailbroken iPhone

Install Theos on the iPhone, then copy this folder to the device.

```sh
cd /path/to/ios-garmin-sender
make package install
```

If `armv7s` is not supported by the installed compiler/SDK, edit `Makefile` and set:

```make
ARCHS := armv7
```

## PRG Input

Copy the PRG here:

```text
/var/mobile/Documents/GarminNativeSender/input.prg
```

Then open Garmin Sender:

1. Tap `Scan Garmin`.
2. Tap `Connect First`.
3. Wait for `GFDI registered`.
4. Tap `Upload PRG`.
5. Tap `Export Trace` after success or failure.

Trace files are written beside the PRG:

```text
/var/mobile/Documents/GarminNativeSender/garmin-native-trace-*.jsonl
```

## Current Caveats

- This is a first native lab build, not polished UI.
- It targets the Garmin v2 path only.
- It uses `CBCharacteristicWriteWithoutResponse`.
- CoreBluetooth on iOS 10 does not provide the modern `peripheralIsReadyToSendWriteWithoutResponse:` backpressure callback, so MLR ACK/window behavior is the main flow control.
- If the iPhone 5 reports 20-byte native write-without-response length, that strongly supports the current 20-byte ceiling.
