# iOSWebBLE PRG Sender

Static Web Bluetooth sender for iOSWebBLE.

Host this folder over HTTPS, open `index.html` in Safari with the iOSWebBLE extension enabled, then:

1. Force-close Garmin Connect on the sender iPhone so it does not hold the watch BLE connection.
2. Choose a `.prg`.
3. Tap `Choose Watch` and select the target Garmin.
4. Tap `Connect`.
5. Tap `Send PRG`.
6. After the transfer completes, let Garmin Connect on the owner phone reconnect and finish Connect IQ registration.

This does not use a native iPhone app. It relies on iOSWebBLE exposing the Web Bluetooth API.

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
