# Garmin PRG WebBLE Sender

Static Web Bluetooth sender for Garmin PRG staging. Bluefy is the working iPhone browser path; Safari plus iOSWebBLE/Beacio can see the watch but may fail to grant the selected device back to the page origin.

Host this folder over HTTPS, open `index.html` in Bluefy on iPhone, then:

1. Force-close Garmin Connect on the sender iPhone so it does not hold the watch BLE connection.
2. Choose a `.prg`, load one from `GitHub PRGs`, or load one from `Saved PRGs`. The sender saves valid PRGs locally in Bluefy so you can load them again next time.
3. Leave `Bluetooth API` on `Standard only`, `Picker mode` on `Name filter: fenix 6 Pro`, and `Access mode` on `Garmin transport services`.
4. Tap `Choose Watch`, and select the target Garmin.
5. Tap `Connect`.
6. If this is the intended watch, tap `Remember` once. Future sends from this browser will be blocked unless the selected WebBLE device id matches the trusted watch.
7. Tick `Confirm target watch`.
8. Tap `Send PRG`.
9. After the transfer completes, let Garmin Connect on the owner phone reconnect and finish Connect IQ registration.

This does not use a custom native iPhone app. It relies on Bluefy exposing the Web Bluetooth API.

## Transfer Reliability

Web Bluetooth uploads must stay in the foreground. iOS can suspend Bluefy and break the BLE connection if you answer a call, switch apps, open Control Centre long enough, lock the screen, or let the screen sleep.

The sender includes `Keep screen awake during transfer`, using the browser Screen Wake Lock API when Bluefy exposes it. This can help prevent screen sleep, but it cannot keep a BLE upload alive after an app switch or phone call.

If an upload is interrupted, reopen Bluefy, reconnect the watch, and send the PRG again from `Saved PRGs`. The sender can correct/resend offsets while the same upload session is alive, but it cannot resume a killed Web Bluetooth session after iOS backgrounds the app.

## Bluefy Settings

Recommended defaults:

- Bluetooth API: `Standard only`
- Picker mode: `Name filter: fenix 6 Pro`
- Access mode: `Garmin transport services`

If the name filter cannot see the watch, use `Broad picker`.

## GitHub PRGs

Use `GitHub PRGs` to fetch public `.prg` assets from GitHub Releases. The default repo is:

```text
holcombe2400/garmin-vpet
```

Workflow for working away from the computer:

1. Build VPet PRGs on a computer or GitHub Actions.
2. Attach the `.prg` files to a GitHub Release in `holcombe2400/garmin-vpet`.
3. In Bluefy, tap `Refresh GitHub`.
4. Select a PRG and tap `Load GitHub PRG`.
5. The sender validates the file and saves it locally in `Saved PRGs`.

This only supports public release assets. Do not paste GitHub tokens into the page. For private repos, use a private backend or make only release PRG assets public.

## Saved PRGs

The sender cannot force the iPhone file picker to open a default folder. Instead, it saves valid PRGs locally in the browser after you choose them once.

- Use `Saved PRGs` to load a previously selected file.
- Use `Delete Saved` to remove one.
- The file stays on the device in browser storage; it is not uploaded to GitHub or any server.
- The library keeps up to 12 saved PRGs.

## Beacio Safari Permissions

If the picker sees `fenix 6 Pro` but fails with "was not offered to this origin", check the Safari extension permission:

1. In Safari, tap `aA` in the address bar.
2. Tap the Beacio/iOSWebBLE extension icon.
3. Choose `Always Allow`.
4. Choose `Always Allow on Every Website`.
5. Refresh the sender page.

`Allow for One Day` can expire and leave the picker visible but the page permission broken.

## Identifying the Watch

The Windows BLE address, such as `C0:28:8D:9A:C4:71`, is not exposed to Web Bluetooth/iOSWebBLE. Browsers expose an opaque per-site device id instead. The sender can remember that browser id locally and use it as a safety check, but it cannot pre-filter the iOS picker by the Windows BLE address.

If iOSWebBLE reports that a device "was not offered to this origin via the device picker", the sender retries the alternate Bluetooth API automatically. Use `Garmin filter` or `Broad picker` only as fallbacks when the name-filtered picker cannot see the watch.

The sender also checks Beacio/iOSWebBLE's `referringDevice` and `getDevices()` before opening the picker. If Beacio already has the fenix permission, this avoids the picker-origin handoff bug entirely.

Some iOSWebBLE builds inject `navigator.webble` only after the first picker handoff. If that happens, the first `Choose Watch` tap primes the bridge, switches the sender to `iOSWebBLE only`, and asks you to tap `Choose Watch` again.

`Choose Watch` calls `requestDevice()` directly from the tap. It does not call `getDevices()` first, because iOSWebBLE's native grant flow is sensitive to how the picker is entered.

Use `Access mode` to test whether iOSWebBLE is failing because of Garmin service permissions. Start with `Garmin transport services`. If all picker modes fail, the page advances to `GFDI v2 only`, then `Grant only, no services`. A grant-only selection may not be able to upload, but it proves whether the picker can grant the watch to the page at all.

If the picker sees the watch but does not grant it back to the page, the sender makes only one picker attempt per tap. It then advances the picker mode from name filter to Garmin filter to broad picker so the next tap tests one cleaner variant.

If the picker still rejects a selected device, leave `Picker mode` on `Garmin filter` and try changing `Bluetooth API` from `iOSWebBLE first` to `Standard first`, then `iOSWebBLE only`.

Use `Log Bridge State` when the picker sees the watch but rejects it. Paste the details log back into the debugging thread; it shows whether Beacio is injected, active for the page origin, and which Bluetooth API object the sender is using.

If `Garmin filter` reports no devices, the watch is probably not advertising while Garmin Connect is holding the phone link. Force-close Garmin Connect and put the watch into `Pair Phone` mode long enough to choose it. You do not need to forget the normal pairing for this test.

Use `Scan 20s` when the picker times out quickly. It does not connect to a device or upload anything; it only logs advertisements that iOSWebBLE can see.

## Hosting

iOS Web Bluetooth requires a secure context. GitHub Pages is the simplest path:

```text
https://<user>.github.io/<repo>/ioswebble-sender/
```

If GitHub Pages is configured to publish the repo's `docs` folder, put this folder at:

```text
docs/ioswebble-sender/
```

## Defaults

- GFDI packet size: `375`
- BLE fragment size: `20`
- Write delay: `0 ms`

If iOSWebBLE disconnects or write calls fail, retry with BLE fragment `20` and write delay `2` or `5`.
