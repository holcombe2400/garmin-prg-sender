# iOSWebBLE PRG Sender

Static Web Bluetooth sender for iOSWebBLE.

Host this folder over HTTPS, open `index.html` in Safari with the iOSWebBLE extension enabled, then:

1. Force-close Garmin Connect on the sender iPhone so it does not hold the watch BLE connection.
2. Choose a `.prg`.
3. Leave picker mode on `Garmin filter`, tap `Choose Watch`, and select the target Garmin.
4. Tap `Connect`.
5. If this is the intended watch, tap `Remember` once. Future sends from this browser will be blocked unless the selected WebBLE device id matches the trusted watch.
6. Tick `Confirm target watch`.
7. Tap `Send PRG`.
8. After the transfer completes, let Garmin Connect on the owner phone reconnect and finish Connect IQ registration.

This does not use a native iPhone app. It relies on iOSWebBLE exposing the Web Bluetooth API.

## Identifying the Watch

The Windows BLE address, such as `C0:28:8D:9A:C4:71`, is not exposed to Web Bluetooth/iOSWebBLE. Browsers expose an opaque per-site device id instead. The sender can remember that browser id locally and use it as a safety check, but it cannot pre-filter the iOS picker by the Windows BLE address.

If iOSWebBLE reports that a device "was not offered to this origin via the device picker", refresh the page and retry with `Garmin filter`. Use `Broad picker` only as a fallback when the Garmin-filtered picker cannot see the watch.

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
